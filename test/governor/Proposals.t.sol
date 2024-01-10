// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest, console2} from "test/Base.t.sol";
import {ProposalTestUtils} from "test/helpers/ProposalTestUtils.sol";
import {BalanceSharesTestUtils} from "test/helpers/BalanceSharesTestUtils.sol";
import {IProposals} from "src/governor/interfaces/IProposals.sol";
import {IProposalVoting} from "src/governor/interfaces/IProposalVoting.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract ProposalsTest is BaseTest, ProposalTestUtils, BalanceSharesTestUtils {
    function setUp() public virtual override {
        super.setUp();
        _setupDefaultBalanceShares();
        governor.harnessFoundGovernor();
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

    function test_ProposerRole() public {
        // Proposer can propose, even though they do not meet the proposalThreshold()
        assertEq(true, governor.hasRole(governor.PROPOSER_ROLE(), users.proposer));
        assertTrue(governor.proposalThreshold() > governor.getVotes(users.proposer, token.clock() - 1));
        _mockPropose(users.proposer);

        // Take away the role
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = governor.PROPOSER_ROLE();
        address[] memory accounts = new address[](1);
        accounts[0] = users.proposer;
        _runOnlyGovernanceUpdate(
            users.gwart, abi.encodeCall(governor.revokeRoles, (roles, accounts)), "revokeRoles(bytes32[],address[])"
        );

        // Now no proposal allowed
        assertEq(false, governor.hasRole(governor.PROPOSER_ROLE(), users.proposer));
        assertTrue(governor.proposalThreshold() > governor.getVotes(users.proposer, token.clock() - 1));
        vm.expectRevert(abi.encodeWithSelector(IProposals.GovernorUnauthorizedSender.selector, users.proposer));
        _mockPropose(users.proposer);
    }

    function test_RevertWhen_ProposalActionSignatureInvalid() public {
        address target = address(governor);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(governor.foundGovernor, 1);
        string memory signature = "invalidFoundGovernor(uint256)";

        vm.expectRevert(abi.encodeWithSelector(IProposals.GovernorInvalidActionSignature.selector, 0));
        _propose(users.proposer, target, value, data, signature, "failed signature");

        // Valid signature will allow proposal to work
        signature = "foundGovernor(uint256)";
        uint256 expectedProposalId = _expectedProposalId();
        uint256 proposalId = _propose(users.proposer, target, value, data, signature, "valid signature");
        assertEq(expectedProposalId, proposalId);
    }

    function test_ProposalActionsHash() public {
        address[] memory targets = new address[](1);
        targets[0] = address(erc20Mock);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(erc20Mock.transfer, (address(0x01), 100));
        string[] memory signatures = new string[](1);
        signatures[0] = "transfer(address,uint256)";

        uint256 expectedProposalId = _expectedProposalId();
        bytes32 expectedActionsHash = keccak256(abi.encode(targets, values, calldatas));
        vm.prank(users.proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, signatures, "transfer erc20");
        assertEq(expectedProposalId, proposalId);
        assertEq(expectedActionsHash, governor.proposalActionsHash(proposalId));
    }

    function test_ProposalProposer() public {
        uint256 proposalId = _mockPropose(users.proposer);
        assertEq(users.proposer, governor.proposalProposer(proposalId));
    }

    function test_ProposalSnapshot() public {
        // Assert delay is valid
        uint256 currentBlock = governor.clock();
        uint256 proposalId = _mockPropose(users.proposer);
        assertEq(GOVERNOR.votingDelay, governor.votingDelay(), "Unexpected initial votingDelay() on governor");
        assertEq(currentBlock + GOVERNOR.votingDelay, governor.proposalSnapshot(proposalId));

        // Change delay, then assert for new proposal
        uint256 newVotingDelay = GOVERNOR.votingDelay * 2;
        _updateGovernorSetting(users.proposer, "setVotingDelay(uint256)", newVotingDelay);
        assertEq(newVotingDelay, governor.votingDelay());
        currentBlock = governor.clock();
        proposalId = _mockPropose(users.proposer);
        assertEq(currentBlock + newVotingDelay, governor.proposalSnapshot(proposalId));
    }

    function test_ProposalDeadline() public {
        assertEq(GOVERNOR.votingDelay, governor.votingDelay(), "Unexpected initial governor.votingDelay()");
        assertEq(GOVERNOR.votingPeriod, governor.votingPeriod(), "Unexpected initial governor.votingPeriod()");

        // Assert period is valid
        uint256 currentBlock = governor.clock();
        uint256 proposalId = _mockPropose(users.proposer);
        assertEq(currentBlock + GOVERNOR.votingDelay + GOVERNOR.votingPeriod, governor.proposalDeadline(proposalId));

        // Change period, then assert for new proposal
        uint256 newVotingPeriod = GOVERNOR.votingPeriod * 2;
        _updateGovernorSetting(users.proposer, "setVotingPeriod(uint256)", newVotingPeriod);
        assertEq(newVotingPeriod, governor.votingPeriod());
        currentBlock = governor.clock();
        proposalId = _mockPropose(users.proposer);
        assertEq(currentBlock + GOVERNOR.votingDelay + newVotingPeriod, governor.proposalDeadline(proposalId));
    }

    function test_ProposalOpNonce() public {
        // Use an arbitrary proposal update
        address target = address(governor);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(governor.setProposalThresholdBps, GOVERNOR.proposalThresholdBps);
        string memory signature = "setProposalThresholdBps(uint256)";

        uint256 proposalId = _propose(users.proposer, target, value, data, signature, "arbitrary proposal");
        assertEq(0, governor.proposalOpNonce(proposalId));

        uint256 expectedOpNonce = executor.getNextOperationNonce();
        _passAndQueueProposal(proposalId, users.proposer, target, value, data);

        assertEq(expectedOpNonce, governor.proposalOpNonce(proposalId));

        // Pass a second proposal to ensure it works for the next one as well
        proposalId = _propose(users.proposer, target, value, data, signature, "arbitrary proposal 2");
        assertEq(0, governor.proposalOpNonce(proposalId));

        expectedOpNonce = executor.getNextOperationNonce();
        _passAndQueueProposal(proposalId, users.proposer, target, value, data);

        assertEq(expectedOpNonce, governor.proposalOpNonce(proposalId));
    }

    function test_ProposalEta() public {
        // Use an arbitrary proposal update
        address target = address(governor);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(governor.setProposalThresholdBps, GOVERNOR.proposalThresholdBps);
        string memory signature = "setProposalThresholdBps(uint256)";

        uint256 proposalId = _propose(users.proposer, target, value, data, signature, "arbitrary proposal");
        assertEq(0, governor.proposalEta(proposalId));

        uint256 expectedEta = block.timestamp + executor.getMinDelay();
        _passAndQueueProposal(proposalId, users.proposer, target, value, data);
        assertEq(expectedEta, governor.proposalEta(proposalId));
    }

    function test_CancelProposal_Proposer() public {
        uint256 shares = GOVERNOR.proposalThresholdBps * TOKEN.maxSupply / MAX_BPS;
        _mintSharesForVoting(users.gwart, shares);

        address target = address(0x01);
        uint256 value = 0;

        uint256 proposalId = _propose(users.gwart, target, value, "", "", "testing cancel proposal");
        vm.roll(governor.proposalSnapshot(proposalId));

        // Expect revert if not pending anymore
        vm.expectRevert(
            abi.encodeWithSelector(
                IProposals.GovernorUnexpectedProposalState.selector,
                proposalId,
                IProposals.ProposalState.Active,
                bytes32(1 << uint8(IProposals.ProposalState.Pending))
            )
        );
        vm.prank(users.gwart);
        _cancel(proposalId, target, value, "");

        // Proposer can cancel during pending tho
        vm.roll(governor.proposalSnapshot(proposalId) - 1);
        vm.prank(users.gwart);
        vm.expectEmit(true, false, false, false, address(governor));
        emit IProposals.ProposalCanceled(proposalId);
        _cancel(proposalId, target, value, "");
        assertEq(uint8(IProposals.ProposalState.Canceled), uint8(governor.state(proposalId)));
    }

    function test_CancelProposal_CancelerRole() public {
        address target = users.gwart;
        uint256 value = 0;

        uint256 proposalId = _propose(users.proposer, target, value, "", "", "testing cancel proposal");

        // Expect revert for unauthorized canceler
        vm.expectRevert(abi.encodeWithSelector(IProposals.GovernorUnauthorizedSender.selector, users.maliciousUser));
        vm.prank(users.maliciousUser);
        _cancel(proposalId, target, value, "");

        // Expect revert for proposer after pending period
        vm.roll(governor.proposalSnapshot(proposalId));
        vm.expectRevert(
            abi.encodeWithSelector(
                IProposals.GovernorUnexpectedProposalState.selector,
                proposalId,
                IProposals.ProposalState.Active,
                bytes32(1 << uint8(IProposals.ProposalState.Pending))
            )
        );
        vm.prank(users.proposer);
        _cancel(proposalId, target, value, "");

        uint256 snapshot = vm.snapshot();

        // Allowed states are anything but Canceled, Expired, Executed
        // forgefmt: disable-next-item
        bytes32 allowedStates = bytes32(
            (2 ** (uint8(type(IProposals.ProposalState).max) + 1)) - 1 ^
            (1 << uint8(IProposals.ProposalState.Canceled)) ^
            (1 << uint8(IProposals.ProposalState.Expired)) ^
            (1 << uint8(IProposals.ProposalState.Executed))
        );

        // Allow one with "canceler" role to cancel
        assertEq(true, governor.hasRole(governor.CANCELER_ROLE(), users.canceler));
        vm.expectEmit(true, false, false, false, address(governor));
        emit IProposals.ProposalCanceled(proposalId);
        vm.prank(users.canceler);
        _cancel(proposalId, target, value, "");
        assertEq(uint8(IProposals.ProposalState.Canceled), uint8(governor.state(proposalId)));

        // Don't allow cancellation for already cancelled proposal
        vm.expectRevert(
            abi.encodeWithSelector(
                IProposals.GovernorUnexpectedProposalState.selector,
                proposalId,
                IProposals.ProposalState.Canceled,
                allowedStates
            )
        );
        vm.prank(users.canceler);
        _cancel(proposalId, target, value, "");

        // Revert back to pre-cancellation for following tests
        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        // Don't allow cancellation for an expired proposal
        _mintSharesForVoting(users.gwart, GOVERNOR.quorumBps * TOKEN.maxSupply / MAX_BPS);
        vm.prank(users.gwart);
        governor.castVote(proposalId, uint8(IProposalVoting.VoteType.For));

        vm.roll(governor.proposalDeadline(proposalId) + governor.proposalGracePeriod() + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IProposals.GovernorUnexpectedProposalState.selector,
                proposalId,
                IProposals.ProposalState.Expired,
                allowedStates
            )
        );
        vm.prank(users.canceler);
        _cancel(proposalId, target, value, "");

        // Don't allow cancellation for an executed proposal
        vm.roll(governor.proposalDeadline(proposalId) + 1);
        _queue(proposalId, target, value, "");
        vm.warp(governor.proposalEta(proposalId));
        _execute(proposalId, target, value, "");

        vm.expectRevert(
            abi.encodeWithSelector(
                IProposals.GovernorUnexpectedProposalState.selector,
                proposalId,
                IProposals.ProposalState.Executed,
                allowedStates
            )
        );
        vm.prank(users.canceler);
        _cancel(proposalId, target, value, "");
    }
}
