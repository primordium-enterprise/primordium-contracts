// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {GovernorBaseLogicV1} from "./GovernorBaseLogicV1.sol";
import {ProposalVotingLogicV1} from "./ProposalVotingLogicV1.sol";
import {IProposalDeadlineExtensions} from "../../interfaces/IProposalDeadlineExtensions.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ProposalDeadlineExtensionsLogicV1
 * @author Ben Jett - @BCJdevelopment
 * @notice An external library with the main proposal deadline extension logic (for reducing code size).
 * @dev Some functions are internal, meaning they will still be included in a contract's code if the contract makes use
 * of these functions. While this leads to some bytecode duplication across contracts/libraries, it also saves on gas by
 * avoiding extra DELEGATECALL's in some cases.
 */
library ProposalDeadlineExtensionsLogicV1 {
    using SafeCast for uint256;

    struct DeadlineData {
        uint64 originalDeadline;
        uint64 extendedBy;
        uint64 currentDeadline;
        bool quorumReached;
    }

    uint256 private constant MIN_PERCENT_DECAY = 1;
    /// @notice Maximum percent decay
    uint256 private constant MAX_PERCENT_DECAY = 100;

    uint256 private constant MASK_UINT64 = 0xffffffffffffffff;
    uint256 private constant MASK_UINT8 = 0xff;

    /// @custom:storage-location erc7201:ProposalDeadlineExtensions.Storage
    struct ProposalDeadlineExtensionsStorage {
        // The max extension period for any given proposal
        uint64 _maxDeadlineExtension;
        // The base extension period for deadline extension calculations
        uint64 _baseDeadlineExtension;
        // Bbase extension amount decays by {percentDecay()} every period
        uint64 _decayPeriod;
        uint8 _percentDecay;
        // Tracking the deadlines for a proposal
        mapping(uint256 => DeadlineData) _deadlineDatas;
    }

    // keccak256(abi.encode(uint256(keccak256("ProposalDeadlineExtensions.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant PROPOSAL_DEADLINE_EXTENSIONS_STORAGE =
        0xae976891f3433ecd54a96b3f554eee56d31b6f881a11bab3b6460b6c2f3ce200;

    function _getProposalDeadlineExtensionsStorage()
        private
        pure
        returns (ProposalDeadlineExtensionsStorage storage $)
    {
        assembly {
            $.slot := PROPOSAL_DEADLINE_EXTENSIONS_STORAGE
        }
    }

    /// @dev The fraction multiple used in the vote weight calculation
    uint256 private constant FRACTION_MULTIPLE = 1000;

    /// @dev Max 1.25 multiple on the vote weight
    uint256 private constant FRACTION_MULTIPLE_MAX = FRACTION_MULTIPLE * 5 / 4;

    function setUp(IProposalDeadlineExtensions.ProposalDeadlineExtensionsInit memory init) public {
        setMaxDeadlineExtension(init.maxDeadlineExtension);
        setBaseDeadlineExtension(init.baseDeadlineExtension);
        setExtensionDecayPeriod(init.decayPeriod);
        setExtensionPercentDecay(init.percentDecay);
    }

    function _proposalDeadline(uint256 proposalId) internal view returns (uint256) {
        uint256 currentDeadline = _getProposalDeadlineExtensionsStorage()._deadlineDatas[proposalId].currentDeadline;
        // If uninitialized (no votes cast yet), return the original proposal deadline
        if (currentDeadline == 0) {
            return _originalProposalDeadline(proposalId);
        }
        return currentDeadline;
    }

    function _originalProposalDeadline(uint256 proposalId) internal view returns (uint256) {
        return GovernorBaseLogicV1._proposalDeadline(proposalId);
    }

    function _maxDeadlineExtension() internal view returns (uint256) {
        return _getProposalDeadlineExtensionsStorage()._maxDeadlineExtension;
    }

    function setMaxDeadlineExtension(uint256 newMaxDeadlineExtension) public {
        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();
        emit IProposalDeadlineExtensions.MaxDeadlineExtensionUpdate($._maxDeadlineExtension, newMaxDeadlineExtension);
        $._maxDeadlineExtension = newMaxDeadlineExtension.toUint64();
    }

    function _baseDeadlineExtension() internal view returns (uint256) {
        return _getProposalDeadlineExtensionsStorage()._baseDeadlineExtension;
    }

    function setBaseDeadlineExtension(uint256 newBaseDeadlineExtension) public {
        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();
        emit IProposalDeadlineExtensions.BaseDeadlineExtensionUpdate($._baseDeadlineExtension, newBaseDeadlineExtension);
        $._baseDeadlineExtension = newBaseDeadlineExtension.toUint64();
    }

    function _extensionDecayPeriod() internal view returns (uint256) {
        return _getProposalDeadlineExtensionsStorage()._decayPeriod;
    }

    function setExtensionDecayPeriod(uint256 newDecayPeriod) public {
        if (newDecayPeriod == 0) {
            revert IProposalDeadlineExtensions.GovernorExtensionDecayPeriodCannotBeZero();
        }

        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();
        emit IProposalDeadlineExtensions.ExtensionDecayPeriodUpdate($._decayPeriod, newDecayPeriod);
        $._decayPeriod = newDecayPeriod.toUint64();
    }

    function _extensionPercentDecay() internal view returns (uint256) {
        return _getProposalDeadlineExtensionsStorage()._percentDecay;
    }

    function setExtensionPercentDecay(uint256 newPercentDecay) public {
        if (newPercentDecay < MIN_PERCENT_DECAY || newPercentDecay > MAX_PERCENT_DECAY) {
            revert IProposalDeadlineExtensions.GovernorExtensionPercentDecayOutOfRange(
                MIN_PERCENT_DECAY, MAX_PERCENT_DECAY
            );
        }

        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();
        emit IProposalDeadlineExtensions.ExtensionPercentDecayUpdate($._percentDecay, newPercentDecay);
        // SafeCast unnecessary here as long as the MAX_PERCENT_DECAY is less than type(uint8).max
        $._percentDecay = uint8(newPercentDecay);
    }

    function processDeadlineExtensionOnVote(uint256 proposalId, uint256 voteWeight) public {
        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();

        // Copy the packed settings to stack for reads
        bytes32 packedSettingsSlot;
        assembly {
            packedSettingsSlot := sload($.slot)
        }

        // Grab the max deadline extension
        uint256 maxDeadlineExtension_;
        assembly {
            maxDeadlineExtension_ := and(MASK_UINT64, packedSettingsSlot)
        }

        // If maxDeadlineExtension is set to zero, then no deadline updates needed, skip the rest to save gas
        if (maxDeadlineExtension_ == 0) {
            return;
        }

        // Retrieve the existing deadline data for this proposal
        DeadlineData memory dd = $._deadlineDatas[proposalId];

        // If extension is already maxxed out, no further updates needed
        if (dd.extendedBy >= maxDeadlineExtension_) {
            return;
        }

        // If quorum wasn't reached last time, check again
        if (!dd.quorumReached) {
            dd.quorumReached = ProposalVotingLogicV1._quorumReached(proposalId);
            // If quorum still hasn't been reached, skip the calculation and return
            if (!dd.quorumReached) {
                return;
            }
        }

        // Initialize the rest of the struct if it hasn't been initialized yet
        if (dd.originalDeadline == 0) {
            // Assumes safe conversion, uint64 should be large enough for either block numbers or timestamps in seconds
            dd.originalDeadline = uint64(_originalProposalDeadline(proposalId));
            dd.currentDeadline = dd.originalDeadline;
        }

        // Initialize extendMultiple
        uint256 extendMultiple;

        uint256 currentTimepoint = GovernorBaseLogicV1._clock();

        /**
         * Save gas with unchecked, this is ok because all overflow/underflow checks are performed in the code here:
         * - If the currentDeadline wasn't larger than the currentTimepoint, the vote wouldn't be allowed to be cast
         * - Only subtracts the originalDeadline from the currentTimepoint if the currentTimepoint is larger
         * - Only subtracts the distanceFromDeadline from the extend amount if extend amount is larger
         *
         * Additionally, this block scopes the storage variables to avoid "stack too deep" errors
         */
        unchecked {
            // Read rest of settings from the packed slot
            uint256 baseDeadlineExtension_;
            uint256 decayPeriod_;
            uint256 percentDecay_;
            assembly {
                baseDeadlineExtension_ := and(MASK_UINT64, shr(64, packedSettingsSlot))
                decayPeriod_ := and(MASK_UINT64, shr(128, packedSettingsSlot))
                percentDecay_ := and(MASK_UINT8, shr(192, packedSettingsSlot))
            }

            // Get the current distance from the deadline
            uint256 distanceFromDeadline = dd.currentDeadline - currentTimepoint;

            // We can return if we are outside the range of the base extension amount (since it gets subtracted out)
            if (baseDeadlineExtension_ < distanceFromDeadline) {
                return;
            }

            // Extend amount decays past the original deadline
            if (currentTimepoint > dd.originalDeadline) {
                uint256 periodsElapsed = (currentTimepoint - dd.originalDeadline) / decayPeriod_;
                uint256 extend = (baseDeadlineExtension_ * (MAX_PERCENT_DECAY - percentDecay_) ** periodsElapsed)
                    / (100 ** periodsElapsed);
                // Check again for distance from the deadline. If extend is too small, just return.
                if (extend < distanceFromDeadline) {
                    return;
                }
                extendMultiple = extend - distanceFromDeadline;
            } else {
                extendMultiple = baseDeadlineExtension_ - distanceFromDeadline;
            }
        }

        // We include a FRACTION_MULTIPLE that we later divide back out to circumvent integer division issues
        uint256 deadlineExtension = extendMultiple
            * Math.min(
                FRACTION_MULTIPLE_MAX,
                // Add 1 to avoid divide by zero error
                (voteWeight * FRACTION_MULTIPLE / (ProposalVotingLogicV1._voteMargin(proposalId) + 1))
            ) / FRACTION_MULTIPLE;

        // Only need to extend and emit if the extension is greater than 0
        if (deadlineExtension > 0) {
            // Update extended by with the extension value, maxing out at the max deadline extension
            dd.extendedBy += SafeCast.toUint64(Math.max(deadlineExtension, maxDeadlineExtension_));
            // Update the new deadline
            dd.currentDeadline = dd.originalDeadline + dd.extendedBy;

            // Set in storage
            $._deadlineDatas[proposalId] = dd;

            // Emit the event
            emit IProposalDeadlineExtensions.ProposalDeadlineExtended(proposalId, dd.currentDeadline);
        }
    }
}
