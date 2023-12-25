// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IProposals} from "../../interfaces/IProposals.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {IGovernorToken} from "../../interfaces/IGovernorToken.sol";
import {MultiSendEncoder} from "src/libraries/MultiSendEncoder.sol";
import {BatchArrayChecker} from "src/utils/BatchArrayChecker.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

/**
 * @title ProposalsLogicV1
 * @author Ben Jett - @BCJdevelopment
 * @notice An external library with the main proposals CRUD logic (for reducing code size)
 * @dev Some functions are internal, meaning they will still be included in a contract's code if the contract makes use
 * of these functions. While this leads to some bytecode duplication across contracts, it also saves on gas by avoiding
 * extra DELEGATECALL's in some cases.
 */
library ProposalsLogicV1 {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using SafeCast for uint256;
    using BasisPoints for uint256;
    using Checkpoints for Checkpoints.Trace208;

    struct ProposalCore {
        address proposer; // 20 bytes
        uint48 voteStart; // 6 bytes
        uint32 voteDuration; // 4 bytes
        bool executed; // 1 byte
        bool canceled; // 1 byte
    }

    bytes32 internal constant ALL_PROPOSAL_STATES_BITMAP =
        bytes32((2 ** (uint8(type(IProposals.ProposalState).max) + 1)) - 1);

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
    bytes32 internal constant PROPOSALS_STORAGE = 0x12dae0b7a75163feb738f3ebdd36c1ba0747f551a5ac705c9e7c1824cec3b800;

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
        Checkpoints.Trace208 _quorumBpsCheckpoints;
    }

    // keccak256(abi.encode(uint256(keccak256("Proposals.ProposalSettings.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant PROPOSAL_SETTINGS_STORAGE =
        0xddaa15f4123548e9bd63b0bf0b1ef94e9857e581d03ae278a788cfe245267b00;

    function _getProposalSettingsStorage() internal pure returns (ProposalSettingsStorage storage $) {
        assembly {
            $.slot := PROPOSAL_SETTINGS_STORAGE
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL GETTERS
    //////////////////////////////////////////////////////////////////////////*/

    function _proposalCount() internal view returns (uint256 count) {
        count = _getProposalsStorage()._proposalCount;
    }

    function _proposalSnapshot(uint256 proposalId) internal view returns (uint256 snapshot) {
        snapshot = _getProposalsStorage()._proposals[proposalId].voteStart;
    }

    function _proposalDeadline(uint256 proposalId) internal view returns (uint256 deadline) {
        ProposalsStorage storage $ = _getProposalsStorage();
        deadline = $._proposals[proposalId].voteStart + $._proposals[proposalId].voteDuration;
    }

    function _proposalProposer(uint256 proposalId) internal view returns (address proposer) {
        proposer = _getProposalsStorage()._proposals[proposalId].proposer;
    }

    function _proposalActionsHash(uint256 proposalId) internal view returns (bytes32 actionsHash) {
        actionsHash = _getProposalsStorage()._proposalActionsHashes[proposalId];
    }

    function _proposalEta(uint256 proposalId) internal view returns (uint256 eta) {
        uint256 opNonce = _getProposalsStorage()._proposalOpNonces[proposalId];
        if (opNonce == 0) {
            return eta;
        }
        eta = executor().getOperationExecutableAt(opNonce);
    }

    function _proposalOpNonce(uint256 proposalId) internal view returns (uint256 opNonce) {
        opNonce = _getProposalsStorage()._proposalOpNonces[proposalId];
    }

    function hashProposalActions(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) public pure returns (bytes32 actionsHash) {
        // Below performs gas-optimized equivalent of "keccak256(abi.encode(targets, values, calldatas))"
        assembly ("memory-safe") {
            // Start at free memory (don't update free mem pointer, just hash and exit)
            let start := mload(0x40)
            // Initialize pointer (3 dynamic arrays, so point past 3 * 32 byte header values)
            let p := add(start, 0x60)

            // Store targets
            {
                mstore(start, 0x60) // targets is first header item, store offset to pointer
                mstore(0, mul(targets.length, 0x20)) // byte length is array length times 32
                mstore(p, targets.length) // store targets length
                calldatacopy(add(p, 0x20), targets.offset, mload(0)) // copy targets array items

                // Increment pointer
                p := add(p, add(0x20, mload(0)))
            }

            // Store values
            {
                mstore(add(start, 0x20), sub(p, start)) // values is second header item, store offset to pointer
                mstore(0, mul(values.length, 0x20)) // byte length is array length times 32
                mstore(p, values.length) // store values length
                calldatacopy(add(p, 0x20), values.offset, mload(0)) // copy values array items

                // Increment pointer
                p := add(p, add(0x20, mload(0)))
            }

            // Store calldatas
            {
                mstore(add(start, 0x40), sub(p, start)) // calldatas is third header item, store offset to pointer
                let calldatasByteLength := 0 // initialize byte length to zero
                if gt(calldatas.length, 0) {
                    // since calldatas is dynamic array of dynamic arrays, not as straightforward to copy...
                    // but the calldata is already abi encoded
                    // so we can add the last item's offset to the last item's (padded) length for total copy length
                    let finalItemOffset := calldataload(add(calldatas.offset, mul(sub(calldatas.length, 0x01), 0x20)))
                    let finalItemByteLength := calldataload(add(calldatas.offset, finalItemOffset))
                    finalItemByteLength := mul(0x20, div(add(finalItemByteLength, 0x1f), 0x20)) // pad to 32 bytes
                    calldatasByteLength :=
                        add(
                            finalItemOffset,
                            add(0x20, finalItemByteLength) // extra 32 bytes for the item length
                        )
                }
                mstore(p, calldatas.length) // store calldatas length
                calldatacopy(add(p, 0x20), calldatas.offset, calldatasByteLength) // copy calldatas array items

                // Increment pointer
                p := add(p, add(0x20, calldatasByteLength))
            }

            // The result is the hash starting at "start", hashing the pointer "p" minus "start" bytes
            actionsHash := keccak256(start, sub(p, start))
        }
    }

    function state(uint256 proposalId) public view returns (IProposals.ProposalState) {
        ProposalsStorage storage $ = _getProposalsStorage();

        // Single SLOAD
        ProposalCore storage proposal = $._proposals[proposalId];
        bool proposalExecuted = proposal.executed;
        bool proposalCanceled = proposal.canceled;

        if (proposalExecuted) {
            return IProposals.ProposalState.Executed;
        }

        if (proposalCanceled) {
            return IProposals.ProposalState.Canceled;
        }

        uint256 snapshot = _proposalSnapshot(proposalId);

        if (snapshot == 0) {
            revert IProposals.GovernorUnknownProposalId(proposalId);
        }

        uint256 currentTimepoint = clock();

        if (snapshot >= currentTimepoint) {
            return IProposals.ProposalState.Pending;
        }

        uint256 deadline = _proposalDeadline(proposalId);

        if (deadline >= currentTimepoint) {
            return IProposals.ProposalState.Active;
        }

        // If no quorum was reached, or if the vote did not succeed, the proposal is defeated
        if (!_quorumReached(proposalId) || !_voteSucceeded(proposalId)) {
            return IProposals.ProposalState.Defeated;
        }

        uint256 opNonce = $._proposalOpNonces[proposalId];
        if (opNonce == 0) {
            uint256 grace = proposalGracePeriod();
            if (deadline + grace >= currentTimepoint) {
                return IProposals.ProposalState.Expired;
            }
            return IProposals.ProposalState.Succeeded;
        }

        ITimelockAvatar.OperationStatus opStatus = executor().getOperationStatus(opNonce);
        if (opStatus == ITimelockAvatar.OperationStatus.Done) {
            return IProposals.ProposalState.Executed;
        }
        if (opStatus == ITimelockAvatar.OperationStatus.Expired) {
            return IProposals.ProposalState.Expired;
        }

        return IProposals.ProposalState.Queued;
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL SETTINGS
    //////////////////////////////////////////////////////////////////////////*/

    function proposalThreshold() public view returns (uint256 proposalThreshold_) {
        IGovernorToken _token = token();
        uint256 _proposalThresholdBps = proposalThresholdBps();

        // Use unchecked, overflow not a problem as long as the token's max supply <= type(uint224).max
        proposalThreshold_ = _proposalThresholdBps.bpsUnchecked(_token.getPastTotalSupply(_clock(_token) - 1));
    }

    function proposalThresholdBps() public view returns (uint256 proposalThresholdBps_) {
        proposalThresholdBps_ = _getProposalSettingsStorage()._proposalThresholdBps;
    }

    function setProposalThresholdBps(uint256 newProposalThresholdBps) public virtual {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();

        emit IProposals.ProposalThresholdBPSUpdate($._proposalThresholdBps, newProposalThresholdBps);
        $._proposalThresholdBps = newProposalThresholdBps.toBps(); // toBps() checks for out of range BPS value
    }

    function votingDelay() public view returns (uint256 _votingDelay) {
        _votingDelay = _getProposalSettingsStorage()._votingDelay;
    }

    function setVotingDelay(uint256 newVotingDelay) public {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();

        emit IProposals.VotingDelayUpdate($._votingDelay, newVotingDelay);
        $._votingDelay = SafeCast.toUint24(newVotingDelay);
    }

    function votingPeriod() public view returns (uint256 _votingPeriod) {
        _votingPeriod = _getProposalSettingsStorage()._votingPeriod;
    }

    function setVotingPeriod(uint256 newVotingPeriod) public virtual {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();

        emit IProposals.VotingPeriodUpdate($._votingPeriod, newVotingPeriod);
        $._votingPeriod = SafeCast.toUint24(newVotingPeriod);
    }

    function proposalGracePeriod() public view returns (uint256 _gracePeriod) {
        _gracePeriod = _getProposalSettingsStorage()._gracePeriod;
    }

    function setProposalGracePeriod(uint256 newGracePeriod) public {
        // Don't allow overflow for setting to a high value "unlimited" value
        if (newGracePeriod > type(uint48).max) {
            newGracePeriod = type(uint48).max;
        }

        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        emit IProposals.ProposalGracePeriodUpdate($._gracePeriod, newGracePeriod);
        $._gracePeriod = uint48(newGracePeriod);
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL CREATION/EXECUTION LOGIC
    //////////////////////////////////////////////////////////////////////////*/

}
