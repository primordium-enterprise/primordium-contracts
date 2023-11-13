// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

// import "./executor/Executor.sol";
// import "./governor/Governor.sol";
// import "./governor/extensions/GovernorVotesQuorumBps.sol";
// import "./governor/extensions/GovernorSettings.sol";
// import "./governor/extensions/GovernorCountingPercentMajority.sol";
// import "./governor/extensions/GovernorProposalDeadlineExtensions.sol";

// contract GovernorV1 is
//     Governor,
//     GovernorVotes,
//     GovernorVotesQuorumBps,
//     GovernorSettings,
//     GovernorCountingPercentMajority,
//     GovernorProposalDeadlineExtensions
// {

//     constructor(
//         Executor timelockAvatar_,
//         SharesManager token_,
//         uint256 governanceThreshold_,
//         uint256 quorumBps_,
//         uint256 proposalThresholdBps_,
//         uint256 votingDelay_,
//         uint256 votingPeriod_,
//         uint256 percentMajority_
//     )
//         Governor(timelockAvatar_, token_, governanceThreshold_)
//         GovernorVotesQuorumBps(quorumBps_)
//         GovernorSettings(proposalThresholdBps_, votingDelay_, votingPeriod_)
//         GovernorCountingPercentMajority(percentMajority_)
//     { }

//     function name() public pure override returns (string memory) {
//         return "Primordium Governor";
//     }

//     // Overriding here is unnecessary, but included for readability
//     function version() public pure override returns (string memory) {
//         return "1";
//     }

//     function proposalDeadline(
//         uint256 proposalId
//     ) public view override(Governor, GovernorProposalDeadlineExtensions) returns (uint256) {
//         return super.proposalDeadline(proposalId);
//     }

//     function _castVote(
//         uint256 proposalId,
//         address account,
//         uint8 support,
//         string memory reason,
//         bytes memory params
//     ) internal override(Governor, GovernorProposalDeadlineExtensions) returns (uint256) {
//         return super._castVote(proposalId, account, support, reason, params);
//     }

// }
