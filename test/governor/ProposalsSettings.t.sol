// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {ProposalTestUtils} from "test/helpers/ProposalTestUtils.sol";
import {IGovernorBase} from "src/governor/interfaces/IGovernorBase.sol";
import {IProposals} from "src/governor/interfaces/IProposals.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {GovernorSettingsRanges} from "src/governor/helpers/GovernorSettingsRanges.sol";

contract ProposalsSettingsTest is BaseTest, ProposalTestUtils {
    function setUp() public virtual override {
        super.setUp();
        governor.harnessFoundGovernor();
    }

    function _proposeUpdateSetting(
        address proposer,
        bytes memory data,
        string memory signature
    )
        internal
        returns (uint256 proposalId)
    {
        proposalId = _propose(proposer, address(governor), 0, data, signature, "update setting");
    }

    function test_ProposalThresholdBps() public {
        uint256 newProposalThresholdBps = GOVERNOR.proposalThresholdBps / 10;

        // Only governance can update
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setProposalThresholdBps(newProposalThresholdBps);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setProposalThresholdBps(newProposalThresholdBps);

        // Successful execution
        bytes memory data = abi.encodeCall(governor.setProposalThresholdBps, newProposalThresholdBps);
        string memory signature = "setProposalThresholdBps(uint256)";

        uint256 proposalId = _proposeOnlyGovernanceUpdate(data, signature);
        _queueAndPassOnlyGovernanceUpdate(proposalId, data);
        vm.expectEmit(false, false, false, true, address(governor));
        emit IProposals.ProposalThresholdBPSUpdate(GOVERNOR.proposalThresholdBps, newProposalThresholdBps);
        _executeOnlyGovernanceUpdate(proposalId, data, "");

        // Out of range BPS
        newProposalThresholdBps = MAX_BPS + 1;
        data = abi.encodeCall(governor.setProposalThresholdBps, newProposalThresholdBps);

        proposalId = _proposeOnlyGovernanceUpdate(data, signature);
        _queueAndPassOnlyGovernanceUpdate(proposalId, data);
        _executeOnlyGovernanceUpdate(
            proposalId,
            data,
            abi.encodeWithSelector(
                GovernorSettingsRanges.GovernorProposalThresholdBpsTooLarge.selector,
                newProposalThresholdBps,
                governor.MAX_PROPOSAL_THRESHOLD_BPS()
            )
        );
    }
}
