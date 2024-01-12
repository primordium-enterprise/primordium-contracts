// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (Governor.sol)
// Based on OpenZeppelin Contracts (last updated v5.0.0) (GovernorCountingSimple.sol)

pragma solidity ^0.8.20;

import {ProposalsLogicV1} from "./logic/ProposalsLogicV1.sol";
import {ProposalVotingLogicV1} from "./logic/ProposalVotingLogicV1.sol";
import {Proposals} from "./Proposals.sol";
import {IProposalVoting} from "../interfaces/IProposalVoting.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";

abstract contract ProposalVoting is Proposals, IProposalVoting {
    bytes32 private immutable BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,uint8 support,address voter,uint256 nonce)");
    bytes32 private immutable EXTENDED_BALLOT_TYPEHASH = keccak256(
        "ExtendedBallot(uint256 proposalId,uint8 support,address voter,uint256 nonce,string reason,bytes params)"
    );

    function __ProposalVoting_init_unchained(ProposalVotingInit memory init) internal virtual onlyInitializing {
        _setPercentMajority(init.percentMajority);
        _setQuorumBps(init.quorumBps);
    }

    /*//////////////////////////////////////////////////////////////////////////
        VOTE COUNTING
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IProposalVoting
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }

    /// @inheritdoc IProposalVoting
    function MIN_PERCENT_MAJORITY() external pure returns (uint256) {
        return ProposalVotingLogicV1._MIN_PERCENT_MAJORITY;
    }

    /// @inheritdoc IProposalVoting
    function MAX_PERCENT_MAJORITY() external pure returns (uint256) {
        return ProposalVotingLogicV1._MAX_PERCENT_MAJORITY;
    }

    /// @inheritdoc IProposalVoting
    function hasVoted(uint256 proposalId, address account) public view virtual override returns (bool) {
        return ProposalVotingLogicV1._hasVoted(proposalId, account);
    }

    /// @inheritdoc IProposalVoting
    function proposalVotes(uint256 proposalId)
        public
        view
        virtual
        returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)
    {
        return ProposalVotingLogicV1._proposalVotes(proposalId);
    }

    /// @inheritdoc IProposalVoting
    function percentMajority(uint256 timepoint) public view virtual returns (uint256) {
        return ProposalVotingLogicV1._percentMajority(timepoint);
    }

    /// @inheritdoc IProposalVoting
    function setPercentMajority(uint256 newPercentMajority) public virtual onlyGovernance {
        _setPercentMajority(newPercentMajority);
    }

    function _setPercentMajority(uint256 newPercentMajority) internal virtual {
        ProposalVotingLogicV1.setPercentMajority(newPercentMajority);
    }

    /// @inheritdoc IProposalVoting
    function quorum(uint256 timepoint) public view virtual returns (uint256 _quorum) {
        _quorum = ProposalVotingLogicV1._quorum(timepoint);
    }

    /// @inheritdoc IProposalVoting
    function quorumBps(uint256 timepoint) public view virtual returns (uint256 _quorumBps) {
        _quorumBps = ProposalVotingLogicV1._quorumBps(timepoint);
    }

    /// @inheritdoc IProposalVoting
    function setQuorumBps(uint256 newQuorumBps) external virtual onlyGovernance {
        _setQuorumBps(newQuorumBps);
    }

    function _setQuorumBps(uint256 newQuorumBps) internal virtual {
        ProposalVotingLogicV1.setQuorumBps(newQuorumBps);
    }

    /*//////////////////////////////////////////////////////////////////////////
        CASTING VOTES
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IProposalVoting
    function castVote(uint256 proposalId, uint8 support) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, "", _defaultParams());
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
        return _castVote(proposalId, voter, support, reason, _defaultParams());
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

        return _castVote(proposalId, voter, support, "", _defaultParams());
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
        weight = ProposalVotingLogicV1.castVote(proposalId, account, support, reason, params);
    }
}
