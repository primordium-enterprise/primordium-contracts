// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "./Treasurer.sol";
import "@openzeppelin/contracts/utils/Checkpoints.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

abstract contract TreasurerDistributions is Treasurer {

    using SafeCast for *;
    using Checkpoints for Checkpoints.Trace224;

    event DistributionCreated(uint256 indexed distributionId, uint256 clockStartTime, uint256 distributionBalance);
    event DistributionClaimPeriodUpdated(uint256 oldClaimPeriod, uint256 newClaimPeriod);
    event DistributionClaimed(uint256 indexed distributionId, address indexed claimedFor, uint256 claimedAmount);
    event DistributionClosed(uint256 indexed distributionId, uint256 reclaimedAmount);

    /**
     * @notice The maximum claim period for new distributions.
     */
    uint256 public immutable MAX_DISTRIBUTION_CLAIM_PERIOD;
    /**
     * @notice The minimum claim period for new distributions.
     */
    uint256 public immutable MIN_DISTRIBUTION_CLAIM_PERIOD;

    // The claim period for distributions, after which the Timelock can close the distribution to reclaim leftover funds.
    Checkpoints.Trace224 private _claimPeriodCheckpoints;

    // Distributions counter
    uint256 public distributionsCount;

    struct Distribution {
        uint32 clockStartTime; // The ERC20Checkpoints clock date that this distribution should begin
        uint224 cachedTotalSupply;
        uint256 balance;
        uint256 claimedBalance;
        mapping(address => bool) hasClaimed;
    }

    // Tracks all distributions
    mapping(uint256 => Distribution) _distributions;

    // Tracks whether or not a distribution has been closed
    mapping(uint256 => bool) _closedDistributions;

    mapping(address => mapping(address => bool)) _approvedAddressesForClaims;
    mapping(address => bool) _approvedAddressesForClosingDistributions;

    constructor(uint256 distributionClaimPeriod_) {
        // Initialize immutables based on clock (assums block.timestamp if not block.number)
        bool usesBlockNumber = clock() == block.number;
        MAX_DISTRIBUTION_CLAIM_PERIOD = usesBlockNumber ?
            1_209_600 : // About 24 weeks at 12sec/block
            24 weeks;
        MIN_DISTRIBUTION_CLAIM_PERIOD = usesBlockNumber ?
            201_600 : // About 4 weeks at 12sec/block
            4 weeks;

        _updateDistributionClaimPeriod(distributionClaimPeriod_);
    }

    /**
     * @notice Creates a new distribution. Only callable by the Timelock itself.
     * @param clockStartTime The start timepoint (according to the token clock) when this distribution will become
     * active. Must be in the future (or will be set to the current execution timepoint if set to zero).
     * @param distributionBalance The balance to be set aside as a distribution, claimable by all token holders according
     * to their token balance at the clockStartTime.
     */
    function createDistribution(
        uint256 clockStartTime,
        uint256 distributionBalance
    ) external virtual onlyTimelock returns (uint256) {
        return _createDistribution(clockStartTime, distributionBalance);
    }

    error ClockStartDateOutOfRange();
    error DistributionBalanceTooLow();
    /**
     * @dev Internal function to create a new distribution.
     */
    function _createDistribution(
        uint256 clockStartTime,
        uint256 distributionBalance
    ) internal virtual returns (uint256) {
        uint currentClock = clock();

        if (clockStartTime == 0) {
            clockStartTime = currentClock;
        } else if (
            clockStartTime < currentClock ||
            clockStartTime > currentClock + MAX_DISTRIBUTION_CLAIM_PERIOD
        ) {
            revert ClockStartDateOutOfRange();
        }

        if (distributionBalance == 0) revert DistributionBalanceTooLow();

        uint currentTreasuryBalance = _treasuryBalance();
        if (distributionBalance > currentTreasuryBalance) revert InsufficientBaseAssetFunds(
            distributionBalance,
            currentTreasuryBalance
        );

        // Increment the distributions count
        uint256 distributionId = ++distributionsCount;

        // Setup the new distribution
        Distribution storage distribution = _distributions[distributionId];
        distribution.clockStartTime = clockStartTime.toUint32();
        distribution.balance = distributionBalance;

        // Transfer to the stash
        _transferBaseAssetToStash(distributionBalance);

        emit DistributionCreated(distributionId, clockStartTime, distributionBalance);

        return distributionId;
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

    error DistributionIsClosed();
    error UnapprovedForClaimingDistribution();
    error AddressAlreadyClaimed();
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
        if (_msgSender() != claimFor) {
            if (
                !_approvedAddressesForClaims[claimFor][_msgSender()] &&
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

    error UnapprovedForClosingDistributions();
    error DistributionClaimPeriodStillActive();
    /**
     * @notice A function to close a distribution and reclaim the remaining unclaimed distribution balance to the DAO
     * treasury. Only callable by approved addresses (or anyone if address(0) is approved). Fails if the claim period for
     * the distribution is still active.
     * @param distributionId The identifier of the distribution to be closed.
     */
    function closeDistribution(uint256 distributionId) external virtual {
        if (msg.sender != address(this)) {
            if (
                !_approvedAddressesForClosingDistributions[address(0)] &&
                !_approvedAddressesForClosingDistributions[_msgSender()]
            ) revert UnapprovedForClosingDistributions();
        }
        uint256 currentClock = clock();
        uint256 clockStartTime = _distributions[distributionId].clockStartTime;

        _checkClockValidity(clockStartTime, currentClock);
        if (currentClock <= clockStartTime + distributionClaimPeriod(clockStartTime)) {
            revert DistributionClaimPeriodStillActive();
        }

        _reclaimRemainingDistributionFunds(distributionId);
    }

    function _reclaimRemainingDistributionFunds(uint256 distributionId) internal virtual {
        Distribution storage distribution = _distributions[distributionId];
        uint256 reclaimAmount = distribution.balance - distribution.claimedBalance;

        _closedDistributions[distributionId] = true;
        _reclaimBaseAssetFromStash(reclaimAmount);

        emit DistributionClosed(distributionId, reclaimAmount);
    }

    error DistributionDoesNotExist();
    error DistributionHasNotStarted();
    function _checkClockValidity(
        uint256 clockStartTime,
        uint256 currentClock
    ) private pure {
        if (clockStartTime == 0) revert DistributionDoesNotExist();
        if (currentClock <= clockStartTime) revert DistributionHasNotStarted();
    }

    /**
     * @notice Returns the current distribution claim period.
     */
    function distributionClaimPeriod() public view virtual returns (uint256) {
        return _claimPeriodCheckpoints.latest();
    }

    /**
     * @notice Returns the distribution claim period at a specific timepoint.
     */
    function distributionClaimPeriod(uint256 timepoint) public view virtual returns (uint256) {
        // Optimistic search, check the latest checkpoint
        (bool exists, uint256 _key, uint256 _value) = _claimPeriodCheckpoints.latestCheckpoint();
        if (exists && _key <= timepoint) {
            return _value;
        }

        // Otherwise, do the binary search
        return _claimPeriodCheckpoints.upperLookupRecent(timepoint.toUint32());
    }

    /**
     * @notice Changes the distribution claim period.
     */
    function updateDistributionClaimPeriod(uint256 newClaimPeriod) external virtual onlyTimelock {
        _updateDistributionClaimPeriod(newClaimPeriod);
    }

    error DistributionClaimPeriodOutOfRange(uint256 min, uint256 max);
    /**
     * @dev Internal function to update the distribution claim period.
     */
    function _updateDistributionClaimPeriod(uint256 newClaimPeriod) internal virtual {
        if (
            newClaimPeriod < MIN_DISTRIBUTION_CLAIM_PERIOD ||
            newClaimPeriod > MAX_DISTRIBUTION_CLAIM_PERIOD
        ) revert DistributionClaimPeriodOutOfRange(MIN_DISTRIBUTION_CLAIM_PERIOD, MAX_DISTRIBUTION_CLAIM_PERIOD);

        uint256 oldClaimPeriod = distributionClaimPeriod();

        _claimPeriodCheckpoints.push(clock().toUint32(), newClaimPeriod.toUint224());

        emit DistributionClaimPeriodUpdated(oldClaimPeriod, newClaimPeriod);
    }

    /**
     * @notice Returns whether or not the provided address is approved to claim the distribution for the specified owner.
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
     * @notice Allows the msg.sender to approve the provided list of addresses for processing distribution claims.
     * Can approve address(0) to allow any address to process a distribution claim.
     * @param approvedAddresses A list of addresses to approve.
     */
    function approveAddressesForDistributionClaims(
        address[] calldata approvedAddresses
    ) public virtual {
        address owner = _msgSender();
        for (uint i = 0; i < approvedAddresses.length;) {
            _approvedAddressesForClaims[owner][approvedAddresses[i]] = true;
            unchecked { ++i; }
        }
    }

    /**
     * @notice Allows the msg.sender to unapprove the provided list of addresses for processing distribution claims.
     * @param unapprovedAddresses A list of addresses to unapprove.
     */
    function unapproveAddressesForDistributionClaims(
        address[] calldata unapprovedAddresses
    ) public virtual {
        address owner = _msgSender();
        for (uint i = 0; i < unapprovedAddresses.length;) {
            _approvedAddressesForClaims[owner][unapprovedAddresses[i]] = false;
            unchecked { i++; }
        }
    }

}