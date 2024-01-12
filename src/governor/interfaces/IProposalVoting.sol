// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

interface IProposalVoting {
    struct ProposalVotingInit {
        uint256 percentMajority;
        uint256 quorumBps;
    }

    /**
     * @dev Supported vote types. Matches GovernorBase Bravo ordering.
     */
    enum VoteType {
        Against,
        For,
        Abstain
    }

    /**
     * @dev Emitted when the percent majority for proposal success is updated.
     */
    event PercentMajorityUpdate(uint256 oldPercentMajority, uint256 newPercentMajority);

    /**
     * @dev Emitted when the quorum BPS value is updated.
     */
    event QuorumBpsUpdate(uint256 oldQuorumBps, uint256 newQuorumBps);

    /**
     * @dev Emitted when a vote is cast without params.
     *
     * Note: `support` values should be seen as buckets. Their interpretation depends on the voting module used.
     */
    event VoteCast(address indexed voter, uint256 indexed proposalId, uint8 support, uint256 weight, string reason);

    /**
     * @dev Emitted when a vote is cast with params.
     *
     * Note: `support` values should be seen as buckets. Their interpretation depends on the voting module used.
     * `params` are additional encoded parameters. Their interpepretation also depends on the voting module used.
     */
    event VoteCastWithParams(
        address indexed voter, uint256 indexed proposalId, uint8 support, uint256 weight, string reason, bytes params
    );

    error GovernorInvalidSignature(address voter);

    error GovernorVoteAlreadyCast(uint256 proposalId, address account);
    error GovernorInvalidVoteValue();
    error GovernorPercentMajorityOutOfRange(uint256 minRange, uint256 maxRange);

    /**
     * @dev A description of the possible `support` values for {castVote} and the way these votes are counted, meant to
     * be consumed by UIs to show correct vote options and interpret the results. The string is a URL-encoded sequence
     * of key-value pairs that each describe one aspect, for example `support=bravo&quorum=for,abstain`.
     *
     * There are 2 standard keys: `support` and `quorum`.
     *
     * - `support=bravo` refers to the vote options 0 = Against, 1 = For, 2 = Abstain, as in `GovernorBravo`.
     * - `quorum=bravo` means that only For votes are counted towards quorum.
     * - `quorum=for,abstain` means that both For and Abstain votes are counted towards quorum.
     *
     * If a counting module makes use of encoded `params`, it should  include this under a `params` key with a unique
     * name that describes the behavior. For example:
     *
     * - `params=fractional` might refer to a scheme where votes are divided fractionally between for/against/abstain.
     * - `params=erc721` might refer to a scheme where specific NFTs are delegated to vote.
     *
     * NOTE: The string can be decoded by the standard
     * https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams[`URLSearchParams`]
     * JavaScript class.
     */
    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() external view returns (string memory);

    /**
     * @dev The minimum setable percent majority for vote success on a proposal. Defaults to 50%.
     */
    function MIN_PERCENT_MAJORITY() external view returns (uint256);

    /**
     * @dev The maximum setable percent majority for vote success on a proposal. Defaults to 66%.
     */
    function MAX_PERCENT_MAJORITY() external view returns (uint256);

    /**
     * @notice Returns whether `account` has cast a vote on `proposalId`.
     */
    function hasVoted(uint256 proposalId, address account) external view returns (bool);

    /**
     * @notice Returns the against votes, the for votes, and the abstain votes for the given proposal ID.
     * @dev These counts can change if the proposal vote period is still active.
     */
    function proposalVotes(uint256 proposalId)
        external
        view
        returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes);

    /**
     * @notice Returns the percent majority at the specified timepoint of for votes required for proposal success.
     */
    function percentMajority(uint256 timepoint) external view returns (uint256);

    /**
     * @notice A governance-only method to update the percent majority for future proposals.
     */
    function setPercentMajority(uint256 newPercentMajority) external;

    /**
     * @notice The minimum number of total votes required for a proposal to be successful.
     *
     * @dev Calculated as the `totalSupply * quorumBps / 10,000`.
     */
    function quorum(uint256 timepoint) external view returns (uint256);

    /**
     * @notice The minimum percentage of the vote token's total supply (in basis points) that must have voted on a
     * proposal in order for it to succeed (regardless of the for vs. against votes).
     */
    function quorumBps(uint256 timepoint) external view returns (uint256);

    /**
     * @notice A governance-only method to update the quorum basis points value. Max value is 10,000.
     */
    function setQuorumBps(uint256 newQuorumBps) external;

    /**
     * @notice Cast a vote. Emits a {VoteCast} event.
     */
    function castVote(uint256 proposalId, uint8 support) external returns (uint256 balance);

    /**
     * @notice Cast a vote with a reason. Emits a {VoteCast} event.
     */
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    )
        external
        returns (uint256 balance);

    /**
     * @notice Cast a vote with a reason and additional encoded parameters. Emits a {VoteCast} or {VoteCastWithParams}
     * event depending on the length of params.
     */
    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    )
        external
        returns (uint256 balance);

    /**
     * @notice Cast a vote using the user's cryptographic signature. Emits a {VoteCast} event.
     *
     * @param signature The signature is a packed bytes encoding of the ECDSA r, s, and v signature values.
     */
    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        address voter,
        bytes memory signature
    )
        external
        returns (uint256 balance);

    /**
     * @notice Cast a vote with a reason and additional encoded parameters using the user's cryptographic signature.
     * Emits a {VoteCast} or {VoteCastWithParams} event depending on the length of params.
     *
     * @param signature The signature is a packed bytes encoding of the ECDSA r, s, and v signature values.
     */
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        address voter,
        string calldata reason,
        bytes memory params,
        bytes memory signature
    )
        external
        returns (uint256 balance);
}
