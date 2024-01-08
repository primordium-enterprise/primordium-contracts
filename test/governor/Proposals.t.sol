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

    function _mockPropose(address proposer) internal returns (uint256 proposalId) {
        string memory signature = "testSignature()";
        return _propose(
            proposer,
            address(0x01),
            0,
            abi.encodePacked(bytes4(keccak256(abi.encodePacked(signature)))),
            signature,
            "mock"
        );
    }

    function test_ValidateProposerDescription() public {
        address proposer = users.proposer;

        address target = address(0x01);
        uint256 value = 0;
        string memory signature = "test()";
        bytes memory data = abi.encodePacked(bytes4(keccak256(bytes(signature))));
        string memory description = string.concat("proposal description #proposer=", Strings.toHexString(proposer));

        // Revert if proposer does not propose
        vm.expectRevert(IProposals.GovernorRestrictedProposer.selector);
        _propose(users.maliciousUser, target, value, data, signature, description);

        // Success if proposer does propose
        _propose(proposer, target, value, data, signature, description);
    }

    function test_ProposalThreshold() public {
        uint256 gwartShares = GOVERNOR.governanceThresholdBps * TOKEN.maxSupply / MAX_BPS;
        _mintSharesForVoting(users.gwart, gwartShares);

        // The amount of shares, when added to gwartShares, will meet the proposalThreshold
        uint256 thresholdShares =
            gwartShares * GOVERNOR.proposalThresholdBps / (MAX_BPS - GOVERNOR.proposalThresholdBps);

        uint256 bobShares = thresholdShares - 1;
        uint256 aliceShares = thresholdShares - bobShares;

        _mintSharesForVoting(users.bob, bobShares);
        _mintSharesForVoting(users.alice, aliceShares);
        vm.roll(token.clock() + 1);

        // By default, bob should not have enough shares to submit a proposal
        vm.expectRevert(abi.encodeWithSelector(IProposals.GovernorUnauthorizedSender.selector, users.bob));
        _mockPropose(users.bob);

        // But if alice delegates to bob as well, the threshold should be met
        vm.prank(users.alice);
        token.delegate(users.bob);
        vm.roll(token.clock() + 1);

        _mockPropose(users.bob);

        // Set proposalThresholdBps to zero, now anyone should be able to propose
        _updateGovernorSetting(users.gwart, "setProposalThresholdBps(uint256)", 0);
        vm.roll(token.clock() + 1);

        _mockPropose(users.maliciousUser);
    }
}
