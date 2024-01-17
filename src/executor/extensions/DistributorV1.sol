// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IDistributor} from "../interfaces/IDistributor.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Ownable1Or2StepUpgradeable} from "src/utils/Ownable1Or2StepUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Treasurer} from "../base/Treasurer.sol";
import {SelfAuthorized} from "../base/SelfAuthorized.sol";
import {ERC165Verifier} from "src/libraries/ERC165Verifier.sol";
import {IERC20Snapshots} from "src/token/interfaces/IERC20Snapshots.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Utils} from "src/libraries/ERC20Utils.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/**
 * @title DistributorV1
 * @author Ben Jett - @BCJdevelopment
 * @notice An extension implementation contract for use with the Executor. Allows creating distributions for share
 * holders using any given ERC20 asset. The share holder token must implement balance snapshots to allow this contract
 * to calculate distribution claims.
 */
contract DistributorV1 is
    ContextUpgradeable,
    UUPSUpgradeable,
    Ownable1Or2StepUpgradeable,
    EIP712Upgradeable,
    NoncesUpgradeable,
    ERC165Upgradeable,
    IDistributor
{
    using ERC20Utils for IERC20;
    using Address for address;
    using ERC165Verifier for address;

    bytes32 private immutable CLAIM_DISTRIBUTION_TYPEHASH = keccak256(
        "ClaimDistribution(uint256 distributionId,address holder,address receiver,uint256 nonce,uint256 deadline)"
    );

    struct Distribution {
        // Slot 0 (32 bytes)
        uint128 totalBalance;
        uint128 claimedBalance;
        // Slot 1 (32 bytes)
        uint48 snapshotId;
        uint208 cachedTotalSupply;
        // Slot 2 (27 bytes)
        IERC20 asset;
        uint48 closableAt;
        bool isClosed;
        // Slot 3
        mapping(address => bool) hasClaimed;
    }

    /// @custom:storage-location erc7201:DistributorV1.Storage
    struct DistributorStorage {
        // Slot 0 (32 bytes)
        uint48 _claimPeriod;
        uint208 _distributionsCount;
        // Slot 1 (20 bytes)
        IERC20Snapshots _token;
        // Slot 2
        mapping(uint256 distributionId => Distribution) _distributions;
        // Slot 3
        mapping(address account => bool isApprovedToClose) _closeDistributionsApproval;
        // Slot 4
        mapping(address holder => mapping(address account => bool isApprovedToClaim)) _claimDistributionsApproval;
    }

    // keccak256(abi.encode(uint256(keccak256("DistributorV1.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant DISTRIBUTOR_STORAGE = 0x62b10fc09c55e175618e56747e3614a6f67f4f2e694c3dd05aa5dc47edf79c00;

    function _getDistributorStorage() private pure returns (DistributorStorage storage $) {
        assembly {
            $.slot := DISTRIBUTOR_STORAGE
        }
    }

    uint256 private constant MASK_UINT128 = 0xffffffffffffffffffffffffffffffff;

    uint256 public constant MAX_DISTRIBUTION_AMOUNT = type(uint128).max;

    event DistributionCreated(
        uint256 indexed distributionId,
        IERC20 indexed asset,
        uint256 indexed balance,
        uint256 snapshotId,
        uint256 closableAt
    );
    event DistributionClaimPeriodUpdate(uint256 oldClaimPeriod, uint256 newClaimPeriod);
    event CloseDistributionsApprovalUpdate(address indexed account, bool indexed isApproved);
    event DistributionClosed(uint256 indexed distributionId, IERC20 asset, uint256 reclaimAmount);
    event ClaimDistributionsApprovalUpdate(address indexed holder, address indexed account, bool indexed isApproved);
    event DistributionClaimed(uint256 indexed distributionId, address indexed holder, IERC20 asset, uint256 amount);

    error Unauthorized();
    error InvalidSnapshotId(uint256 currentClock, uint256 snapshotClock);
    error DistributionAmountTooLow();
    error DistributionAmountTooHigh(uint256 maxAmount);
    error InvalidMsgValue();
    error ETHTransferFailed();
    error OwnerAuthorizationRequired();
    error DistributionDoesNotExist();
    error DistributionIsClosed();
    error DistributionClaimsStillActive(uint256 closableAt);
    error DistributionAlreadyClaimed(address holder);
    error TokenTotalSupplyIsZero(address token, uint256 snapshotId);
    error ClaimsExpiredSignature();
    error ClaimsInvalidSignature();

    modifier requireOwnerAuthorization() {
        if (SelfAuthorized(owner()).getAuthorizedOperator() != address(this)) {
            revert OwnerAuthorizationRequired();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * By default, initializes to the msg.sender being the owner.
     */
    function setUp(address token_, uint256 claimPeriod_) external virtual override initializer {
        DistributorStorage storage $ = _getDistributorStorage();

        __Ownable_init_unchained(msg.sender);
        __EIP712_init("DistributorV1", "1");

        token_.checkInterfaces([type(IERC20Snapshots).interfaceId, type(IERC6372).interfaceId]);
        $._token = IERC20Snapshots(token_);

        _setDistributionClaimPeriod(claimPeriod_);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        // forgefmt: disable-next-item
        return
            interfaceId == type(IDistributor).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * Returns the address of the token used for calculating each holder's distribution share.
     */
    function token() public view virtual returns (address _token) {
        _token = address(_getDistributorStorage()._token);
    }

    /**
     * Returns the current distribution claim period. This is the minimum time period, in seconds, that a distribution
     * will be claimable by token holders.
     */
    function distributionClaimPeriod() public view virtual returns (uint256 claimPeriod) {
        claimPeriod = _getDistributorStorage()._claimPeriod;
    }

    /**
     * Updates the distribution claim period.
     * @notice Only callable by the owning contract.
     * @param newClaimPeriod The new minimum claim period, in seconds (no greater than type(uint48).max)
     */
    function setDistributionClaimPeriod(uint256 newClaimPeriod) external virtual onlyOwner {
        _setDistributionClaimPeriod(newClaimPeriod);
    }

    function _setDistributionClaimPeriod(uint256 newClaimPeriod) internal virtual {
        DistributorStorage storage $ = _getDistributorStorage();
        emit DistributionClaimPeriodUpdate($._claimPeriod, newClaimPeriod);
        $._claimPeriod = SafeCast.toUint48(newClaimPeriod);
    }

    /**
     * Returns the total count of distributions so far.
     */
    function distributionsCount() public view virtual returns (uint256 _distributionsCount) {
        _distributionsCount = _getDistributorStorage()._distributionsCount;
    }

    /**
     * Check the closable status for a distribution. Returns false for distributions that are already closed.
     */
    function isDistributionClosable(uint256 distributionId) public view virtual returns (bool) {
        DistributorStorage storage $ = _getDistributorStorage();
        Distribution storage _distribution = $._distributions[distributionId];
        _checkDistributionExistence(_distribution);

        uint256 closableAt = _distribution.closableAt;
        bool isClosed = _distribution.isClosed;

        if (isClosed || block.timestamp < closableAt) {
            return false;
        }
        return true;
    }

    /**
     * Returns true if the distribution has been closed.
     */
    function isDistributionClosed(uint256 distributionId) public view virtual returns (bool isClosed) {
        Distribution storage _distribution = _getDistributorStorage()._distributions[distributionId];
        _checkDistributionExistence(_distribution);

        isClosed = _distribution.isClosed;
    }

    /**
     * Returns true if the specified account holder has claimed the distriution ID.
     */
    function accountHasClaimedDistribution(
        uint256 distributionId,
        address holder
    )
        public
        view
        virtual
        returns (bool hasClaimed)
    {
        Distribution storage _distribution = _getDistributorStorage()._distributions[distributionId];
        _checkDistributionExistence(_distribution);

        hasClaimed = _distribution.hasClaimed[holder];
    }

    /**
     * Returns the data for the given distribution ID.
     * @return totalBalance The total balance of the asset for distribution to share holders.
     * @return claimedBalance The total amount of balance claimed by share holders.
     * @return asset The address of the ERC20 asset for the distribution (address(0) for ETH).
     * @return snapshotId The token snapshot ID for this distribution.
     * @return closableAt The clock unit when this distribution will be closable.
     * @return isClosed A bool that is true if the distribution has been closed.
     */
    function getDistributionData(uint256 distributionId)
        public
        view
        virtual
        returns (
            uint256 totalBalance,
            uint256 claimedBalance,
            IERC20 asset,
            uint256 snapshotId,
            uint256 closableAt,
            bool isClosed
        )
    {
        Distribution storage _distribution = _getDistributorStorage()._distributions[distributionId];
        (totalBalance, claimedBalance) = _checkDistributionExistence(_distribution);
        asset = _distribution.asset;
        snapshotId = _distribution.snapshotId;
        closableAt = _distribution.closableAt;
        isClosed = _distribution.isClosed;
    }

    /**
     * Creates a new distribution for share holders.
     * @notice Only callable by the owner (see dev note about authorized operation).
     * @param snapshotId The ID of the token snapshot for this distribution.
     * @param asset The ERC20 asset to be used for the distribution (address(0) for ETH).
     * @param amount The amount of the ERC20 asset to be transferred to this contract as a total amount avaialable for
     * distribution. Cannot be greater than type(uint128).max for gas reasons.
     * @return distributionId The ID of the newly created distribution.
     *
     * @dev This function requires that not only the owner initiates the call, but also that the owner has flagged this
     * contract as the authorized operator. If not, this call will fail. This restricts the call to only be callable
     * through another function on the owner that specifically authorizes this contract for the operation.
     */
    function createDistribution(
        uint256 snapshotId,
        IERC20 asset,
        uint256 amount
    )
        public
        payable
        virtual
        onlyOwner
        requireOwnerAuthorization
        returns (uint256 distributionId)
    {
        distributionId = _createDistribution(snapshotId, asset, amount);
    }

    function _createDistribution(
        uint256 snapshotId,
        IERC20 asset,
        uint256 amount
    )
        internal
        virtual
        returns (uint256 distributionId)
    {
        DistributorStorage storage $ = _getDistributorStorage();

        // Verify the snapshot ID is current
        IERC20Snapshots _token = $._token;
        uint256 currentClock = _token.clock();
        uint256 snapshotClock = _token.getSnapshotClock(snapshotId);
        if (currentClock != snapshotClock) {
            revert InvalidSnapshotId(currentClock, snapshotClock);
        }

        if (amount == 0) {
            revert DistributionAmountTooLow();
        } else if (amount > MAX_DISTRIBUTION_AMOUNT) {
            revert DistributionAmountTooHigh(MAX_DISTRIBUTION_AMOUNT);
        }

        // Ensure this contract receives the funds
        asset.receiveFrom(msg.sender, amount);

        // Increment the distributions count, prepare distribution parameters
        uint256 claimPeriod = $._claimPeriod;
        distributionId = ++$._distributionsCount;
        uint256 closableAt = Math.min(block.timestamp + claimPeriod, type(uint48).max);

        // Setup the new distribution
        Distribution storage _distribution = $._distributions[distributionId];
        _distribution.snapshotId = SafeCast.toUint48(snapshotId); // Assumes snapshot ID will never exceed uint48
        _distribution.totalBalance = uint128(amount);
        _distribution.closableAt = uint48(closableAt);

        emit DistributionCreated(distributionId, asset, amount, snapshotId, closableAt);
    }

    /**
     * Returns whether or not the provided address is approved for closing distributions once the claim period has
     * expired for a distribution.
     * @param account The address to check the status for.
     * @return isApproved A bool indicating whether or not the account is approved.
     */
    function isApprovedForClosingDistributions(address account) public view virtual returns (bool) {
        return _getDistributorStorage()._closeDistributionsApproval[account];
    }

    /**
     * A timelock-only function to approve addresses to close distributions once the claim period has expired. Approve
     * address(0) to allow anyone to close a distribution.
     * @param accounts A list of addresses to approve.
     */
    function approveForClosingDistributions(address[] calldata accounts) external virtual onlyOwner {
        DistributorStorage storage $ = _getDistributorStorage();
        for (uint256 i = 0; i < accounts.length;) {
            _setApprovalForClosingDistributions($, accounts[i], true);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * A timelock-only function to unapprove addresses for closing distributions.
     * @param accounts A list of addresses to unapprove.
     */
    function unapproveForClosingDistributions(address[] calldata accounts) external virtual onlyOwner {
        DistributorStorage storage $ = _getDistributorStorage();
        for (uint256 i = 0; i < accounts.length;) {
            _setApprovalForClosingDistributions($, accounts[i], false);
            unchecked {
                ++i;
            }
        }
    }

    function _setApprovalForClosingDistributions(
        DistributorStorage storage $,
        address account,
        bool isApproved
    )
        internal
        virtual
    {
        $._closeDistributionsApproval[account] = isApproved;
        emit CloseDistributionsApprovalUpdate(account, isApproved);
    }

    /**
     * A function to close a distribution and reclaim the remaining distribution balance to the owner. Only callable by
     * the owner, or approved addresses. If the distribution claims have not yet started, the owner can close it. If the
     * distribution claims have already begun, then the distribution cannot be closed until after the claim period has
     * passed.
     * @param distributionId The identifier of the distribution to be closed.
     */
    function closeDistribution(uint256 distributionId) external virtual {
        DistributorStorage storage $ = _getDistributorStorage();

        // Authorize the caller
        address _owner = owner();
        if (msg.sender != _owner) {
            if (!$._closeDistributionsApproval[address(0)] && !$._closeDistributionsApproval[_msgSender()]) {
                revert Unauthorized();
            }
        }

        _closeDistribution(distributionId, _owner);
    }

    function _closeDistribution(uint256 distributionId, address reclaimReceiver) internal virtual {
        DistributorStorage storage $ = _getDistributorStorage();

        Distribution storage _distribution = $._distributions[distributionId];

        // Revert if distribution does not exist
        (uint256 totalBalance, uint256 claimedBalance) = _checkDistributionExistence(_distribution);

        // Read together to save gas
        IERC20 asset = _distribution.asset;
        bool isClosed = _distribution.isClosed;
        uint256 closableAt = _distribution.closableAt;

        if (isClosed) {
            revert DistributionIsClosed();
        }

        if (block.timestamp < closableAt) {
            revert DistributionClaimsStillActive(closableAt);
        }

        // Close and reclaim remaining assets
        _distribution.isClosed = true;

        uint256 reclaimAmount = totalBalance - claimedBalance;
        asset.transferTo(reclaimReceiver, reclaimAmount);

        emit DistributionClosed(distributionId, asset, reclaimAmount);
    }

    /**
     * Returns whether or not the provided address is approved to claim distributions for the specified token holder.
     * @notice Claimed funds are still sent to the token holder. Approved accounts can simply process the claims.
     * @param holder The token holder.
     * @param account The address to check for approval for claiming distributions to the owner.
     */
    function isApprovedForClaimingDistributions(
        address holder,
        address account
    )
        public
        view
        virtual
        returns (bool isApproved)
    {
        isApproved = _getDistributorStorage()._claimDistributionsApproval[holder][account];
    }

    /**
     * Approves the provided accounts to claim distributions on behalf of the msg.sender.
     * @notice Claimed distribution funds are still sent to the token holder, not the approved account.
     * @param accounts A list of addresses to approve.
     */
    function approveForClaimingDistributions(address[] calldata accounts) external virtual {
        DistributorStorage storage $ = _getDistributorStorage();
        for (uint256 i = 0; i < accounts.length; ++i) {
            _setApprovalForClaimingDistributions($, msg.sender, accounts[i], true);
        }
    }

    /**
     * Approves the provided accounts to claim distributions on behalf of the msg.sender. Approving address(0) allows
     * anyone to claim distributions on behalf of the msg.sender.
     * @notice Claimed distribution funds are still sent to the token holder, not the approved account.
     * @param accounts A list of addresses to approve.
     */
    function unapproveForClaimingDistributions(address[] calldata accounts) external virtual {
        DistributorStorage storage $ = _getDistributorStorage();
        for (uint256 i = 0; i < accounts.length; ++i) {
            _setApprovalForClaimingDistributions($, msg.sender, accounts[i], false);
        }
    }

    function _setApprovalForClaimingDistributions(
        DistributorStorage storage $,
        address holder,
        address account,
        bool isApproved
    )
        internal
    {
        $._claimDistributionsApproval[holder][account] = isApproved;
        emit ClaimDistributionsApprovalUpdate(holder, account, isApproved);
    }

    /**
     * Claims a distribution for the specified token holder, sending the claimed asset amount to the receiver.
     * @notice If the msg.sender is not the holder, this requires that the msg.sender is approved for claiming
     * distributions on behalf of the holder (or that the holder has approved address(0)).
     * @notice The receiver address MUST be equal to the holder address UNLESS the msg.sender is the holder.
     * @param distributionId The distribution ID to claim for.
     * @param holder The address of the token holder.
     * @param receiver The address to send the claimed assets to.
     * @return claimAmount The amount of assets claimed by this token holder.
     */
    function claimDistribution(
        uint256 distributionId,
        address holder,
        address receiver
    )
        public
        virtual
        returns (uint256 claimAmount)
    {
        DistributorStorage storage $ = _getDistributorStorage();

        // Authorize the sender
        address sender = _msgSender();
        if (sender != holder) {
            // Only holder is authorized to send to a different address
            if (holder != receiver) {
                revert Unauthorized();
            }

            // Sender must be authorized to send to the holder
            if (!$._claimDistributionsApproval[holder][address(0)] && !$._claimDistributionsApproval[holder][sender]) {
                revert Unauthorized();
            }
        }

        claimAmount = _claimDistribution($, distributionId, holder, receiver);
    }

    /**
     * Same as above, but uses the msg.sender as the holder and the receiver address.
     */
    function claimDistribution(uint256 distributionId) public virtual returns (uint256 claimAmount) {
        address sender = _msgSender();
        claimAmount = _claimDistribution(_getDistributorStorage(), distributionId, sender, sender);
    }

    /**
     * @dev Claims distribution for holder by signature, sending to receiver. Supports ECDSA or EIP1271 signatures.
     *
     * @param signature The signature is a packed bytes encoding of the ECDSA r, s, and v signature values.
     */
    function claimDistributionBySig(
        uint256 distributionId,
        address holder,
        address receiver,
        uint256 deadline,
        bytes memory signature
    )
        public
        virtual
        returns (uint256 claimAmount)
    {
        if (block.timestamp > deadline) {
            revert ClaimsExpiredSignature();
        }

        bool valid = SignatureChecker.isValidSignatureNow(
            holder,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        CLAIM_DISTRIBUTION_TYPEHASH, distributionId, holder, receiver, _useNonce(holder), deadline
                    )
                )
            ),
            signature
        );

        if (!valid) {
            revert ClaimsInvalidSignature();
        }

        claimAmount = _claimDistribution(_getDistributorStorage(), distributionId, holder, receiver);
    }

    function _claimDistribution(
        DistributorStorage storage $,
        uint256 distributionId,
        address holder,
        address receiver
    )
        internal
        virtual
        returns (uint256 claimAmount)
    {
        // Set the distribution reference
        Distribution storage _distribution;
        assembly ("memory-safe") {
            mstore(0, distributionId)
            mstore(0x20, add($.slot, 0x02))
            _distribution.slot := keccak256(0, 0x40)
        }

        // Single read, reverts if it does not exist
        (uint256 totalBalance, uint256 claimedBalance) = _checkDistributionExistence(_distribution);

        // Single read
        IERC20 asset = _distribution.asset;
        bool isClosed = _distribution.isClosed;

        // Distribution must not be closed
        if (isClosed) {
            revert DistributionIsClosed();
        }

        // Must not have claimed already
        bytes32 hasClaimedSlot;
        {
            bool hasClaimed;
            assembly ("memory-safe") {
                mstore(0, holder)
                mstore(0x20, add(_distribution.slot, 0x03))
                hasClaimedSlot := keccak256(0, 0x40)
                hasClaimed := sload(hasClaimedSlot)
            }

            if (hasClaimed) {
                revert DistributionAlreadyClaimed(holder);
            }
        }

        // Single read
        uint256 snapshotId = _distribution.snapshotId;
        uint256 totalSupply = _distribution.cachedTotalSupply;

        IERC20Snapshots _token = $._token;

        // If the cached total supply is zero, then check that the distribution is active
        if (totalSupply == 0) {
            // Get the total supply at the start time
            totalSupply = _token.getTotalSupplyAtSnapshot(snapshotId);

            // If the total supply is still zero, throw an error
            if (totalSupply == 0) {
                revert TokenTotalSupplyIsZero(address(_token), snapshotId);
            }

            // Cache the result for future claims
            _distribution.cachedTotalSupply = SafeCast.toUint208(totalSupply);
        }

        // Calculate the claim amount
        claimAmount = Math.mulDiv(_token.getBalanceAtSnapshot(holder, snapshotId), totalBalance, totalSupply);

        // Set the distribution as claimed for the holder, update claimed balance, and transfer the assets
        assembly ("memory-safe") {
            sstore(hasClaimedSlot, 0x01)
        }
        if (claimAmount > 0) {
            claimedBalance += claimAmount;
            assembly ("memory-safe") {
                sstore(_distribution.slot, or(totalBalance, shl(128, claimedBalance)))
            }
            asset.transferTo(receiver, claimAmount);
        }

        emit DistributionClaimed(distributionId, holder, asset, claimAmount);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {
        bytes memory data = abi.encodeCall(Treasurer.authorizeDistributorImplementation, (newImplementation));
        owner().functionCall(data);
    }

    /**
     * @dev Distribution considered to exist if totalBalance is greater than zero
     */
    function _checkDistributionExistence(Distribution storage _distribution)
        internal
        view
        returns (uint256 totalBalance, uint256 claimedBalance)
    {
        totalBalance = _distribution.totalBalance;
        claimedBalance = _distribution.claimedBalance;
        if (totalBalance == 0) {
            revert DistributionDoesNotExist();
        }
    }
}
