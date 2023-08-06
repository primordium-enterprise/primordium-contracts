// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "./governance/executor/Executor.sol";
import "./governance/governor/Governor.sol";
import "./governance/governor/extensions/GovernorVotesQuorumBps.sol";
import "./governance/governor/extensions/GovernorSettings.sol";
import "./governance/governor/extensions/GovernorCountingSimple.sol";
import "./governance/governor/extensions/GovernorProposalDeadlineExtensions.sol";

contract GovernorV1 is
    Governor,
    GovernorVotes,
    GovernorVotesQuorumBps,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorProposalDeadlineExtensions
{

    constructor(
        Executor executor_,
        VotesProvisioner token_,
        uint256 governanceThreshold_,
        uint256 quorumBps_,
        uint256 proposalThresholdBps_,
        uint256 votingDelay_,
        uint256 votingPeriod_
    )
        Governor(executor_, token_, governanceThreshold_)
        GovernorVotesQuorumBps(quorumBps_)
        GovernorSettings(proposalThresholdBps_, votingDelay_, votingPeriod_)
    { }

    function name() public pure override returns (string memory) {
        return "Primordium Governor";
    }

    // Overriding here is unnecessary, but included for readability
    function version() public pure override returns (string memory) {
        return "1";
    }

    function proposalDeadline(
        uint256 proposalId
    ) public view override(Governor, GovernorProposalDeadlineExtensions) returns (uint256) {
        return super.proposalDeadline(proposalId);
    }

    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal override(Governor, GovernorProposalDeadlineExtensions) returns (uint256) {
        return super._castVote(proposalId, account, support, reason, params);
    }

}
