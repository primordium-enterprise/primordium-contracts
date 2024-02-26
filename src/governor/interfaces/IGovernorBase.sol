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
    struct GovernorBaseInit {
        address executor;
        address token;
        uint256 governanceCanBeginAt;
        uint256 governanceThresholdBps;
        uint256 proposalThresholdBps;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 gracePeriod;
        bytes grantRoles;
    }

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    struct ProposalCore {
        address proposer; // 20 bytes
        uint48 voteStart; // 6 bytes
        uint32 voteDuration; // 4 bytes
        bool queued; // 1 byte
        bool canceled; // 1 byte
    }

    /*/////////////////////////////////////////////////////////////////////////
        EVENTS
    /////////////////////////////////////////////////////////////////////////*/

    event GovernorBaseInitialized(
        address executor, address token, uint256 governanceCanBeginAt, uint256 governanceThresholdBps, bool isFounded
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
     * @dev Emitted when the proposal threshold BPS is updated.
     */
    event ProposalThresholdBPSUpdate(uint256 oldProposalThresholdBps, uint256 newProposalThresholdBps);

    /**
     * @dev Emitted when the voting delay is updated.
     */
    event VotingDelayUpdate(uint256 oldVotingDelay, uint256 newVotingDelay);

    /**
     * @dev Emitted when the voting period is updated.
     */
    event VotingPeriodUpdate(uint256 oldVotingPeriod, uint256 newVotingPeriod);

    /**
     * @dev Emitted when the proposal grace period is updated.
     */
    event ProposalGracePeriodUpdate(uint256 oldGracePeriod, uint256 newGracePeriod);

    /**
     * @dev Emitted when a proposal is created.
     */
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        string[] signatures,
        uint256 voteStart,
        uint256 voteEnd,
        string description
    );

    /**
     * @dev Emitted when a proposal is queued.
     */
    event ProposalQueued(uint256 indexed proposalId, uint256 eta);

    /**
     * @dev Emitted when a proposal is canceled.
     */
    event ProposalCanceled(uint256 indexed proposalId, address indexed canceler);

    /**
     * @dev Emitted when a proposal is executed.
     */
    event ProposalExecuted(uint256 indexed proposalId);

    /*/////////////////////////////////////////////////////////////////////////
        ERRORS
    /////////////////////////////////////////////////////////////////////////*/

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
     * @dev The current state of a proposal is not the required for performing an operation.
     * The `expectedStates` is a bitmap with the bits enabled for each ProposalState enum position counting from right
     * to left.
     *
     * NOTE: If `expectedState` is `bytes32(0)`, the proposal is expected to not be in any state (i.e. not exist).
     * This is the case when a proposal that is expected to be unset is already initiated (the proposal is duplicated).
     */
    error GovernorUnexpectedProposalState(uint256 proposalId, ProposalState current, bytes32 expectedStates);

    /**
     * @dev If governance has not been initialized, the only allowable proposal action is to initialize governance.
     */
    error GovernorFoundingActionRequired();

    /**
     * @dev Thrown when the provided `proposalId` does not match any known proposals.
     */
    error GovernorUnknownProposalId(uint256 proposalId);

    /**
     * @dev Thrown when the proposal description ends with `#proposer=0x???`, where `0x???` is a valid address, and the
     * msg.sender's address does not match this provided address.
     */
    error GovernorRestrictedProposer();

    /**
     * @dev Thrown when the msg.sender is unauthorized to complete the current action.
     */
    error GovernorUnauthorizedSender(address msgSender);

    /**
     * @dev Thrown when the actions hash of the targets, values, and calldatas do not match the proposal's actions hash.
     */
    error GovernorInvalidProposalActions(uint256 proposalId);

    /**
     * @dev Thrown when a calldata signature does not match the actual calldata selector. Provides the index where the
     * mismatch occurs.
     */
    error GovernorInvalidActionSignature(uint256 index);

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
    function setExecutor(address newExecutor) external;

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

    /**
     * @dev The bytes32 role hash for accounts that are allowed to submit proposals, regardless of the proposal
     * threshold.
     */
    function PROPOSER_ROLE() external view returns (bytes32);

    /**
     * @dev The bytes32 role hash for accounts that are allowed to cancel proposals. If granting this ability to an
     * account, it is recommended to set a reasonable "expiresAt" paramater, as any account with this role can cancel
     * any proposal before execution.
     */
    function CANCELER_ROLE() external view returns (bytes32);

    /**
     * @notice Returns the total number of submitted proposals.
     */
    function proposalCount() external view returns (uint256 _proposalCount);

    /**
     * @notice Timepoint used to retrieve user's votes and quorum. If using block number (as per Compound's Comp), the
     * snapshot is performed at the end of this block. Hence, voting for this proposal starts at the beginning of the
     * following block.
     */
    function proposalSnapshot(uint256 proposalId) external view returns (uint256);

    /**
     * @notice Timepoint at which votes close. If using block number, votes close at the end of this block, so it is
     * possible to cast a vote during this block.
     */
    function proposalDeadline(uint256 proposalId) external view returns (uint256);

    /**
     * @notice Address of the proposer.
     */
    function proposalProposer(uint256 proposalId) external view returns (address);

    /**
     * @notice Returns the hash of the proposal actions.
     */
    function proposalActionsHash(uint256 proposalId) external view returns (bytes32);

    /**
     * @notice Public accessor to check the eta of a proposal. Returns zero for an unqueued operation. Otherwise returns
     * the result of {TimelockAvatar.getOperationExecutableAt}.
     */
    function proposalEta(uint256 proposalId) external view returns (uint256);

    /**
     * @notice Public accessor to check the operation nonce of a proposal queued on the Executor. Returns 0 for a
     * proposal that has not been queued. Also returns zero for a proposalId that does not exist.
     * @dev If the proposal is the first operation on the executor, it is possible that the operation nonce is 0 and
     * does in fact exist. The {proposalEta} can be additionally checked to determine if the operation exists.
     */
    function proposalOpNonce(uint256 proposalId) external view returns (uint256);

    /**
     * Current state of a proposal, following Compound's convention.
     */
    function state(uint256 proposalId) external view returns (ProposalState);

    /**
     * @dev The actionsHash is produced by hashing the ABI encoded `targets` array, the `values` array, and the
     * `calldatas` array. This can be reproduced from the proposal data which is part of the {ProposalCreated} event.
     */
    function hashProposalActions(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        external
        pure
        returns (bytes32);

    /**
     * @notice The current number of votes that need to be delegated to the msg.sender in order to create a new
     * proposal (calculated using the {proposalThresholdBps}).
     */
    function proposalThreshold() external view returns (uint256);

    /**
     * @notice The percentage of the vote token's total supply (in basis points) that must be delegated to the
     * msg.sender in order to create a new proposal.
     */
    function proposalThresholdBps() external view returns (uint256);

    /**
     * @notice A governance-only function to update the proposal threshold basis points. Max value is 10,000.
     */
    function setProposalThresholdBps(uint256 newProposalThresholdBps) external;

    /**
     * @notice Delay, between the proposal is created and the vote starts. The unit this duration is expressed in
     * depends on the clock (see EIP-6372) this contract uses.
     *
     * This can be increased to leave time for users to buy voting power, or delegate it, before the voting of a
     * proposal starts.
     */
    function votingDelay() external view returns (uint256);

    /**
     * @notice A governance-only function to update the voting delay.
     */
    function setVotingDelay(uint256 newVotingDelay) external;

    /**
     * @notice Delay, between the vote start and vote ends. The unit this duration is expressed in depends on the clock
     * (see EIP-6372) this contract uses.
     *
     * NOTE: The {votingDelay} can delay the start of the vote. This must be considered when setting the voting period
     * compared to the voting delay.
     */
    function votingPeriod() external view returns (uint256);

    /**
     * @notice A governance-only function to update the voting period.
     */
    function setVotingPeriod(uint256 newVotingPeriod) external;

    /**
     * @notice Grace period after a proposal deadline passes in which a successful proposal must be queued for
     * execution, or else the proposal will expire. The unit this duration is expressed in depends on the clock
     * (see EIP-6372) this contract uses.
     */
    function proposalGracePeriod() external view returns (uint256);

    /**
     * @notice A governance-only function to update the proposal grace period.
     */
    function setProposalGracePeriod(uint256 newGracePeriod) external;

    /**
     * Create a new proposal. Emits a {ProposalCreated} event.
     *
     * @dev Accounts with the PROPOSER_ROLE can submit proposals regardless of delegation.
     *
     * @param targets The execution targets.
     * @param values The execution values.
     * @param calldatas The execution calldatas.
     * @param signatures The human-readable signatures associated with the calldatas selectors. These are checked
     * against the selectors in the calldatas to ensure the provided actions line up with the human-readable signatures.
     * @param description The proposal description.
     * @dev If the proposal description ends with `#proposer=0x???`, where `0x???` is an address written as a hex string
     * (case insensitive), then the submission of this proposal will only be authorized to said address. This is used
     * as an opt-in protection against front-running.
     * @return proposalId Returns the ID of the newly created proposal.
     */
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string[] calldata signatures,
        string calldata description
    )
        external
        returns (uint256 proposalId);

    /**
     * @notice Queue a proposal in the Timelock for execution. This requires the quorum to be reached, the vote to be
     * successful, and the deadline to be reached.Emits a {ProposalQueued} event.
     */
    function queue(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        external
        returns (uint256 proposalId_);

    /**
     * @notice Execute a queued proposal. Requires that the operation ETA is has been reached in the timelock, and that
     * the operation has not expired.
     */
    function execute(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        external
        returns (uint256 proposalId_);

    /**
     * @notice Cancel a proposal. A proposal is cancellable by the proposer, but only while it is Pending state, i.e.
     * before the vote starts.
     *
     * Emits a {ProposalCanceled} event.
     *
     * @dev Accounts with the CANCELER_ROLE can cancel the proposal anytime before execution. It is recommended to set
     * an expiresAt timestamp for any CANCELER_ROLE grants, or else they can cancel any proposal forever into the
     * future.
     */
    function cancel(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        external
        returns (uint256 proposalId_);

    /**
     * @dev Batch method for granting roles. Only governance.
     * @param roles The bytes32 role hashes to grant.
     * @param accounts The accounts to grant each role to.
     * @param expiresAts The expiration timestamp for each role. Can be set to type(uint256).max for infinite. After
     * this timestamp, an account will not be able to fulfill the access of this role anymore.
     */
    function grantRoles(bytes32[] memory roles, address[] memory accounts, uint256[] memory expiresAts) external;

    /**
     * @dev Batch method for revoking roles. Only governance.
     * @param roles The bytes32 roles to revoke.
     * @param accounts The accounts to revoke each role from.
     */
    function revokeRoles(bytes32[] memory roles, address[] memory accounts) external;
}
