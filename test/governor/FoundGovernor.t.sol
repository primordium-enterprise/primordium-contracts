// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest, console2} from "test/Base.t.sol";
import {ProposalTestUtils} from "test/helpers/ProposalTestUtils.sol";
import {BalanceSharesTestUtils} from "test/helpers/BalanceSharesTestUtils.sol";
import {IGovernorBase} from "src/governor/interfaces/IGovernorBase.sol";
import {IProposals} from "src/governor/interfaces/IProposals.sol";
import {ExecutorBase} from "src/executor/base/ExecutorBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract FoundGovernorTest is BaseTest, ProposalTestUtils, BalanceSharesTestUtils {
    uint256 internal constant MAX_BPS = 10_000;

    function setUp() public virtual override {
        super.setUp();
    }

    function _proposeFoundGovernor(
        address proposer,
        uint256 expectedProposalId
    )
        internal
        returns (uint256 proposalId)
    {
        proposalId = _propose(
            proposer,
            address(governor),
            0,
            abi.encodeCall(governor.foundGovernor, expectedProposalId),
            "foundGovernor(uint256)",
            "Let's get this party started."
        );
    }

    function _queueFoundGovernor(uint256 proposalId) internal returns (uint256) {
        return _queue(proposalId, address(governor), 0, abi.encodeCall(governor.foundGovernor, proposalId));
    }

    function _executeFoundGovernor(uint256 proposalId) internal returns (uint256) {
        return _execute(proposalId, address(governor), 0, abi.encodeCall(governor.foundGovernor, proposalId));
    }

    function _setupGwartToFound(uint256 amount) internal {
        _mintSharesForVoting(users.gwart, amount);
        vm.roll(block.number + 1); // Roll forward to ensure votes count
    }

    function _setupGwartToFound() internal {
        _setupGwartToFound(governor.governanceFoundingVoteThreshold());
    }

    function test_GovernanceCanBeginAt() public {
        assertEq(governor.governanceCanBeginAt(), GOVERNOR.governanceCanBeginAt);
    }

    function test_RevertBefore_GovernanceCanBeginAt() public {
        uint256 expectedProposalId = _expectedProposalId();

        vm.warp(block.timestamp - 1);
        vm.expectRevert(
            abi.encodeWithSelector(IGovernorBase.GovernorCannotBeFoundedYet.selector, GOVERNOR.governanceCanBeginAt)
        );
        _proposeFoundGovernor(users.gwart, expectedProposalId);
    }

    function test_GovernanceFoundingVoteThreshold() public {
        uint256 expectedThreshold = Math.mulDiv(TOKEN.maxSupply, GOVERNOR.governanceThresholdBps, 10_000);
        uint256 threshold = governor.governanceFoundingVoteThreshold();
        assertEq(threshold, expectedThreshold);
    }

    function test_RevertWhen_GovernanceFoundingVoteThresholdNotMet() public {
        uint256 expectedProposalId = _expectedProposalId();

        // Miss the threshold by one
        uint256 threshold = governor.governanceFoundingVoteThreshold();
        uint256 amount = threshold - 1;

        // Mint for voting (delegates gwart shares to gwart)
        _setupGwartToFound(amount);

        bytes memory thresholdNotMetError =
            abi.encodeWithSelector(IGovernorBase.GovernorFoundingVoteThresholdNotMet.selector, threshold, amount);

        vm.expectRevert(thresholdNotMetError);
        _proposeFoundGovernor(users.gwart, expectedProposalId);

        // Mint the missing shares to gwart
        _mintShares(users.gwart, threshold - amount);
        vm.roll(block.number + 1); // Roll forward to make sure shares count

        // Now proposal should be allowed
        uint256 proposalId = _proposeFoundGovernor(users.gwart, expectedProposalId);
        assertEq(proposalId, expectedProposalId);

        // Vote to succeed
        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(users.gwart);
        governor.castVote(proposalId, 1);

        // Gwart burns a share, dipping below the proposal threshold again
        vm.prank(users.gwart);
        token.withdraw(threshold - amount, new IERC20[](0));

        // Queue for execution
        vm.roll(governor.proposalDeadline(proposalId) + 1);
        _queueFoundGovernor(proposalId);

        // Execution should fail due to the proposal threshold not begin met at the proposal deadline
        vm.warp(governor.proposalEta(proposalId));
        vm.expectRevert(abi.encodeWithSelector(ExecutorBase.CallReverted.selector, thresholdNotMetError));
        _executeFoundGovernor(proposalId);

        assertEq(false, governor.isFounded());
    }

    function test_RevertWhen_FoundGovernorActionIsInvalid() public {
        uint256 expectedProposalId = _expectedProposalId();

        _setupGwartToFound();

        // Correct parameters for founding
        address correctTarget = address(governor);
        bytes memory correctData = abi.encodeCall(governor.foundGovernor, expectedProposalId);
        uint256 value = 0;
        string memory correctSignature = "foundGovernor(uint256)";
        string memory description = "lego";

        // Invalid target
        address invalidTarget = address(0x01);
        vm.expectRevert(IProposals.GovernorFoundingActionRequired.selector);
        _propose(users.gwart, invalidTarget, value, correctData, correctSignature, description);

        // Invalid data length
        bytes memory invalidData = abi.encodePacked(governor.foundGovernor.selector, hex"1234");
        vm.expectRevert(IProposals.GovernorFoundingActionRequired.selector);
        _propose(users.gwart, correctTarget, value, invalidData, correctSignature, description);

        // Invalid function selector
        invalidData = abi.encodeCall(governor.proposalDeadline, expectedProposalId);
        vm.expectRevert(IProposals.GovernorFoundingActionRequired.selector);
        _propose(users.gwart, correctTarget, value, invalidData, "proposalDeadline(uint256)", description);

        // Invalid proposalId
        uint256 invalidProposalId = expectedProposalId + 1;
        invalidData = abi.encodeCall(governor.foundGovernor, invalidProposalId);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernorBase.GovernorInvalidFoundingProposalID.selector, expectedProposalId, invalidProposalId
            )
        );
        _propose(users.gwart, correctTarget, value, invalidData, correctSignature, description);

        // Invalid signature
        string memory invalidSignature = "foundGovernor()";
        vm.expectRevert(abi.encodeWithSelector(IProposals.GovernorInvalidActionSignature.selector, 0));
        _propose(users.gwart, correctTarget, value, correctData, invalidSignature, description);
    }

    function test_FoundGovernor() public {
        // With balance shares (not enabled by default)
        _setupDefaultBalanceShares(false);

        uint256 expectedProposalId = _expectedProposalId();

        // Gwart deposits full threshold amount of shares
        address proposer = users.gwart;
        uint256 shares = governor.governanceFoundingVoteThreshold();
        uint256 depositAmount = shares * ONBOARDER.quoteAmount / ONBOARDER.mintAmount;
        _giveQuoteAsset(proposer, depositAmount);

        vm.prank(proposer);
        onboarder.deposit{value: depositAmount}(depositAmount);
        assertEq(shares, token.balanceOf(proposer));

        vm.prank(proposer);
        token.delegate(proposer);

        vm.roll(block.number + 1);
        uint256 proposalId = _proposeFoundGovernor(proposer, expectedProposalId);

        assertEq(proposalId, expectedProposalId, "proposalId not equal to expectedProposalId");
        assertEq(proposalId, governor.proposalCount(), "proposalId not equal to proposalCount()");
        assertEq(depositAmount, address(executor).balance, "invalid pre-execution treasury balance");
        assertEq(false, governor.isFounded(), "governor should not be founded pre-execution");

        // Pass the proposal through
        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(proposer);
        governor.castVote(proposalId, 1);

        vm.roll(governor.proposalDeadline(proposalId) + 1);
        _queueFoundGovernor(proposalId);

        // Execute
        vm.warp(governor.proposalEta(proposalId));
        vm.expectEmit(true, false, false, false, address(governor));
        emit IGovernorBase.GovernorFounded(proposalId);
        _executeFoundGovernor(proposalId);

        assertEq(true, governor.isFounded(), "governor should be founded post-execution");
        assertEq(
            depositAmount - _expectedTreasuryBalanceShareAllocation(DEPOSITS_ID, address(0), depositAmount),
            address(executor).balance,
            "invalid treasury balance post-execution (accounting for deposit balance shares)"
        );
    }
}
