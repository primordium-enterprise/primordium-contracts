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
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC20Checkpoints} from "contracts/shares/interfaces/IERC20Checkpoints.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract Distributor is IDistributor, UUPSUpgradeable, OwnableUpgradeable, ERC165 {
    using SafeERC20 for IERC20;
    using Address for address;
    using ERC165Checker for address;

    struct Distribution {
        // Slot 0 (32 bytes)
        uint128 balance;
        uint128 claimedBalance;

        // Slot 1 (32 bytes)
        uint48 clockStartTime;
        uint208 cachedTotalSupply;

        // Slot 2 (27 bytes)
        address asset;
        bool isDistributionClosed;
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
    }

    bytes32 private immutable DISTRIBUTOR_STORAGE =
        keccak256(abi.encode(uint256(keccak256("Distributor.Storage")) - 1)) & ~bytes32(uint256(0xff));

    function _getDistributorStorage() private view returns (DistributorStorage storage $) {
        bytes32 slot = DISTRIBUTOR_STORAGE;
        assembly {
            $.slot := slot
        }
    }

    uint256 public constant MAX_DISTRIBUTION_AMOUNT = type(uint128).max;

    event DistributionCreated(
        uint256 indexed distributionId,
        address indexed asset,
        uint256 indexed balance,
        uint256 clockStartTime,
        uint256 clockClosableAt
    );
    event DistributionClaimPeriodUpdate(uint256 oldClaimPeriod, uint256 newClaimPeriod);

    error InvalidERC165InterfaceSupport(address _contract);
    error ClockStartTimeCannotBeInThePast();
    error DistributionAmountTooLow();
    error DistributionAmountTooHigh(uint256 maxAmount);
    error InvalidMsgValue();
    error OwnerAuthorizationRequired();

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

        if (
            !token_.supportsInterface(type(IERC20Checkpoints).interfaceId) ||
            !token_.supportsInterface(type(IERC6372).interfaceId)
        ) {
            revert InvalidERC165InterfaceSupport(token_);
        }
        $._token = IERC20Checkpoints(token_);

        _setDistributionClaimPeriod(claimPeriod_);
    }

    /**
     * Returns the current distribution claim period. This is the minimum time period (in the token's clock mode) that a
     * distribution will be claimable by token holders once claims have begun.
     */
    function distributionClaimPeriod() public view returns (uint256 claimPeriod) {
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
    function setDistributionClaimPeriod(uint256 newClaimPeriod) external onlyOwner {
        _setDistributionClaimPeriod(newClaimPeriod);
    }

    function _setDistributionClaimPeriod(uint256 newClaimPeriod) internal {
        DistributorStorage storage $ = _getDistributorStorage();
        emit DistributionClaimPeriodUpdate($._claimPeriod, newClaimPeriod);
        $._claimPeriod = uint48(newClaimPeriod);
    }

    function distributionsCount() public view returns (uint256 _distributionsCount) {
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
    ) public virtual onlyOwner requireOwnerAuthorization returns (uint256 distributionId) {
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



    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {
        bytes memory data = abi.encodeCall(Treasurer.authorizeDistributorImplementation, (newImplementation));
        owner().functionCall(data);
    }

}