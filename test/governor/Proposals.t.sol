// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PRBTest} from "@prb/test/PRBTest.sol";
import {Proposals} from "src/governor/base/Proposals.sol";

contract ProposalsHarness is Proposals {

    function _quorumReached(
        uint256 proposalId
    ) internal view virtual override returns (bool) {}

    function _voteSucceeded(
        uint256 proposalId
    ) internal view virtual override returns (bool) {}
}

contract ProposalsTest is PRBTest {

    ProposalsHarness proposals;

    constructor() {
        proposals = new ProposalsHarness();
    }

    /// forge-config: default.fuzz.runs = 1048
    function testHashProposalActions(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) public {
        assertEq(
            proposals.hashProposalActions(targets, values, calldatas),
            keccak256(abi.encode(targets, values, calldatas))
        );
    }
}