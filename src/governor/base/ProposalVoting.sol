// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (Governor.sol)
// Based on OpenZeppelin Contracts (last updated v5.0.0) (GovernorCountingSimple.sol)

pragma solidity ^0.8.20;

import {ProposalVotingLogicV1} from "./logic/ProposalVotingLogicV1.sol";
import {GovernorBase} from "./GovernorBase.sol";
import {IProposalVoting} from "../interfaces/IProposalVoting.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";

/**
 * @title ProposalVoting
 * @author Ben Jett - @benbcjdev
 * @notice Includes vote casting logic for the Governor. Also includes settings for dynamically extending the proposal
 * deadline for last-minute swing votes (see ./logic/ProposalVotingLogicV1).
 */
abstract contract ProposalVoting is GovernorBase, IProposalVoting {
    bytes32 private immutable BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,uint8 support,address voter,uint256 nonce)");
    bytes32 private immutable EXTENDED_BALLOT_TYPEHASH = keccak256(
        "ExtendedBallot(uint256 proposalId,uint8 support,address voter,uint256 nonce,string reason,bytes params)"
    );

    function __ProposalVoting_init_unchained(ProposalVotingInit memory init) internal virtual onlyInitializing {
        _setPercentMajority(init.percentMajority);
        _setQuorumBps(init.quorumBps);

        _setMaxDeadlineExtension(init.maxDeadlineExtension);
        _setBaseDeadlineExtension(init.baseDeadlineExtension);
        _setExtensionDecayPeriod(init.decayPeriod);
        _setExtensionPercentDecay(init.percentDecay);
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

    /// @inheritdoc IProposalVoting
    function proposalDeadline(uint256 proposalId)
        public
        view
        virtual
        override(GovernorBase, IProposalVoting)
        returns (uint256)
    {
        return ProposalVotingLogicV1._proposalDeadline(proposalId);
    }

    /// @inheritdoc IProposalVoting
    function proposalOriginalDeadline(uint256 proposalId) public view virtual returns (uint256) {
        return ProposalVotingLogicV1._originalProposalDeadline(proposalId);
    }

    /// @inheritdoc IProposalVoting
    function maxDeadlineExtension() public view virtual returns (uint256) {
        return ProposalVotingLogicV1._maxDeadlineExtension();
    }

    /// @inheritdoc IProposalVoting
    function setMaxDeadlineExtension(uint256 newMaxDeadlineExtension) public virtual onlyGovernance {
        _setMaxDeadlineExtension(newMaxDeadlineExtension);
    }

    function _setMaxDeadlineExtension(uint256 newMaxDeadlineExtension) internal virtual {
        ProposalVotingLogicV1.setMaxDeadlineExtension(newMaxDeadlineExtension);
    }

    /// @inheritdoc IProposalVoting
    function baseDeadlineExtension() public view virtual returns (uint256) {
        return ProposalVotingLogicV1._baseDeadlineExtension();
    }

    /// @inheritdoc IProposalVoting
    function setBaseDeadlineExtension(uint256 newBaseDeadlineExtension) public virtual onlyGovernance {
        _setBaseDeadlineExtension(newBaseDeadlineExtension);
    }

    function _setBaseDeadlineExtension(uint256 newBaseDeadlineExtension) internal virtual {
        ProposalVotingLogicV1.setBaseDeadlineExtension(newBaseDeadlineExtension);
    }

    /// @inheritdoc IProposalVoting
    function extensionDecayPeriod() public view virtual returns (uint256) {
        return ProposalVotingLogicV1._extensionDecayPeriod();
    }

    /// @inheritdoc IProposalVoting
    function setExtensionDecayPeriod(uint256 newDecayPeriod) public virtual onlyGovernance {
        _setExtensionDecayPeriod(newDecayPeriod);
    }

    function _setExtensionDecayPeriod(uint256 newDecayPeriod) internal virtual {
        return ProposalVotingLogicV1.setExtensionDecayPeriod(newDecayPeriod);
    }

    /// @inheritdoc IProposalVoting
    function extensionPercentDecay() public view virtual returns (uint256) {
        return ProposalVotingLogicV1._extensionPercentDecay();
    }

    /// @inheritdoc IProposalVoting
    function setExtensionPercentDecay(uint256 newPercentDecay) public virtual onlyGovernance {
        _setExtensionPercentDecay(newPercentDecay);
    }

    function _setExtensionPercentDecay(uint256 newPercentDecay) internal virtual {
        ProposalVotingLogicV1.setExtensionPercentDecay(newPercentDecay);
    }
}
