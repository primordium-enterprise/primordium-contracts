// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v4.8.0) (IGovernor.sol)

pragma solidity ^0.8.20;

import {IGovernorToken} from "src/governor/interfaces/IGovernorToken.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";

/**
 * @dev Interface of the {GovernorBase} core.
 */
interface IGovernorBase is IERC6372 {

    event GovernorBaseInitialized(
        string name,
        string version,
        address timelockAvatar,
        address token,
        uint256 governanceCanBeginAt,
        uint256 governanceThresholdBps,
        bool isFounded
    );

    /**
     * @dev Emitted when the Governor is successfully founded.
     */
    event GovernorFounded(uint256 proposalId);

    /**
     * @dev Emitted when the executor controller used for proposal execution is modified.
     */
    event ExecutorUpdate(address oldExecutor, address newExecutor);

    /**
     * @dev Thrown if the action requires being executed through a governance proposal.
     */
    error OnlyGovernance();

    /**
     * @dev Thrown if the provided address is an invalid address to update the executor to.
     */
    error GovernorInvalidExecutorAddress(address invalidAddress);

    /**
     * @dev Thrown if an attempt to set the executor address in the initializer is made, but the executor is already
     * a non-zero address (meaning it was already initialized).
     */
    error GovernorExecutorAlreadyInitialized();

    /**
     * @dev Thrown if the current block.timestamp is still less than the "governanceCanBeginAt()" timestamp.
     */
    error GovernorCannotBeFoundedYet(uint256 governanceCanBeginAt);

    /**
     * @dev Thrown if the current vote token supply is less than the required threshold for founding the Governor.
     */
    error GovernorFoundingVoteThresholdNotMet(uint256 governanceThreshold, uint256 voteSupply);

    /**
     * @dev Thrown if the Governor is already founded.
     */
    error GovernorAlreadyFounded();

    /**
     * @dev Thrown if the provided proposal ID when submitting a founding proposal is different than the expected
     * proposal ID. The expected proposal ID is the current "proposalCount()" + 1
     */
    error GovernorInvalidFoundingProposalID(uint256 expectedProposalId, uint256 providedProposalId);

    /**
     * @dev Error thrown if a relay call by the exector to this contract reverts.
     */
    error GovernorRelayFailed();

    /**
     * @dev Name of the governor instance (used in building the ERC712 domain separator).
     */
    function name() external view returns (string memory);

    /**
     * @dev Version of the governor instance (used in building the ERC712 domain separator). Default: "1"
     */
    function version() external view returns (string memory);

    /**
     * @notice Returns the address of the executor.
     */
    function executor() external view returns (ITimelockAvatar _executor);

    /**
     * @notice Public endpoint to update the underlying timelock instance. Restricted to the timelock itself, so updates
     * must be proposed, scheduled, and executed through governance proposals.
     *
     * @dev CAUTION: It is not recommended to change the timelock while there are other queued governance proposals.
     */
    function updateExecutor(address newExecutor) external;

    /**
     * @notice Returns the address of the token used for tracking votes.
     */
    function token() external view returns (IGovernorToken);

    /**
     * Returns the timestamp after which the Governor can be founded.
     */
    function governanceCanBeginAt() external view returns (uint256 _governanceCanBeginAt);

    /**
     * Returns the amount of the vote token's initial max supply that needs to be allocated into circulation (via
     * deposits) before the Governor can be founded. Returns zero if governance is already active.
     */
    function governanceFoundingVoteThreshold() external view returns (uint256 threshold);

    /**
     * @notice Initializes governance. This function is the only allowable proposal action on the Governor until it has
     * been successfully executed.
     * @dev The governance threshold of tokens must be allocated before a founding proposal can be submitted.
     * Additionally, the governance threshold of tokens must still be met at the end of the founding proposal's voting
     * period to successfully execute this action, or else it will revert on execution (even if the proposal vote
     * succeeded).
     * @param proposalId This MUST be equal to the proposalId of the founding proposal, or else the `propose()` function
     * will revert. The proposalId can be predicted by taking the current `proposalCount()` and adding one.
     */
    function foundGovernor(uint256 proposalId) external;

    /**
     * @notice Returns true if the Governor has been founded, meaning any proposal actions are available for
     * submission and execution.
     */
    function isFounded() external view returns (bool);

    /**
     * @notice Voting power of an `account` at a specific `timepoint` (which is according to the clock mode - see
     * EIP6372).
     */
    function getVotes(address account, uint256 timepoint) external view returns (uint256);

    /**
     * @notice Voting power of an `account` at a specific `timepoint` given additional encoded parameters.
     */
    function getVotesWithParams(
        address account,
        uint256 timepoint,
        bytes memory params
    )
        external
        view
        returns (uint256);

}
