// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {Proposals} from "./Proposals.sol";
import {IProposalVoting} from "../interfaces/IProposalVoting.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

abstract contract ProposalVoting is
    Proposals,
    IProposalVoting
{
    bytes32 private immutable BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,uint8 support,address voter,uint256 nonce)");
    bytes32 private immutable EXTENDED_BALLOT_TYPEHASH = keccak256(
        "ExtendedBallot(uint256 proposalId,uint8 support,address voter,uint256 nonce,string reason,bytes params)"
    );

    /// @inheritdoc IProposalVoting
    function castVote(uint256 proposalId, uint8 support) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, "");
    }

    /// @inheritdoc IProposalVoting
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    )
        public
        virtual
        override
        returns (uint256)
    {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason);
    }

    /// @inheritdoc IProposalVoting
    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    )
        public
        virtual
        override
        returns (uint256)
    {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason, params);
    }

    /// @inheritdoc IProposalVoting
    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        address voter,
        bytes memory signature
    )
        public
        virtual
        override
        returns (uint256)
    {
        bool valid = SignatureChecker.isValidSignatureNow(
            voter,
            _hashTypedDataV4(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support, voter, _useNonce(voter)))),
            signature
        );

        if (!valid) {
            revert GovernorInvalidSignature(voter);
        }

        return _castVote(proposalId, voter, support, "");
    }

    /// @inheritdoc IProposalVoting
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        address voter,
        string calldata reason,
        bytes memory params,
        bytes memory signature
    )
        public
        virtual
        override
        returns (uint256)
    {
        bool valid = SignatureChecker.isValidSignatureNow(
            voter,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EXTENDED_BALLOT_TYPEHASH,
                        proposalId,
                        support,
                        voter,
                        _useNonce(voter),
                        keccak256(bytes(reason)),
                        keccak256(params)
                    )
                )
            ),
            signature
        );

        if (!valid) {
            revert GovernorInvalidSignature(voter);
        }

        return _castVote(proposalId, voter, support, reason, params);
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function. Uses the _defaultParams().
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason
    )
        internal
        virtual
        returns (uint256)
    {
        return _castVote(proposalId, account, support, reason, _defaultParams());
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function.
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    )
        internal
        virtual
        returns (uint256 weight)
    {
        _validateStateBitmap(proposalId, _encodeStateBitmap(ProposalState.Active));

        ProposalCore storage proposal = _getProposalsStorage()._proposals[proposalId];

        weight = _getVotes(account, proposal.voteStart, params);
        _countVote(proposalId, account, support, weight, params);

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }
    }



    /**
     * @dev Register a vote for `proposalId` by `account` with a given `support`, voting `weight` and voting `params`.
     *
     * Note: Support is generic and can represent various things depending on the voting system used.
     */
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory params
    )
        internal
        virtual;

    /**
     * @dev The vote spread (the difference between For and Against counts)
     */
    function _voteMargin(uint256 proposalId) internal view virtual returns (uint256);
}