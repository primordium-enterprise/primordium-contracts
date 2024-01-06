// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest, console2} from "test/Base.t.sol";
import {ProposalTestUtils} from "test/helpers/ProposalTestUtils.sol";
import {BalanceSharesTestUtils} from "test/helpers/BalanceSharesTestUtils.sol";
import {IProposals} from "src/governor/interfaces/IProposals.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract ProposalsTest is BaseTest, ProposalTestUtils, BalanceSharesTestUtils {
    // uint256 defaultGwartShares = 100;

    function setUp() public virtual override {
        super.setUp();
        _setupDefaultBalanceShares();
        governor.harnessFoundGovernor();
        // _mintSharesForVoting(users.gwart, defaultGwartShares);
    }

    function test_ValidateProposerDescription() public {
        address proposer = users.proposer;

        address target = address(0x01);
        uint256 value = 0;
        string memory signature = "test()";
        bytes memory data = abi.encodePacked(bytes4(keccak256(bytes(signature))));
        string memory description =
            string.concat("proposal description #proposer=", Strings.toHexString(proposer));

        // Revert if proposer does not propose
        vm.expectRevert(IProposals.GovernorRestrictedProposer.selector);
        _propose(users.maliciousUser, target, value, data, signature, description);

        // Success if proposer does propose
        _propose(proposer, target, value, data, signature, description);
    }
}
