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

    bytes32 public immutable PROPOSER_ROLE = keccak256("PROPOSER");
    bytes32 public immutable CANCELER_ROLE = keccak256("CANCELER");

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
        _grantRoles(roles, accounts, expiresAts);
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL GETTERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IProposals
    function proposalCount() public view virtual returns (uint256 count) {
        return ProposalsLogicV1.proposalCount();
    }

    /// @inheritdoc IProposals
    function proposalSnapshot(uint256 proposalId) public view virtual returns (uint256 snapshot) {
        return ProposalsLogicV1.proposalSnapshot(proposalId);
    }

    /// @inheritdoc IProposals
    function proposalDeadline(uint256 proposalId) public view virtual returns (uint256 deadline) {
        return ProposalsLogicV1.proposalDeadline(proposalId);
    }

    /// @inheritdoc IProposals
    function proposalProposer(uint256 proposalId) public view virtual returns (address proposer) {
        return ProposalsLogicV1.proposalProposer(proposalId);
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
        ProposalsLogicV1.hashProposalActions(targets, values, calldatas);
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
        ProposalsLogicV1.setProposalThresholdBps();
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
        override
        returns (uint256 proposalId)
    {
        address proposer = _msgSender();

        uint256 snapshot;
        uint256 duration;
        {
            (, uint256 currentClock) = _authorizeProposal(proposer, targets, values, calldatas, description);

            (uint256 _votingDelay, uint256 _votingPeriod) = _getVotingDelayAndPeriod();

            snapshot = currentClock + _votingDelay;
            duration = _votingPeriod;
        }

        proposalId = _propose(proposer, snapshot, duration, targets, values, calldatas, signatures, description);
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
        assembly ("memory-safe") {
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
            assembly ("memory-safe") {
                // Shift right by 20 address bytes + 1 bool byte = 21 bytes * 8 = 168 bits
                _governanceCanBeginAt := and(shr(0xa8, packedGovernorBaseStorage), 0xffffffffff)
            }
            if (block.timestamp < _governanceCanBeginAt) {
                revert GovernorCannotBeFoundedYet(_governanceCanBeginAt);
            }

            // Check the governance threshold
            uint256 _governanceThresholdBps;
            assembly ("memory-safe") {
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
        string[] memory signatures,
        string calldata description
    )
        internal
        virtual
        returns (uint256 proposalId)
    {
        BatchArrayChecker.checkArrayLengths(targets.length, values.length, calldatas.length, signatures.length);

        // Verify the human-readable function signatures
        _validateCalldataSignatures(calldatas, signatures);

        // Increment proposal counter
        ProposalsStorage storage $ = _getProposalsStorage();
        {
            bytes32 actionsHash = hashProposalActions(targets, values, calldatas);
            proposalId = ++$._proposalCount;
            $._proposalActionsHashes[proposalId] = actionsHash;
        }

        ProposalCore storage proposal = $._proposals[proposalId];
        proposal.proposer = proposer;
        proposal.voteStart = snapshot.toUint48();
        proposal.voteDuration = duration.toUint32();

        emit ProposalCreated(
            proposalId, proposer, targets, values, calldatas, signatures, snapshot, snapshot + duration, description
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
        DoubleEndedQueue.Bytes32Deque storage governanceCall = GovernorBaseLogicV1._getGovernanceCallQueue();
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

    /// @dev Override to check that the threshold is still met at the end of the proposal period
    function _foundGovernor(uint256 proposalId) internal virtual override {
        GovernorBaseStorage storage _governorBaseStorage;
        assembly {
            _governorBaseStorage.slot := GOVERNOR_BASE_STORAGE
        }

        IGovernorToken _token = _governorBaseStorage._token;
        uint256 _governanceThresholdBps = _governorBaseStorage._governanceThresholdBps;

        // Check that the total supply at the vote end is still above the threshold
        uint256 voteEndedSupply = _token.getPastTotalSupply(proposalDeadline(proposalId));
        uint256 threshold = _token.maxSupply().bpsUnchecked(_governanceThresholdBps);
        if (voteEndedSupply < threshold) {
            revert GovernorFoundingVoteThresholdNotMet(threshold, voteEndedSupply);
        }

        super._foundGovernor(proposalId);
    }

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
     * @dev Gas-optimized validation. Assumes that the array lengths have already been checked
     */
    function _validateCalldataSignatures(bytes[] calldata calldatas, string[] memory signatures) internal pure {
        assembly ("memory-safe") {
            let i := 0
            for {} lt(i, calldatas.length) { i := add(i, 0x01) } {
                // If the calldata item byte length is greater than zero, check the signature
                let calldataItemOffset := add(calldatas.offset, calldataload(add(calldatas.offset, mul(i, 0x20))))
                if gt(calldataload(calldataItemOffset), 0) {
                    // Load the function selector from the currnet calldata item (shift right 28 * 8 = 224 bits)
                    let selector := shr(224, calldataload(add(0x20, calldataItemOffset)))

                    let signature := mload(add(0x20, add(signatures, mul(i, 0x20))))
                    let signatureLength := mload(signature)
                    let signatureHash := keccak256(add(signature, 0x20), signatureLength)

                    if iszero(eq(selector, shr(224, signatureHash))) {
                        // `GovernorInvalidActionSignature(uint256)`
                        mstore(0, 0xb8e4a11400000000000000000000000000000000000000000000000000000000)
                        mstore(0x04, i) // index
                        revert(0, 0x24)
                    }
                }
            }
        }
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
        assembly ("memory-safe") {
            len := description.length
        }

        // Length is too short to contain a valid proposer suffix
        if (len < 52) {
            return true;
        }

        // Extract what would be the `#proposer=0x` marker beginning the suffix
        bytes12 marker;
        assembly ("memory-safe") {
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
