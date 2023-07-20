// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../Governor.sol";

/**
 * @dev A module to extend the deadline for controversial votes. The extension amount for each vote is dynamically
 * computed, taking several parameters into account, such as:
 * - If the vote is particularly influential to the outcome of the vote, this will weight towards a longer deadline
 * extension.
 * - If the vote takes place close to the current deadline, this will also weight towards a longer deadline extension to
 * give other DAO members time to react.
 * - The deadline extension amount decays exponentially as the proposal moves further past its original deadline to
 * prevent infinite delays and/or DoS for the outcome.
 *
 * This is designed as a dynamic protection mechanism against "Vote Sniping," where the outcome of a low activity
 * proposal is flipped at the last minute by a heavy swing vote, without leaving time for additional voters to react.
 *
 * Through the governance process, the DAO can set the baseExtension, the decayPeriod, and the percentDecay values.
 *
 */
abstract contract GovernorProposalDeadlineExtensions is Governor {

    /**
     * @notice The maximum base extension period for extending votes.
     */
    uint64 public immutable MAX_BASE_EXTENSION;
    uint64 private _baseExtension;
    uint64 private _decayPeriod;
    uint8 private _percentDecay;
    // uint8 private _maxVoteWeightMultiple;
    // uint120 private __gap_unused0;

    constructor() {
        MAX_BASE_EXTENSION = clock() == block.number ?
            21_600 : // About 3 days at 12sec/block
            3 days;
    }

}