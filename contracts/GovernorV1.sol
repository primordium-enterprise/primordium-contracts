// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "./governance/executor/Executor.sol";
import "./governance/governor/Governor.sol";
import "./governance/governor/extensions/GovernorVotes.sol";
import "./governance/governor/extensions/GovernorSettings.sol";
import "./governance/governor/extensions/_PlaceholderFunctions.sol";

contract GovernorV1 is Governor, GovernorVotes, GovernorSettings, _PlaceholderFunctions {

    constructor(
        Executor executor,
        VotesProvisioner token,
        uint256 initialVotingDelay,
        uint256 initialVotingPeriod,
        uint256 initialProposalThreshold
    )
        Governor(executor, token)
        GovernorSettings(initialVotingDelay, initialVotingPeriod, initialProposalThreshold)
    { }

    function name() public pure override returns (string memory) {
        return "Primordium Governor";
    }

    // Overriding here is unnecessary, but included for readability
    function version() public pure override returns (string memory) {
        return "1";
    }

}
