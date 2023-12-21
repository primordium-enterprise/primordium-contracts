// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

interface IProposals {
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

    /**
     * @dev Emitted when a proposal is created.
     */
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
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
    event ProposalCanceled(uint256 indexed proposalId);

    /**
     * @dev Emitted when a proposal is executed.
     */
    event ProposalExecuted(uint256 indexed proposalId);

    /**
     * @dev The current state of a proposal is not the required for performing an operation.
     * The `expectedStates` is a bitmap with the bits enabled for each ProposalState enum position counting from right
     * to left.
     *
     * NOTE: If `expectedState` is `bytes32(0)`, the proposal is expected to not be in any state (i.e. not exist).
     * This is the case when a proposal that is expected to be unset is already initiated (the proposal is duplicated).
     */
    error GovernorUnexpectedProposalState(uint256 proposalId, ProposalState current, bytes32 expectedStates);

    function PROPOSER_ROLE() external view returns (bytes32 proposerRole);
    function CANCELER_ROLE() external view returns (bytes32 cancelerRole);

    /**
     * @notice Returns the total number of submitted proposals.
     */
    function proposalCount() external view returns (uint256 _proposalCount);

    /**
     * @notice The current number of votes that need to be delegated to the msg.sender in order to create a new
     * proposal.
     */
    function proposalThreshold() external view returns (uint256);

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
     */
    function proposalOpNonce(uint256 proposalId) external view returns (uint256);

    /**
     * @notice Delay, between the proposal is created and the vote starts. The unit this duration is expressed in
     * depends on the clock (see EIP-6372) this contract uses.
     *
     * This can be increased to leave time for users to buy voting power, or delegate it, before the voting of a
     * proposal starts.
     */
    function votingDelay() external view returns (uint256);

    /**
     * @notice Delay, between the vote start and vote ends. The unit this duration is expressed in depends on the clock
     * (see EIP-6372) this contract uses.
     *
     * NOTE: The {votingDelay} can delay the start of the vote. This must be considered when setting the voting period
     * compared to the voting delay.
     */
    function votingPeriod() external view returns (uint256);

    /**
     * @notice Grace period after a proposal deadline passes in which a successful proposal must be queued for
     * execution, or else the proposal will expire. The unit this duration is expressed in depends on the clock
     * (see EIP-6372) this contract uses.
     */
    function proposalGracePeriod() external view returns (uint256);

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
     * @notice Minimum number of cast voted required for a proposal to be successful.
     *
     * NOTE: The `timepoint` parameter corresponds to the snapshot used for counting vote. This allows to scale the
     * quorum depending on values such as the totalSupply of a token at this timepoint (see {ERC20Votes}).
     */
    function quorum(uint256 timepoint) external view returns (uint256);

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