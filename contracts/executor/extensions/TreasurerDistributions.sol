// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import "../base/Treasurer.sol";
import "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

abstract contract TreasurerDistributions is Treasurer {

    using SafeCast for *;
    using Checkpoints for Checkpoints.Trace224;

    struct Distribution {
        // The ERC20CheckpointsUpgradeable clock date that this distribution should begin
        uint32 clockStartTime;
        uint224 cachedTotalSupply;
        uint256 balance;
        uint256 claimedBalance;
        mapping(address => bool) hasClaimed;
    }

    /**
     * @notice The maximum claim period for new distributions.
     */
    uint256 public immutable MAX_DISTRIBUTION_CLAIM_PERIOD;
    /**
     * @notice The minimum claim period for new distributions.
     */
    uint256 public immutable MIN_DISTRIBUTION_CLAIM_PERIOD;

    // Distributions counter
    uint256 public distributionsCount;

    // The distribution claim period, after which the Timelock can close the distribution to reclaim leftover funds.
    Checkpoints.Trace224 private _claimPeriodCheckpoints;

    // Tracks all distributions
    mapping(uint256 => Distribution) private _distributions;

    // Tracks whether or not a distribution has been closed
    mapping(uint256 => bool) private _closedDistributions;

    mapping(address => mapping(address => bool)) private _approvedAddressesForClaims;

    event DistributionCreated(uint256 indexed distributionId, uint256 clockStartTime, uint256 distributionBalance);
    event DistributionClaimPeriodUpdated(uint256 oldClaimPeriod, uint256 newClaimPeriod);
    event DistributionClaimed(uint256 indexed distributionId, address indexed claimedFor, uint256 claimedAmount);
    event DistributionClosed(uint256 indexed distributionId, uint256 reclaimedAmount);

    error ClockStartDateOutOfRange();
    error DistributionBalanceTooLow();
    error DistributionIsClosed();
    error UnapprovedForClaimingDistribution();
    error AddressAlreadyClaimed();
    error UnapprovedForClosingDistributions();
    error DistributionClaimPeriodStillActive();
    error DistributionDoesNotExist();
    error DistributionHasNotStarted();
    error DistributionClaimPeriodOutOfRange(uint256 min, uint256 max);

    /**
     * @notice A public view function to see data about the specified distribution.
     * @param distributionId The identifier for the distribution to view.
     * @return isDistribitionClosed True if the distribution has been closed.
     * @return clockStartTime The start time (according to the token clock mode), after which this distribution will be
     * claimable.
     * @return distributionBalance The total balance available to token holders for this distribution.
     * @return claimedBalance The total balance that has been claimed by token holders for this distribution.
     */
    function getDistribution(uint256 distributionId) public view virtual returns(
        bool,
        uint256,
        uint256,
        uint256
    ) {
        Distribution storage distribution = _distributions[distributionId];
        uint256 clockStartTime = distribution.clockStartTime;
        if (clockStartTime == 0) revert DistributionDoesNotExist();
        return (
            _closedDistributions[distributionId],
            clockStartTime,
            distribution.balance,
            distribution.claimedBalance
        );
    }

    /**
     * @notice Returns whether or not the provided address is approved to claim the distribution for the specified
     * owner.
     * @param owner The token holder.
     * @param account The address to check for approval for claiming distributions to the owner.
     */
    function isAddressApprovedForDistributionClaims(
        address owner,
        address account
    ) public view virtual returns (bool) {
        return _approvedAddressesForClaims[owner][account];
    }

    /**
     * @notice Changes the distribution claim period.
     */
    function updateDistributionClaimPeriod(uint256 newClaimPeriod) external virtual onlySelf {
        _updateDistributionClaimPeriod(newClaimPeriod);
    }





    /**
     * @notice Public function for claiming a distribution for the msg.sender
     * @param distributionId The distribution identifier to claim.
     * @return claimAmount Returns the amount of base asset transferred to the claim recipient.
     */
    function claimDistribution(
        uint256 distributionId
    ) public virtual returns (uint256) {
        return _claimDistribution(distributionId, _msgSender());
    }

    /**
     * @notice Public function for claiming a distribution on behalf of another account (but the msg.sender must be
     * approved for claims).
     * @param distributionId The distribution identifier to claim.
     * @param claimFor The address of the token holder to claim the distribution for.
     * @return claimAmount Returns the amount of base asset transferred to the claim recipient.
     */
    function claimDistribution(
        uint256 distributionId,
        address claimFor
    ) public virtual returns (uint256) {
        return _claimDistribution(distributionId, claimFor);
    }



    /**
     * @dev Internal function for claiming a distribution as a token holder
     */
    function _claimDistribution(
        uint256 distributionId,
        address claimFor
    ) internal virtual returns (uint256) {
        // Distribution must not be closed
        if (_closedDistributions[distributionId]) revert DistributionIsClosed();

        // msg.sender must be claimFor, or must be approved
        address msgSender = _msgSender();
        if (msgSender != claimFor) {
            if (
                !_approvedAddressesForClaims[claimFor][msgSender] &&
                !_approvedAddressesForClaims[claimFor][address(0)]
            ) revert UnapprovedForClaimingDistribution();
        }

        Distribution storage distribution = _distributions[distributionId];

        // Must not have claimed already
        if (distribution.hasClaimed[claimFor]) revert AddressAlreadyClaimed();

        uint256 clockStartTime = distribution.clockStartTime;
        uint256 totalSupply = distribution.cachedTotalSupply;

        // If the cached total supply is zero, then this distribution needs to be initialized (meaning cached)
        if (totalSupply == 0) {
            _checkClockValidity(clockStartTime, clock());
            totalSupply = _token.getPastTotalSupply(clockStartTime);
            // If the total supply is still zero, then simply reclaim the distribution
            if (totalSupply == 0) {
                _reclaimRemainingDistributionFunds(distributionId);
                return 0;
            }
            // Cache the result for future claims
            distribution.cachedTotalSupply = totalSupply.toUint224();
        }

        uint256 claimAmount = Math.mulDiv(
            _token.getPastBalanceOf(claimFor, clockStartTime),
            distribution.balance,
            totalSupply
        );

        distribution.hasClaimed[claimFor] = true;
        distribution.claimedBalance += claimAmount;
        _transferStashedBaseAsset(claimFor, claimAmount);

        emit DistributionClaimed(distributionId, claimFor, claimAmount);

        return claimAmount;
    }


    function _checkClockValidity(
        uint256 clockStartTime,
        uint256 currentClock
    ) private pure {
        if (clockStartTime == 0) revert DistributionDoesNotExist();
        if (currentClock <= clockStartTime) revert DistributionHasNotStarted();
    }

}