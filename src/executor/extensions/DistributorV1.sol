// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IDistributor} from "./interfaces/IDistributor.sol";
import {IDistributionCreator} from "../interfaces/IDistributionCreator.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Ownable1Or2StepUpgradeable} from "src/utils/Ownable1Or2StepUpgradeable.sol";
import {AuthorizedInitializer} from "src/utils/AuthorizedInitializer.sol";
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
    AuthorizedInitializer,
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
    function setUp(bytes memory initParams) external virtual override initializer {
        DistributorStorage storage $ = _getDistributorStorage();

        __Ownable_init_unchained(msg.sender);
        __EIP712_init("DistributorV1", "1");

        (address token_, uint256 claimPeriod_) = abi.decode(initParams, (address, uint256));
        token_.checkInterfaces([type(IERC20Snapshots).interfaceId, type(IERC6372).interfaceId]);
        $._token = IERC20Snapshots(token_);

        _setDistributionClaimPeriod(claimPeriod_);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        // forgefmt: disable-next-item
        return
            interfaceId == type(IDistributionCreator).interfaceId ||
            interfaceId == type(IDistributor).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IDistributor
    function token() public view virtual override returns (address _token) {
        _token = address(_getDistributorStorage()._token);
    }

    /// @inheritdoc IDistributor
    function distributionClaimPeriod() public view virtual returns (uint256 claimPeriod) {
        claimPeriod = _getDistributorStorage()._claimPeriod;
    }

    /// @inheritdoc IDistributor
    function setDistributionClaimPeriod(uint256 newClaimPeriod) external virtual onlyOwner {
        _setDistributionClaimPeriod(newClaimPeriod);
    }

    function _setDistributionClaimPeriod(uint256 newClaimPeriod) internal virtual {
        DistributorStorage storage $ = _getDistributorStorage();
        emit DistributionClaimPeriodUpdate($._claimPeriod, newClaimPeriod);
        $._claimPeriod = SafeCast.toUint48(newClaimPeriod);
    }

    /// @inheritdoc IDistributor
    function distributionsCount() public view virtual returns (uint256 _distributionsCount) {
        _distributionsCount = _getDistributorStorage()._distributionsCount;
    }

    /// @inheritdoc IDistributor
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

    /// @inheritdoc IDistributor
    function isDistributionClosed(uint256 distributionId) public view virtual returns (bool isClosed) {
        Distribution storage _distribution = _getDistributorStorage()._distributions[distributionId];
        _checkDistributionExistence(_distribution);

        isClosed = _distribution.isClosed;
    }

    /// @inheritdoc IDistributor
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

    /// @inheritdoc IDistributor
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
     * @inheritdoc IDistributionCreator
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
        override
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

    /// @inheritdoc IDistributor
    function isApprovedForClosingDistributions(address account) public view virtual returns (bool) {
        return _getDistributorStorage()._closeDistributionsApproval[account];
    }

    /// @inheritdoc IDistributor
    function approveForClosingDistributions(address[] calldata accounts) external virtual onlyOwner {
        DistributorStorage storage $ = _getDistributorStorage();
        for (uint256 i = 0; i < accounts.length;) {
            _setApprovalForClosingDistributions($, accounts[i], true);
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IDistributor
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

    /// @inheritdoc IDistributor
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

    /// @inheritdoc IDistributor
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

    /// @inheritdoc IDistributor
    function approveForClaimingDistributions(address[] calldata accounts) external virtual {
        DistributorStorage storage $ = _getDistributorStorage();
        for (uint256 i = 0; i < accounts.length; ++i) {
            _setApprovalForClaimingDistributions($, msg.sender, accounts[i], true);
        }
    }

    /// @inheritdoc IDistributor
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

    /// @inheritdoc IDistributor
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

    /// @inheritdoc IDistributor
    function claimDistribution(uint256 distributionId) public virtual returns (uint256 claimAmount) {
        address sender = _msgSender();
        claimAmount = _claimDistribution(_getDistributorStorage(), distributionId, sender, sender);
    }

    /// @inheritdoc IDistributor
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
