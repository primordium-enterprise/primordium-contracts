// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IDistributor} from "../../interfaces/IDistributor.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Treasurer} from "../../base/Treasurer.sol";
import {SelfAuthorized} from "../../base/SelfAuthorized.sol";
import {ERC165Verifier} from "contracts/libraries/ERC165Verifier.sol";
import {IERC20Checkpoints} from "contracts/shares/interfaces/IERC20Checkpoints.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Distributor is IDistributor, UUPSUpgradeable, OwnableUpgradeable, ERC165 {
    using SafeERC20 for IERC20;
    using Address for address;
    using ERC165Verifier for address;

    struct Distribution {
        // Slot 0 (32 bytes)
        uint128 balance;
        uint128 claimedBalance;

        // Slot 1 (32 bytes)
        uint48 clockStartTime;
        uint208 cachedTotalSupply;

        // Slot 2 (27 bytes)
        address asset;
        bool isClosed;
        uint48 clockClosableAt;

        // Slot 3
        mapping(address => bool) hasClaimed;
    }

    /// @custom:storage-location erc7201:Distributor.Storage
    struct DistributorStorage {
        uint48 _claimPeriod;
        uint208 _distributionsCount;

        IERC20Checkpoints _token;

        mapping(uint256 distributionId => Distribution) _distributions;

        mapping(address account => bool isApprovedToClose) _closeDistributionsApproval;

        mapping(address holder => mapping(address account => bool isApprovedToClaim)) _claimDistributionsApproval;

    }

    bytes32 private immutable DISTRIBUTOR_STORAGE =
        keccak256(abi.encode(uint256(keccak256("Distributor.Storage")) - 1)) & ~bytes32(uint256(0xff));

    function _getDistributorStorage() private view returns (DistributorStorage storage $) {
        bytes32 slot = DISTRIBUTOR_STORAGE;
        assembly {
            $.slot := slot
        }
    }

    uint256 private constant MASK_UINT128 = 0xffffffffffffffffffffffffffffffff;

    uint256 public constant MAX_DISTRIBUTION_AMOUNT = type(uint128).max;

    event DistributionCreated(
        uint256 indexed distributionId,
        address indexed asset,
        uint256 indexed balance,
        uint256 clockStartTime,
        uint256 clockClosableAt
    );
    event DistributionClaimPeriodUpdate(uint256 oldClaimPeriod, uint256 newClaimPeriod);
    event CloseDistributionsApprovalUpdate(address indexed account, bool indexed isApproved);
    event DistributionClosed(uint256 indexed distributionId, address asset, uint256 reclaimAmount);
    event ClaimDistributionsApprovalUpdate(address indexed holder, address indexed account, bool indexed isApproved);
    event DistributionClaimed(
        uint256 indexed distributionId,
        address indexed holder,
        address asset,
        uint256 amount
    );

    error Unauthorized();
    error InvalidERC165InterfaceSupport(address _contract);
    error ClockStartTimeCannotBeInThePast();
    error DistributionAmountTooLow();
    error DistributionAmountTooHigh(uint256 maxAmount);
    error InvalidMsgValue();
    error ETHTransferFailed();
    error OwnerAuthorizationRequired();
    error DistributionDoesNotExist();
    error DistributionIsClosed();
    error DistributionClaimsNotYetActive(uint256 clockStartTime);
    error DistributionClaimsStillActive(uint256 closableAt);
    error DistributionAlreadyClaimed(address holder);
    error TokenTotalSupplyIsZero(address token, uint256 clockStartTime);

    modifier requireOwnerAuthorization() {
        if (SelfAuthorized(owner()).getAuthorizedOperator() != address(this)) {
            revert OwnerAuthorizationRequired();
        }
        _;
    }

    /**
     * By default, initializes to the msg.sender being the owner.
     */
    function initialize(
        address token_,
        uint256 claimPeriod_
    ) external initializer {
        DistributorStorage storage $ = _getDistributorStorage();

        __Ownable_init(msg.sender);

        token_.checkInterfaces([
            type(IERC20Checkpoints).interfaceId,
            type(IERC6372).interfaceId
        ]);
        $._token = IERC20Checkpoints(token_);

        _setDistributionClaimPeriod(claimPeriod_);
    }

    /**
     * Returns the current distribution claim period. This is the minimum time period (in the token's clock unit) that a
     * distribution will be claimable by token holders once the claims have begun.
     */
    function distributionClaimPeriod() public view virtual returns (uint256 claimPeriod) {
        claimPeriod = _getDistributorStorage()._claimPeriod;
    }

    /**
     * Updates the distribution claim period.
     * @notice Only callable by the owning contract.
     * @param newClaimPeriod The new claim period, which must be denoted in the units of the token's clock mode. For
     * example, if the token's clock mode uses block numbers, then this period should be set to the number of blocks
     * after claims begin for a distribution to ensure claims continue before the distribution can be closed. If using
     * timestamps, then this is the number of seconds before which claims should be closable.
     */
    function setDistributionClaimPeriod(uint256 newClaimPeriod) external virtual onlyOwner {
        _setDistributionClaimPeriod(newClaimPeriod);
    }

    function _setDistributionClaimPeriod(uint256 newClaimPeriod) internal virtual {
        DistributorStorage storage $ = _getDistributorStorage();
        emit DistributionClaimPeriodUpdate($._claimPeriod, newClaimPeriod);
        $._claimPeriod = uint48(newClaimPeriod);
    }

    /**
     * Returns the total count of distributions so far.
     */
    function distributionsCount() public view virtual returns (uint256 _distributionsCount) {
        _distributionsCount = _getDistributorStorage()._distributionsCount;
    }

    /**
     * Creates a new distribution for share holders.
     * @notice Only callable by the owner (see dev note about authorized operation).
     * @param clockStartTime The timepoint (according to the share token clock) when claims will begin for this
     * distribution. If a value of zero is passed, then this will be set to the current clock value at execution.
     * Otherwise, the clockStartTime CANNOT be in the past.
     * @param asset The ERC20 asset to be used for the distribution (address(0) for ETH).
     * @param amount The amount of the ERC20 asset to be transferred to this contract as a total amount avaialable for
     * distribution.
     * @return distributionId The ID of the newly created distribution.
     *
     * @dev This function requires that not only the owner initiates the call, but also that the owner has flagged this
     * contract as the authorized operator. If not, this call will fail. This restricts the call to only be callable
     * through another function on the owner that specifically authorizes this contract for the operation.
     */
    function createDistribution(
        uint256 clockStartTime,
        address asset,
        uint256 amount
    ) public payable virtual onlyOwner requireOwnerAuthorization returns (uint256 distributionId) {
        distributionId = _createDistribution(clockStartTime, asset, amount);
    }

    function _createDistribution(
        uint256 clockStartTime,
        address asset,
        uint256 amount
    ) internal virtual returns (uint256 distributionId) {
        DistributorStorage storage $ = _getDistributorStorage();

        uint256 currentClock = $._token.clock();

        // Set zero to current timestamp, otherwise check range
        if (clockStartTime == 0) {
            clockStartTime = currentClock;
        } else if (
            clockStartTime < currentClock
        ) {
            revert ClockStartTimeCannotBeInThePast();
        }

        if (amount == 0) {
            revert DistributionAmountTooLow();
        } else if (amount > MAX_DISTRIBUTION_AMOUNT) {
            revert DistributionAmountTooHigh(MAX_DISTRIBUTION_AMOUNT);
        }

        // Transfer the funds to this contract
        if (asset == address(0)) {
            if (msg.value != amount) {
                revert InvalidMsgValue();
            }
        } else {
            if (msg.value > 0) {
                revert InvalidMsgValue();
            }
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }


        // Increment the distributions count, prepare distribution parameters
        uint256 claimPeriod = $._claimPeriod;
        distributionId = ++$._distributionsCount;
        uint256 clockClosableAt = clockStartTime + claimPeriod;

        // Setup the new distribution
        Distribution storage _distribution = $._distributions[distributionId];
        _distribution.clockStartTime = uint48(clockStartTime);
        _distribution.balance = uint128(amount);
        _distribution.clockClosableAt = SafeCast.toUint48(clockClosableAt);

        emit DistributionCreated(distributionId, asset, amount, clockStartTime, clockClosableAt);
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
    function approveForClosingDistributions(
        address[] calldata accounts
    ) external virtual onlyOwner {
        DistributorStorage storage $ = _getDistributorStorage();
        for (uint256 i = 0; i < accounts.length;) {
            _setApprovalForClosingDistributions($, accounts[i], true);
            unchecked { ++i; }
        }
    }

    /**
     * A timelock-only function to unapprove addresses for closing distributions.
     * @param accounts A list of addresses to unapprove.
     */
    function unapproveForClosingDistributions(
        address[] calldata accounts
    ) external virtual onlyOwner {
        DistributorStorage storage $ = _getDistributorStorage();
        for (uint256 i = 0; i < accounts.length;) {
            _setApprovalForClosingDistributions($, accounts[i], false);
            unchecked { ++i; }
        }
    }

    function _setApprovalForClosingDistributions(
        DistributorStorage storage $,
        address account,
        bool isApproved
    ) internal virtual {
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
            if (
                !$._closeDistributionsApproval[address(0)] &&
                !$._closeDistributionsApproval[_msgSender()]
            ) {
                revert Unauthorized();
            }
        }

        Distribution storage _distribution = $._distributions[distributionId];

        // Read together to save gas
        address asset = _distribution.asset;
        bool isClosed = _distribution.isClosed;
        uint256 closableAt = _distribution.clockClosableAt;

        if (isClosed) {
            revert DistributionIsClosed();
        }

        // Check clock time
        uint256 currentClock = $._token.clock();
        uint256 startTime = _distribution.clockStartTime;

        if (startTime == 0) {
            revert DistributionDoesNotExist();
        } else if (currentClock < startTime && msg.sender != _owner) {
            revert Unauthorized();
        } else if (currentClock < closableAt) {
            revert DistributionClaimsStillActive(closableAt);
        }

        // Close and reclaim remaining assets
        _distribution.isClosed = true;

        uint256 reclaimAmount = _distribution.balance - _distribution.claimedBalance;
        _safeTransfer(asset, _owner, reclaimAmount);

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
    ) public view virtual returns (bool isApproved) {
        isApproved = _getDistributorStorage()._claimDistributionsApproval[holder][account];
    }

    /**
     * Approves the provided accounts to claim distributions on behalf of the msg.sender.
     * @notice Claimed distribution funds are still sent to the token holder, not the approved account.
     * @param accounts A list of addresses to approve.
     */
    function approveForClaimingDistributions(
        address[] calldata accounts
    ) external virtual {
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
    function unapproveForClaimingDistributions(
        address[] calldata accounts
    ) external virtual {
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
    ) internal {
        $._claimDistributionsApproval[holder][account] = isApproved;
        emit ClaimDistributionsApprovalUpdate(holder, account, isApproved);
    }

    function claimDistribution(
        uint256 distributionId
    ) public returns (uint256 claimAmount) {
        claimAmount = claimDistribution(distributionId, msg.sender);
    }

    function claimDistribution(
        uint256 distributionId,
        address holder
    ) public returns (uint256 claimAmount) {
        DistributorStorage storage $ = _getDistributorStorage();

        // Authorize the sender
        address sender = _msgSender();
        if (sender != holder) {
            if (
                !$._claimDistributionsApproval[holder][address(0)] &&
                !$._claimDistributionsApproval[holder][sender]
            ) {
                revert Unauthorized();
            }
        }

        claimAmount = _claimDistribution($, distributionId, holder, holder);
    }

    function _claimDistribution(
        DistributorStorage storage $,
        uint256 distributionId,
        address holder,
        address receiver
    ) internal virtual returns (uint256 claimAmount) {
        Distribution storage _distribution = $._distributions[distributionId];

        // Read slot once
        address asset = _distribution.asset;
        bool isClosed = _distribution.isClosed;

        // Distribution must not be closed
        if (isClosed) {
            revert DistributionIsClosed();
        }

        // Must not have claimed already
        if (_distribution.hasClaimed[holder]) {
            revert DistributionAlreadyClaimed(holder);
        }

        uint256 clockStartTime = _distribution.clockStartTime;
        uint256 totalSupply = _distribution.cachedTotalSupply;

        // If the cached total supply is zero, then check that the distribution is active
        IERC20Checkpoints _token = $._token;
        if (totalSupply == 0) {
            // Check if the distribution exists
            if (clockStartTime == 0) {
                revert DistributionDoesNotExist();
            } else {
                uint256 currentClock = _token.clock();
                if (currentClock < clockStartTime) {
                    revert DistributionClaimsNotYetActive(clockStartTime);
                }
            }

            // Get the total supply at the start time
            totalSupply = _token.getPastTotalSupply(clockStartTime);

            // If the total supply is still zero, throw an error
            if (totalSupply == 0) {
                revert TokenTotalSupplyIsZero(address(_token), clockStartTime);
            }

            // Cache the result for future claims
            _distribution.cachedTotalSupply = SafeCast.toUint208(totalSupply);
        }

        // Read balances together
        uint256 totalBalance = _distribution.balance;
        uint256 claimedBalance = _distribution.claimedBalance;

        // Calculate the claim amount
        claimAmount = Math.mulDiv(
            _token.getPastBalanceOf(holder, clockStartTime),
            totalBalance,
            totalSupply
        );

        // Set the distribution as claimed for the holder, update claimed balance, and transfer the assets
        _distribution.hasClaimed[holder] = true;
        claimedBalance += claimAmount;
        if (claimAmount > 0) {
            assembly ("memory-safe") {
                sstore(_distribution.slot, or(totalBalance, shl(128, claimedBalance)))
            }
            _safeTransfer(asset, receiver, claimAmount);
        }

        emit DistributionClaimed(distributionId, holder, asset, claimAmount);
    }

    function _safeTransfer(address asset, address to, uint256 amount) internal {
        if (asset == address(0)) {
            (bool success,) = to.call{value: amount}("");
            if (!success) {
                revert ETHTransferFailed();
            }
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {
        bytes memory data = abi.encodeCall(Treasurer.authorizeDistributorImplementation, (newImplementation));
        owner().functionCall(data);
    }

}