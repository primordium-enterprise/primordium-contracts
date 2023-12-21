// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

interface IProposalVoting {
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

    /**
     * @notice Returns whether `account` has cast a vote on `proposalId`.
     */
    function hasVoted(uint256 proposalId, address account) external view returns (bool);

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