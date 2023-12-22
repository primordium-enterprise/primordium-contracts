// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {GovernorBase} from "./GovernorBase.sol";
import {IProposals} from "../interfaces/IProposals.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Roles} from "src/utils/Roles.sol";
import {IGovernorToken} from "../interfaces/IGovernorToken.sol";
import {Enum} from "src/common/Enum.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {MultiSendEncoder} from "src/libraries/MultiSendEncoder.sol";
import {SelectorChecker} from "src/libraries/SelectorChecker.sol";
import {BatchArrayChecker} from "src/utils/BatchArrayChecker.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";

/**
 * @title Proposals
 * @notice Logic for creating, queueing, and executing Governor proposals.
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract Proposals is GovernorBase, IProposals, Roles {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using SafeCast for uint256;
    using BasisPoints for uint256;

    struct ProposalCore {
        address proposer; // 20 bytes
        uint48 voteStart; // 6 bytes
        uint32 voteDuration; // 4 bytes
        bool executed; // 1 byte
        bool canceled; // 1 byte
    }

    bytes32 private constant ALL_PROPOSAL_STATES_BITMAP = bytes32((2 ** (uint8(type(ProposalState).max) + 1)) - 1);

    bytes32 public immutable PROPOSER_ROLE = keccak256("PROPOSER");
    bytes32 public immutable CANCELER_ROLE = keccak256("CANCELER");

    /// @custom:storage-location erc7201:Proposals.Storage
    struct ProposalsStorage {
        uint256 _proposalCount;
        // Tracking core proposal data
        mapping(uint256 => ProposalCore) _proposals;
        // Tracking hashes of each proposal's actions
        mapping(uint256 => bytes32) _proposalActionsHashes;
        // Tracking queued operations on the TimelockAvatar
        mapping(uint256 => uint256) _proposalOpNonces;
    }

    // keccak256(abi.encode(uint256(keccak256("Proposals.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant PROPOSALS_STORAGE = 0x12dae0b7a75163feb738f3ebdd36c1ba0747f551a5ac705c9e7c1824cec3b800;

    function _getProposalsStorage() internal pure returns (ProposalsStorage storage $) {
        assembly {
            $.slot := PROPOSALS_STORAGE
        }
    }

    /// @custom:storage-location erc7201:Proposals.ProposalSettings.Storage
    struct ProposalSettingsStorage {
        uint16 _proposalThresholdBps;
        // uint24 allows each period to be up to 194 days long using timestamps (longer using block numbers)
        uint24 _votingDelay;
        uint24 _votingPeriod;
        // Grace period can be set to max to be unlimited
        uint48 _gracePeriod;
    }

    // keccak256(abi.encode(uint256(keccak256("Proposals.ProposalSettings.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant PROPOSAL_SETTINGS_STORAGE =
        0xddaa15f4123548e9bd63b0bf0b1ef94e9857e581d03ae278a788cfe245267b00;

    function _getProposalSettingsStorage() internal pure returns (ProposalSettingsStorage storage $) {
        assembly {
            $.slot := PROPOSAL_SETTINGS_STORAGE
        }
    }

    function __Proposals_init(
        uint256 proposalThresholdBps_,
        uint256 votingDelay_,
        uint256 votingPeriod_,
        uint256 gracePeriod_,
        bytes memory initGrantRoles
    ) internal virtual onlyInitializing {
        _setProposalThresholdBps(proposalThresholdBps_);
        _setVotingDelay(votingDelay_);
        _setVotingPeriod(votingPeriod_);
        _setProposalGracePeriod(gracePeriod_);

        (bytes32[] memory roles, address[] memory accounts, uint256[] memory expiresAts) =
            abi.decode(initGrantRoles, (bytes32[], address[], uint256[]));
        _grantRoles(roles, accounts, expiresAts);
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL GETTERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IProposals
    function proposalCount() public view virtual returns (uint256 count) {
        count = _getProposalsStorage()._proposalCount;
    }

    /// @inheritdoc IProposals
    function proposalSnapshot(uint256 proposalId) public view virtual override returns (uint256 snapshot) {
        snapshot = _getProposalsStorage()._proposals[proposalId].voteStart;
    }

    /// @inheritdoc IProposals
    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256 deadline) {
        ProposalsStorage storage $ = _getProposalsStorage();
        deadline = $._proposals[proposalId].voteStart + $._proposals[proposalId].voteDuration;
    }

    /// @inheritdoc IProposals
    function proposalProposer(uint256 proposalId) public view virtual override returns (address proposer) {
        proposer = _getProposalsStorage()._proposals[proposalId].proposer;
    }

    /// @inheritdoc IProposals
    function proposalActionsHash(uint256 proposalId) public view virtual override returns (bytes32 actionsHash) {
        actionsHash = _getProposalsStorage()._proposalActionsHashes[proposalId];
    }

    /// @inheritdoc IProposals
    function proposalEta(uint256 proposalId) public view virtual override returns (uint256 eta) {
        uint256 opNonce = _getProposalsStorage()._proposalOpNonces[proposalId];
        if (opNonce == 0) {
            return eta;
        }
        eta = executor().getOperationExecutableAt(opNonce);
    }

    /// @inheritdoc IProposals
    function proposalOpNonce(uint256 proposalId) public view virtual override returns (uint256 opNonce) {
        opNonce = _getProposalsStorage()._proposalOpNonces[proposalId];
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
        override
        returns (bytes32)
    {
        return keccak256(abi.encode(targets, values, calldatas));
    }

    /// @inheritdoc IProposals
    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        ProposalsStorage storage $ = _getProposalsStorage();

        // Single SLOAD
        ProposalCore storage proposal = $._proposals[proposalId];
        bool proposalExecuted = proposal.executed;
        bool proposalCanceled = proposal.canceled;

        if (proposalExecuted) {
            return ProposalState.Executed;
        }

        if (proposalCanceled) {
            return ProposalState.Canceled;
        }

        uint256 snapshot = proposalSnapshot(proposalId);

        if (snapshot == 0) {
            revert GovernorUnknownProposalId(proposalId);
        }

        uint256 currentTimepoint = clock();

        if (snapshot >= currentTimepoint) {
            return ProposalState.Pending;
        }

        uint256 deadline = proposalDeadline(proposalId);

        if (deadline >= currentTimepoint) {
            return ProposalState.Active;
        }

        // If no quorum was reached, or if the vote did not succeed, the proposal is defeated
        if (!_quorumReached(proposalId) || !_voteSucceeded(proposalId)) {
            return ProposalState.Defeated;
        }

        uint256 opNonce = $._proposalOpNonces[proposalId];
        if (opNonce == 0) {
            uint256 grace = proposalGracePeriod();
            if (deadline + grace >= currentTimepoint) {
                return ProposalState.Expired;
            }
            return ProposalState.Succeeded;
        }

        ITimelockAvatar.OperationStatus opStatus = executor().getOperationStatus(opNonce);
        if (opStatus == ITimelockAvatar.OperationStatus.Done) {
            return ProposalState.Executed;
        }
        if (opStatus == ITimelockAvatar.OperationStatus.Expired) {
            return ProposalState.Expired;
        }

        return ProposalState.Queued;
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL SETTINGS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IProposals
    function proposalThreshold() public view virtual returns (uint256 _proposalThreshold) {
        IGovernorToken _token = token();
        uint256 _proposalThresholdBps = proposalThresholdBps();

        // Use unchecked, overflow not a problem as long as the token's max supply <= type(uint224).max
        _proposalThreshold = _proposalThresholdBps.bpsUnchecked(_token.getPastTotalSupply(_clock(_token) - 1));
    }

    /// @inheritdoc IProposals
    function proposalThresholdBps() public view virtual returns (uint256 _proposalThresholdBps) {
        _proposalThresholdBps = _getProposalSettingsStorage()._proposalThresholdBps;
    }

    /// @inheritdoc IProposals
    function setProposalThresholdBps(uint256 newProposalThresholdBps) public virtual onlyGovernance {
        _setProposalThresholdBps(newProposalThresholdBps);
    }

    function _setProposalThresholdBps(uint256 newProposalThresholdBps) internal virtual {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();

        emit ProposalThresholdBPSUpdate($._proposalThresholdBps, newProposalThresholdBps);
        $._proposalThresholdBps = newProposalThresholdBps.toBps();
    }

    /// @inheritdoc IProposals
    function votingDelay() public view virtual override returns (uint256 _votingDelay) {
        _votingDelay = _getProposalSettingsStorage()._votingDelay;
    }

    /// @inheritdoc IProposals
    function setVotingDelay(uint256 newVotingDelay) public virtual onlyGovernance {
        _setVotingDelay(newVotingDelay);
    }

    function _setVotingDelay(uint256 newVotingDelay) internal virtual {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();

        emit VotingDelayUpdate($._votingDelay, newVotingDelay);
        $._votingDelay = SafeCast.toUint24(newVotingDelay);
    }

    /// @inheritdoc IProposals
    function votingPeriod() public view virtual override returns (uint256 _votingPeriod) {
        _votingPeriod = _getProposalSettingsStorage()._votingPeriod;
    }

    /// @inheritdoc IProposals
    function setVotingPeriod(uint256 newVotingPeriod) public virtual onlyGovernance {
        _setVotingPeriod(newVotingPeriod);
    }

    function _setVotingPeriod(uint256 newVotingPeriod) internal virtual {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();

        emit VotingPeriodUpdate($._votingPeriod, newVotingPeriod);
        $._votingPeriod = SafeCast.toUint24(newVotingPeriod);
    }

    /// @inheritdoc IProposals
    function proposalGracePeriod() public view virtual override returns (uint256 _gracePeriod) {
        _gracePeriod = _getProposalSettingsStorage()._gracePeriod;
    }

    /// @inheritdoc IProposals
    function setProposalGracePeriod(uint256 newGracePeriod) public virtual onlyGovernance {
        _setProposalGracePeriod(newGracePeriod);
    }

    function _setProposalGracePeriod(uint256 newGracePeriod) internal virtual {
        // Don't allow overflow for setting to a high value "unlimited" value
        if (newGracePeriod > type(uint48).max) {
            newGracePeriod = type(uint48).max;
        }

        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        emit ProposalGracePeriodUpdate($._gracePeriod, newGracePeriod);
        $._gracePeriod = uint48(newGracePeriod);
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL CREATION/EXECUTION LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IProposals
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string[] calldata signatures,
        string calldata description
    )
        public
        virtual
        override
        returns (uint256 proposalId)
    {
        address proposer = _msgSender();

        (, uint256 currentClock) = _authorizeProposal(proposer, targets, values, calldatas, description);

        (uint256 _votingDelay, uint256 duration) = _getVotingDelayAndPeriod();

        proposalId = _propose(
            proposer, currentClock + _votingDelay, duration, targets, values, calldatas, signatures, description
        );
    }

    /**
     * @dev Authorizes whether a proposal can be submitted by the provided proposer. Also includes front-running
     * protection as used in OpenZeppelin 5.0.0's {Governor.sol} contract.
     *
     * @notice This function checks whether the Governor has been founded, and restricts proposals to only initializing
     * governance if the Governor is not yet founded.
     *
     * @return _token The IGovernorToken token read from storage for internal gas optimization
     * @return currentClock The current clock() value for the token for internal gas optimization (avoid re-calling)
     */
    function _authorizeProposal(
        address proposer,
        address[] calldata targets,
        uint256[] calldata, /*values*/
        bytes[] calldata calldatas,
        string calldata description
    )
        internal
        view
        virtual
        returns (IGovernorToken _token, uint256 currentClock)
    {
        // check description restriction
        if (!_isValidDescriptionForProposer(proposer, description)) {
            revert GovernorRestrictedProposer(proposer);
        }

        // check founded status
        bytes32 packedGovernorBaseStorage;
        bool isFounded;
        assembly {
            packedGovernorBaseStorage := sload(GOVERNOR_BASE_STORAGE)
            _token := packedGovernorBaseStorage
            // The _isFounded bool is at byte index 20 (after the 20 address bytes), so shift right 20 * 8 = 160 bits
            isFounded := and(shr(160, packedGovernorBaseStorage), 0xff)
        }

        currentClock = _clock(_token);

        // Check if the Governor has been founded yet
        if (!isFounded) {
            // Check if goverance can begin yet
            uint256 _governanceCanBeginAt;
            assembly {
                // Shift right by 20 address bytes + 1 bool byte = 21 bytes * 8 = 168 bits
                _governanceCanBeginAt := and(shr(0xa8, packedGovernorBaseStorage), 0xffffffffff)
            }
            if (block.timestamp < _governanceCanBeginAt) {
                revert GovernorCannotBeFoundedYet(_governanceCanBeginAt);
            }

            // Check the governance threshold
            uint256 _governanceThresholdBps;
            assembly {
                // Shift right by 20 address bytes + 1 bool byte + 5 uint40 bytes = 26 bytes * 8 = 208 bits
                _governanceThresholdBps := and(shr(0xd0, packedGovernorBaseStorage), 0xffff)
            }
            uint256 currentSupply = _token.totalSupply();
            uint256 threshold = _token.maxSupply().bpsUnchecked(_governanceThresholdBps);
            if (currentSupply < threshold) {
                revert GovernorFoundingVoteThresholdNotMet(threshold, currentSupply);
            }

            // Ensure that the only proposal action is to foundGovernor() on this Governor
            bytes calldata initData = calldatas[0];
            // forgefmt: disable-next-item
            if (
                targets.length != 1 ||
                targets[0] != address(this) ||
                bytes4(initData) != this.foundGovernor.selector ||
                initData.length != 36 // 4 selector bytes + 32 proposalId bytes
            ) {
                revert GovernanceInitializationActionRequired();
            }

            // Check that the provided proposalId is the expected proposalId
            uint256 expectedProposalId = _getProposalsStorage()._proposalCount + 1;
            uint256 providedProposalId;
            assembly ("memory-safe") {
                // Offset by 4 bytes for the function selector
                providedProposalId := calldataload(add(initData.offset, 0x04))
            }
            if (providedProposalId != expectedProposalId) {
                revert GovernorInvalidFoundingProposalID(expectedProposalId, providedProposalId);
            }
        }

        // Check the proposer's votes against the proposalThreshold(), also check the proposer's role
        // forgefmt: disable-next-item
        if (
            _getVotes(_token, proposer, currentClock - 1, _defaultParams()) < proposalThreshold() &&
            !_hasRole(PROPOSER_ROLE, proposer)
        ) revert GovernorUnauthorized(proposer);
    }

    function _propose(
        address proposer,
        uint256 snapshot,
        uint256 duration,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string[] calldata signatures,
        string calldata description
    )
        internal
        virtual
        returns (uint256 proposalId)
    {
        ProposalsStorage storage $ = _getProposalsStorage();

        BatchArrayChecker.checkArrayLengths(targets.length, values.length, calldatas.length, signatures.length);

        // Verify the human-readable function signatures
        SelectorChecker.verifySelectors(calldatas, signatures);

        // Increment proposal counter
        proposalId = ++$._proposalCount;

        ProposalCore storage proposal = $._proposals[proposalId];
        $._proposalActionsHashes[proposalId] = hashProposalActions(targets, values, calldatas);
        proposal.proposer = proposer;
        proposal.voteStart = snapshot.toUint48();
        proposal.voteDuration = duration.toUint32();

        emit ProposalCreated(
            proposalId, proposer, targets, values, signatures, calldatas, snapshot, snapshot + duration, description
        );
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
        override
        returns (uint256)
    {
        ProposalsStorage storage $ = _getProposalsStorage();

        _validateStateBitmap(proposalId, _encodeStateBitmap(ProposalState.Succeeded));

        if ($._proposalActionsHashes[proposalId] != hashProposalActions(targets, values, calldatas)) {
            revert GovernorInvalidProposalActions(proposalId);
        }

        ITimelockAvatar _executor = executor();
        (address to, uint256 value, bytes memory data) =
            MultiSendEncoder.encodeMultiSendCalldata(address(_executor), targets, values, calldatas);

        (, bytes memory returnData) =
            _executor.execTransactionFromModuleReturnData(to, value, data, Enum.Operation.Call);

        (uint256 opNonce,, uint256 eta) = abi.decode(returnData, (uint256, bytes32, uint256));
        $._proposalOpNonces[proposalId] = opNonce;

        emit ProposalQueued(proposalId, eta);

        return proposalId;
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
        override
        returns (uint256)
    {
        ProposalsStorage storage $ = _getProposalsStorage();

        _validateStateBitmap(proposalId, _encodeStateBitmap(ProposalState.Queued));

        // NOTE: We don't check the actionsHash here because the TimelockAvatar's opHash will be checked
        $._proposals[proposalId].executed = true;

        // before execute: queue any operations on self
        DoubleEndedQueue.Bytes32Deque storage governanceCall = _getGovernanceCallQueue();
        for (uint256 i = 0; i < targets.length; ++i) {
            if (targets[i] == address(this)) {
                governanceCall.pushBack(keccak256(calldatas[i]));
            }
        }

        _executeOperations(proposalId, targets, values, calldatas);

        // after execute: cleanup governance call queue
        if (!governanceCall.empty()) {
            governanceCall.clear();
        }

        emit ProposalExecuted(proposalId);

        return proposalId;
    }

    /**
     * @dev Overridden execute function that run the already queued proposal through the timelock.
     */
    function _executeOperations(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        internal
        virtual
    {
        ITimelockAvatar _executor = executor();
        (address to, uint256 value, bytes memory data) =
            MultiSendEncoder.encodeMultiSendCalldata(address(_executor), targets, values, calldatas);

        ProposalsStorage storage $ = _getProposalsStorage();
        _executor.executeOperation($._proposalOpNonces[proposalId], to, value, data, Enum.Operation.Call);
    }

    /// @inheritdoc IProposals
    function cancel(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
        virtual
        override
        returns (uint256)
    {
        ProposalsStorage storage $ = _getProposalsStorage();
        if ($._proposalActionsHashes[proposalId] != hashProposalActions(targets, values, calldatas)) {
            revert GovernorInvalidProposalActions(proposalId);
        }

        // Only allow cancellation if the sender is CANCELER_ROLE, or if the proposer cancels before voting starts
        if (!_hasRole(CANCELER_ROLE, msg.sender)) {
            if (msg.sender != proposalProposer(proposalId)) {
                revert GovernorUnauthorized(msg.sender);
            }
            _validateStateBitmap(proposalId, _encodeStateBitmap(ProposalState.Pending));
        }

        return _cancel(proposalId);
    }

    /**
     * @dev Internal cancel mechanism: locks up the proposal timer, preventing it from being re-submitted. Marks it as
     * canceled to allow distinguishing it from executed proposals.
     *
     * Emits a {IGovernor-ProposalCanceled} event.
     */
    function _cancel(uint256 proposalId) internal virtual returns (uint256) {
        // Can cancel in any state other than Canceled, Expired, or Executed.
        _validateStateBitmap(
            proposalId,
            ALL_PROPOSAL_STATES_BITMAP ^ _encodeStateBitmap(ProposalState.Canceled)
                ^ _encodeStateBitmap(ProposalState.Expired) ^ _encodeStateBitmap(ProposalState.Executed)
        );

        ProposalsStorage storage $ = _getProposalsStorage();
        $._proposals[proposalId].canceled = true;

        // Cancel the op if it exists (will revert if it cannot be cancelled)
        uint256 opNonce = $._proposalOpNonces[proposalId];
        if (opNonce != 0) {
            executor().cancelOperation(opNonce);
        }

        emit ProposalCanceled(proposalId);

        return proposalId;
    }

    /// @inheritdoc IProposals
    function quorum(uint256 timepoint) public view virtual returns (uint256);

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
        _grantRoles(roles, accounts, expiresAts);
    }

    /// @inheritdoc IProposals
    function revokeRoles(bytes32[] memory roles, address[] memory accounts) public virtual override onlyGovernance {
        _revokeRoles(roles, accounts);
    }

    /// @dev Get both values at once to optimize gas where applicable
    function _getVotingDelayAndPeriod() internal view virtual returns (uint256 _votingDelay, uint256 _votingPeriod) {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        _votingDelay = $._votingDelay;
        _votingPeriod = $._votingPeriod;
    }

    /// @dev Amount of votes already cast passes the threshold limit.
    function _quorumReached(uint256 proposalId) internal view virtual returns (bool);

    /// @dev Is the proposal successful or not.
    function _voteSucceeded(uint256 proposalId) internal view virtual returns (bool);

    /**
     * @dev Encodes a `ProposalState` into a `bytes32` representation where each bit enabled corresponds to
     * the underlying position in the `ProposalState` enum. For example:
     *
     * 0x000...10000
     *   ^^^^^^------ ...
     *         ^----- Succeeded
     *          ^---- Defeated
     *           ^--- Canceled
     *            ^-- Active
     *             ^- Pending
     */
    function _encodeStateBitmap(ProposalState proposalState) internal pure returns (bytes32) {
        return bytes32(1 << uint8(proposalState));
    }

    /**
     * @dev Check that the current state of a proposal matches the requirements described by the `allowedStates` bitmap.
     * This bitmap should be built using `_encodeStateBitmap`.
     *
     * If requirements are not met, reverts with a {GovernorUnexpectedProposalState} error.
     */
    function _validateStateBitmap(uint256 proposalId, bytes32 allowedStates) internal view returns (ProposalState) {
        ProposalState currentState = state(proposalId);
        if (_encodeStateBitmap(currentState) & allowedStates == bytes32(0)) {
            revert GovernorUnexpectedProposalState(proposalId, currentState, allowedStates);
        }
        return currentState;
    }

    /**
     * @dev Check if the proposer is authorized to submit a proposal with the given description.
     *
     * If the proposal description ends with `#proposer=0x???`, where `0x???` is an address written as a hex string
     * (case insensitive), then the submission of this proposal will only be authorized to said address.
     *
     * This is used for frontrunning protection. By adding this pattern at the end of their proposal, one can ensure
     * that no other address can submit the same proposal. An attacker would have to either remove or change that part,
     * which would result in a different proposal id.
     *
     * If the description does not match this pattern, it is unrestricted and anyone can submit it. This includes:
     * - If the `0x???` part is not a valid hex string.
     * - If the `0x???` part is a valid hex string, but does not contain exactly 40 hex digits.
     * - If it ends with the expected suffix followed by newlines or other whitespace.
     * - If it ends with some other similar suffix, e.g. `#other=abc`.
     * - If it does not end with any such suffix.
     */
    function _isValidDescriptionForProposer(
        address proposer,
        string calldata description
    )
        internal
        view
        virtual
        returns (bool)
    {
        uint256 len;
        assembly {
            len := description.length
        }

        // Length is too short to contain a valid proposer suffix
        if (len < 52) {
            return true;
        }

        // Extract what would be the `#proposer=0x` marker beginning the suffix
        bytes12 marker;
        assembly {
            // - Start of the string contents in calldata = description.offset
            // - First character of the marker = len - 52
            //   - Length of "#proposer=0x0000000000000000000000000000000000000000" = 52
            // - We read the memory word starting at the first character of the marker:
            //   - (description.offset) + (len - 52)
            // - Note: Solidity will ignore anything past the first 12 bytes
            marker := calldataload(add(description.offset, sub(len, 52)))
        }

        // If the marker is not found, there is no proposer suffix to check
        if (marker != bytes12("#proposer=0x")) {
            return true;
        }

        // Parse the 40 characters following the marker as uint160
        uint160 recovered = 0;
        for (uint256 i = len - 40; i < len;) {
            (bool isHex, uint8 value) = _tryHexToUint(bytes(description)[i]);
            // If any of the characters is not a hex digit, ignore the suffix entirely
            if (!isHex) {
                return true;
            }
            recovered = (recovered << 4) | value;
            unchecked {
                ++i;
            }
        }

        return recovered == uint160(proposer);
    }

    /**
     * @dev Try to parse a character from a string as a hex value. Returns `(true, value)` if the char is in
     * `[0-9a-fA-F]` and `(false, 0)` otherwise. Value is guaranteed to be in the range `0 <= value < 16`
     */
    function _tryHexToUint(bytes1 char) private pure returns (bool, uint8) {
        uint8 c = uint8(char);
        unchecked {
            // Case 0-9
            if (47 < c && c < 58) {
                return (true, c - 48);
            }
            // Case A-F
            else if (64 < c && c < 71) {
                return (true, c - 55);
            }
            // Case a-f
            else if (96 < c && c < 103) {
                return (true, c - 87);
            }
            // Else: not a hex char
            else {
                return (false, 0);
            }
        }
    }
}
