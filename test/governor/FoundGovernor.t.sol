// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {ProposalTestUtils} from "test/helpers/ProposalTestUtils.sol";

contract FoundGovernorTest is BaseTest, ProposalTestUtils {
    function setUp() public virtual override {
        super.setUp();
    }

    function _proposeFoundGovernor(address proposer)
        internal
        returns (uint256 proposalId, uint256 expectedProposalId)
    {
        expectedProposalId = governor.proposalCount() + 1;
        proposalId = _propose(
            proposer,
            address(governor),
            0,
            abi.encodeCall(governor.foundGovernor, expectedProposalId),
            "foundGovernor(uint256)",
            "Let's get this party started."
        );
    }


}
