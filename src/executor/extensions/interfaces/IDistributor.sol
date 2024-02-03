// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IDistributionCreator} from "../../interfaces/IDistributionCreator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDistributor is IDistributionCreator {
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

    /**
     * Returns the address of the token used for calculating each holder's distribution share.
     */
    function token() external view returns (address);

    /**
     * Returns the current distribution claim period. This is the minimum time period, in seconds, that a distribution
     * will be claimable by token holders.
     */
    function distributionClaimPeriod() external view returns (uint256 claimPeriod);

    /**
     * Updates the distribution claim period.
     * @notice Only callable by the owning contract.
     * @param newClaimPeriod The new minimum claim period, in seconds (no greater than type(uint48).max)
     */
    function setDistributionClaimPeriod(uint256 newClaimPeriod) external;

    /**
     * Returns the total count of distributions so far.
     */
    function distributionsCount() external view returns (uint256 _distributionsCount);

    /**
     * Check the closable status for a distribution. Returns false for distributions that are already closed.
     */
    function isDistributionClosable(uint256 distributionId) external view returns (bool);

    /**
     * Returns true if the distribution has been closed.
     */
    function isDistributionClosed(uint256 distributionId) external view returns (bool);

    /**
     * Returns true if the specified account holder has claimed the distriution ID.
     */
    function accountHasClaimedDistribution(uint256 distributionId, address holder) external view returns (bool);

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
        external
        view
        returns (
            uint256 totalBalance,
            uint256 claimedBalance,
            IERC20 asset,
            uint256 snapshotId,
            uint256 closableAt,
            bool isClosed
        );

    /**
     * Returns whether or not the provided address is approved for closing distributions once the claim period has
     * expired for a distribution.
     * @param account The address to check the status for.
     * @return isApproved A bool indicating whether or not the account is approved.
     */
    function isApprovedForClosingDistributions(address account) external view returns (bool);

    /**
     * An owner-only function to approve addresses to close distributions once the claim period has expired. Approve
     * address(0) to allow anyone to close a distribution.
     * @param accounts A list of addresses to approve.
     */
    function approveForClosingDistributions(address[] calldata accounts) external;

    /**
     * An owner-only function to unapprove addresses for closing distributions.
     * @param accounts A list of addresses to unapprove.
     */
    function unapproveForClosingDistributions(address[] calldata accounts) external;

    /**
     * A function to close a distribution and reclaim the remaining distribution balance to the owner. Only callable by
     * the owner, or approved addresses. If the distribution claims have not yet started, the owner can close it. If the
     * distribution claims have already begun, then the distribution cannot be closed until after the claim period has
     * passed.
     * @param distributionId The identifier of the distribution to be closed.
     */
    function closeDistribution(uint256 distributionId) external;

    /**
     * Returns whether or not the provided address is approved to claim distributions for the specified token holder.
     * @notice Claimed funds are still sent to the token holder. Approved accounts can simply process the claims.
     * @param holder The token holder.
     * @param account The address to check for approval for claiming distributions to the owner.
     */
    function isApprovedForClaimingDistributions(address holder, address account) external view returns (bool);

    /**
     * Approves the provided accounts to claim distributions on behalf of the msg.sender.
     * @notice Claimed distribution funds are still sent to the token holder, not the approved account.
     * @param accounts A list of addresses to approve.
     */
    function approveForClaimingDistributions(address[] calldata accounts) external;

    /**
     * Approves the provided accounts to claim distributions on behalf of the msg.sender. Approving address(0) allows
     * anyone to claim distributions on behalf of the msg.sender.
     * @notice Claimed distribution funds are still sent to the token holder, not the approved account.
     * @param accounts A list of addresses to approve.
     */
    function unapproveForClaimingDistributions(address[] calldata accounts) external;

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
        external
        returns (uint256 claimAmount);

    /**
     * Same as above, but uses the msg.sender as the holder and the receiver address.
     */
    function claimDistribution(uint256 distributionId) external returns (uint256 claimAmount);

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
        external
        returns (uint256 claimAmount);
}
