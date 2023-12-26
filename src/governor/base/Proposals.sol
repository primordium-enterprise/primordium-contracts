// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (Governor.sol)
// Based on OpenZeppelin Contracts (last updated v5.0.0) (GovernorSettings.sol)

pragma solidity ^0.8.20;

import {GovernorBaseLogicV1} from "./logic/GovernorBaseLogicV1.sol";
import {ProposalsLogicV1} from "./logic/ProposalsLogicV1.sol";
import {GovernorBase} from "./GovernorBase.sol";
import {IProposals} from "../interfaces/IProposals.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Roles} from "src/utils/Roles.sol";
import {RolesLib} from "src/libraries/RolesLib.sol";
import {IGovernorToken} from "../interfaces/IGovernorToken.sol";
import {Enum} from "src/common/Enum.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {MultiSendEncoder} from "src/libraries/MultiSendEncoder.sol";
import {BatchArrayChecker} from "src/utils/BatchArrayChecker.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

/**
 * @title Proposals
 * @notice Logic for creating, queueing, and executing Governor proposals.
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract Proposals is GovernorBase, IProposals, Roles {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using SafeCast for uint256;
    using BasisPoints for uint256;
    using Checkpoints for Checkpoints.Trace208;

    function __Proposals_init_unchained(bytes memory proposalsInitParams) internal virtual onlyInitializing {
        (
            uint256 proposalThresholdBps_,
            uint256 votingDelay_,
            uint256 votingPeriod_,
            uint256 gracePeriod_,
            bytes memory initGrantRoles
        ) = abi.decode(proposalsInitParams, (uint256, uint256, uint256, uint256, bytes));

        _setProposalThresholdBps(proposalThresholdBps_);
        _setVotingDelay(votingDelay_);
        _setVotingPeriod(votingPeriod_);
        _setProposalGracePeriod(gracePeriod_);

        (bytes32[] memory roles, address[] memory accounts, uint256[] memory expiresAts) =
            abi.decode(initGrantRoles, (bytes32[], address[], uint256[]));
        RolesLib._grantRoles(roles, accounts, expiresAts);
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL GETTERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IProposals
    function PROPOSER_ROLE() external pure virtual returns (bytes32) {
        return ProposalsLogicV1._PROPOSER_ROLE;
    }

    /// @inheritdoc IProposals
    function CANCELER_ROLE() external pure virtual returns (bytes32) {
        return ProposalsLogicV1._CANCELER_ROLE;
    }

    /// @inheritdoc IProposals
    function proposalCount() public view virtual returns (uint256 count) {
        return ProposalsLogicV1._proposalCount();
    }

    /// @inheritdoc IProposals
    function proposalSnapshot(uint256 proposalId) public view virtual returns (uint256 snapshot) {
        return ProposalsLogicV1._proposalSnapshot(proposalId);
    }

    /// @inheritdoc IProposals
    function proposalDeadline(uint256 proposalId) public view virtual returns (uint256 deadline) {
        return ProposalsLogicV1._proposalDeadline(proposalId);
    }

    /// @inheritdoc IProposals
    function proposalProposer(uint256 proposalId) public view virtual returns (address proposer) {
        return ProposalsLogicV1._proposalProposer(proposalId);
    }

    /// @inheritdoc IProposals
    function proposalActionsHash(uint256 proposalId) public view virtual returns (bytes32 actionsHash) {
        return ProposalsLogicV1._proposalActionsHash(proposalId);
    }

    /// @inheritdoc IProposals
    function proposalEta(uint256 proposalId) public view virtual returns (uint256 eta) {
        return ProposalsLogicV1._proposalEta(proposalId);
    }

    /// @inheritdoc IProposals
    function proposalOpNonce(uint256 proposalId) public view virtual returns (uint256 opNonce) {
        return ProposalsLogicV1._proposalOpNonce(proposalId);
    }

    /// @inheritdoc IProposals
    function hashProposalActions(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
        pure
        virtual
        returns (bytes32 actionsHash)
    {
        actionsHash = ProposalsLogicV1.hashProposalActions(targets, values, calldatas);
    }

    /// @inheritdoc IProposals
    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        return ProposalsLogicV1.state(proposalId);
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL SETTINGS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IProposals
    function proposalThreshold() public view virtual returns (uint256 _proposalThreshold) {
        return ProposalsLogicV1.proposalThreshold();
    }

    /// @inheritdoc IProposals
    function proposalThresholdBps() public view virtual returns (uint256 _proposalThresholdBps) {
        return ProposalsLogicV1.proposalThresholdBps();
    }

    /// @inheritdoc IProposals
    function setProposalThresholdBps(uint256 newProposalThresholdBps) public virtual onlyGovernance {
        _setProposalThresholdBps(newProposalThresholdBps);
    }

    function _setProposalThresholdBps(uint256 newProposalThresholdBps) internal virtual {
        ProposalsLogicV1.setProposalThresholdBps(newProposalThresholdBps);
    }

    /// @inheritdoc IProposals
    function votingDelay() public view virtual returns (uint256 _votingDelay) {
        return ProposalsLogicV1.votingDelay();
    }

    /// @inheritdoc IProposals
    function setVotingDelay(uint256 newVotingDelay) public virtual onlyGovernance {
        _setVotingDelay(newVotingDelay);
    }

    function _setVotingDelay(uint256 newVotingDelay) internal virtual {
        ProposalsLogicV1.setVotingDelay(newVotingDelay);
    }

    /// @inheritdoc IProposals
    function votingPeriod() public view virtual returns (uint256 _votingPeriod) {
        return ProposalsLogicV1.votingPeriod();
    }

    /// @inheritdoc IProposals
    function setVotingPeriod(uint256 newVotingPeriod) public virtual onlyGovernance {
        _setVotingPeriod(newVotingPeriod);
    }

    function _setVotingPeriod(uint256 newVotingPeriod) internal virtual {
        ProposalsLogicV1.setVotingPeriod(newVotingPeriod);
    }

    /// @inheritdoc IProposals
    function proposalGracePeriod() public view virtual returns (uint256 _gracePeriod) {
        return ProposalsLogicV1.proposalGracePeriod();
    }

    /// @inheritdoc IProposals
    function setProposalGracePeriod(uint256 newGracePeriod) public virtual onlyGovernance {
        _setProposalGracePeriod(newGracePeriod);
    }

    function _setProposalGracePeriod(uint256 newGracePeriod) internal virtual {
        ProposalsLogicV1.setProposalGracePeriod(newGracePeriod);
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL CREATION/EXECUTION LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IProposals
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string[] memory signatures,
        string calldata description
    )
        public
        virtual
        returns (uint256 proposalId)
    {
        proposalId = ProposalsLogicV1.propose(targets, values, calldatas, signatures, description, _msgSender());
    }

    /// @inheritdoc IProposals
    function queue(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
        virtual
        returns (uint256)
    {
        return ProposalsLogicV1.queue(proposalId, targets, values, calldatas);
    }

    /// @inheritdoc IProposals
    function execute(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
        virtual
        returns (uint256)
    {
        return ProposalsLogicV1.execute(proposalId, targets, values, calldatas);
    }

    /// @inheritdoc IProposals
    function cancel(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
        returns (uint256)
    {
        return ProposalsLogicV1.cancel(proposalId, targets, values, calldatas);
    }

    /// @inheritdoc IProposals
    function grantRoles(
        bytes32[] memory roles,
        address[] memory accounts,
        uint256[] memory expiresAts
    )
        public
        virtual
        override
        onlyGovernance
    {
        RolesLib._grantRoles(roles, accounts, expiresAts);
    }

    /// @inheritdoc IProposals
    function revokeRoles(bytes32[] memory roles, address[] memory accounts) public virtual override onlyGovernance {
        RolesLib._revokeRoles(roles, accounts);
    }

    /// @dev Amount of votes already cast passes the threshold limit.
    function _quorumReached(uint256 proposalId) internal view virtual returns (bool);

    /// @dev Is the proposal successful or not.
    function _voteSucceeded(uint256 proposalId) internal view virtual returns (bool);

    /// @dev Override to check that the threshold is still met at the end of the proposal period
    function _foundGovernor(uint256 proposalId) internal virtual override {
        ProposalsLogicV1.checkFoundingProposalGovernanceThreshold(proposalId);
        super._foundGovernor(proposalId);
    }

}
