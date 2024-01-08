// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest, ERC165Contract} from "test/Base.t.sol";
import {ProposalTestUtils} from "test/helpers/ProposalTestUtils.sol";
import {IGovernorBase} from "src/governor/interfaces/IGovernorBase.sol";
import {IProposals} from "src/governor/interfaces/IProposals.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";
import {IAvatar} from "src/executor/interfaces/IAvatar.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {ERC165Verifier} from "src/libraries/ERC165Verifier.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {GovernorSettingsRanges} from "src/governor/helpers/GovernorSettingsRanges.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AvatarInterfaceMock is ERC165Contract {
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAvatar).interfaceId || super.supportsInterface(interfaceId);
    }
}

contract GovernorSettingsTest is BaseTest, ProposalTestUtils {
    function setUp() public virtual override {
        super.setUp();
        governor.harnessFoundGovernor();
    }

    function _proposeAndExecuteUpdate(
        bytes memory data,
        string memory signature,
        bytes memory expectedExecutionError
    )
        internal
    {
        uint256 proposalId = _proposeQueueAndPassOnlyGovernanceUpdate(data, signature);
        _executeOnlyGovernanceUpdate(proposalId, data, expectedExecutionError);
    }

    function _proposeAndExecuteAddressUpdate(
        address parameter,
        string memory signature,
        bytes memory expectedExecutionError
    )
        internal
    {
        bytes4 selector = bytes4(keccak256(abi.encodePacked(signature)));
        bytes memory data = abi.encodeWithSelector(selector, parameter);
        _proposeAndExecuteUpdate(data, signature, expectedExecutionError);
    }

    function _proposeAndExecuteUint256Update(
        uint256 parameter,
        string memory signature,
        bytes memory expectedExecutionError
    )
        internal
    {
        bytes4 selector = bytes4(keccak256(abi.encodePacked(signature)));
        bytes memory data = abi.encodeWithSelector(selector, parameter);
        _proposeAndExecuteUpdate(data, signature, expectedExecutionError);
    }

    /**
     * GovernorBase
     */
    function test_SetExecutor() public {
        address newExecutor = erc165Address;
        string memory signature = "setExecutor(address)";

        // Only governance can update
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setExecutor(newExecutor);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setExecutor(newExecutor);

        // Invalid IAvatar interface support
        _proposeAndExecuteAddressUpdate(
            newExecutor,
            signature,
            abi.encodeWithSelector(
                ERC165Verifier.InvalidERC165InterfaceSupport.selector, newExecutor, type(IAvatar).interfaceId
            )
        );

        // Invalid ITimelockAvatar interface support
        newExecutor = address(new AvatarInterfaceMock());
        _proposeAndExecuteAddressUpdate(
            newExecutor,
            signature,
            abi.encodeWithSelector(
                ERC165Verifier.InvalidERC165InterfaceSupport.selector, newExecutor, type(ITimelockAvatar).interfaceId
            )
        );

        // No address(0)
        newExecutor = address(0);
        _proposeAndExecuteAddressUpdate(
            newExecutor,
            signature,
            abi.encodeWithSelector(IGovernorBase.GovernorInvalidExecutorAddress.selector, newExecutor)
        );

        // No address(governor)
        newExecutor = address(governor);
        _proposeAndExecuteAddressUpdate(
            newExecutor,
            signature,
            abi.encodeWithSelector(IGovernorBase.GovernorInvalidExecutorAddress.selector, newExecutor)
        );

        // Valid address
        newExecutor = address(new ERC1967Proxy(executorImpl, ""));
        bytes memory data = abi.encodeCall(governor.setExecutor, newExecutor);
        uint256 proposalId = _proposeQueueAndPassOnlyGovernanceUpdate(data, signature);
        vm.expectEmit(false, false, false, true, address(governor));
        emit IGovernorBase.ExecutorUpdate(address(executor), newExecutor);
        _executeOnlyGovernanceUpdate(proposalId, data, "");
        assertEq(newExecutor, address(governor.executor()));
    }

    /**
     * Proposals
     */

    function test_Revert_SetProposalThresholdBps_OnlyGovernance() public {
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setProposalThresholdBps(GOVERNOR.proposalThresholdBps);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setProposalThresholdBps(GOVERNOR.proposalThresholdBps);
    }

    function test_Fuzz_SetProposalThresholdBps(uint16 newProposalThresholdBps) public {
        // Mint tokens to create total supply
        _mintSharesForVoting(users.gwart, GOVERNOR.governanceThresholdBps * TOKEN.maxSupply / MAX_BPS);

        bytes memory data = abi.encodeCall(governor.setProposalThresholdBps, newProposalThresholdBps);
        string memory signature = "setProposalThresholdBps(uint256)";
        uint256 proposalId = _proposeQueueAndPassOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedProposalThresholdBps = GOVERNOR.proposalThresholdBps;
        if (newProposalThresholdBps > MAX_BPS) {
            err = abi.encodeWithSelector(BasisPoints.BPSValueTooLarge.selector, newProposalThresholdBps);
        } else {
            expectedProposalThresholdBps = newProposalThresholdBps;
            vm.expectEmit(false, false, false, true, address(governor));
            emit IProposals.ProposalThresholdBPSUpdate(GOVERNOR.proposalThresholdBps, newProposalThresholdBps);
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedProposalThresholdBps, governor.proposalThresholdBps());
        assertEq(token.totalSupply() * expectedProposalThresholdBps / MAX_BPS, governor.proposalThreshold());
    }

    function test_Revert_SetVotingDelay_OnlyGovernance() public {
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setVotingDelay(GOVERNOR.votingDelay);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setVotingDelay(GOVERNOR.votingDelay);
    }

    function test_Fuzz_SetVotingDelay(uint32 newVotingDelay) public {
        uint256 min = governor.MIN_VOTING_DELAY();
        uint256 max = governor.MAX_VOTING_DELAY();

        bytes memory data = abi.encodeCall(governor.setVotingDelay, newVotingDelay);
        string memory signature = "setVotingDelay(uint256)";
        uint256 proposalId = _proposeQueueAndPassOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedVotingDelay = GOVERNOR.votingDelay;
        if (newVotingDelay < min || newVotingDelay > max) {
            err = abi.encodeWithSelector(GovernorSettingsRanges.GovernorVotingDelayOutOfRange.selector, min, max);
        } else {
            expectedVotingDelay = newVotingDelay;
            vm.expectEmit(false, false, false, true);
            emit IProposals.VotingDelayUpdate(GOVERNOR.votingDelay, newVotingDelay);
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedVotingDelay, governor.votingDelay());
    }

    function test_Revert_SetVotingPeriod_OnlyGovernance() public {
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setVotingPeriod(GOVERNOR.votingPeriod);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setVotingPeriod(GOVERNOR.votingPeriod);
    }

    function test_Fuzz_SetVotingPeriod(uint32 newVotingPeriod) public {
        uint256 min = governor.MIN_VOTING_PERIOD();
        uint256 max = governor.MAX_VOTING_PERIOD();

        bytes memory data = abi.encodeCall(governor.setVotingPeriod, newVotingPeriod);
        string memory signature = "setVotingPeriod(uint256)";
        uint256 proposalId = _proposeQueueAndPassOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedVotingPeriod = GOVERNOR.votingPeriod;
        if (newVotingPeriod < min || newVotingPeriod > max) {
            err = abi.encodeWithSelector(GovernorSettingsRanges.GovernorVotingPeriodOutOfRange.selector, min, max);
        } else {
            expectedVotingPeriod = newVotingPeriod;
            vm.expectEmit(false, false, false, true);
            emit IProposals.VotingPeriodUpdate(GOVERNOR.votingPeriod, newVotingPeriod);
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedVotingPeriod, governor.votingPeriod());
    }

    function test_Revert_SetProposalGracePeriod_OnlyGovernance() public {
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setProposalGracePeriod(GOVERNOR.gracePeriod);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setProposalGracePeriod(GOVERNOR.gracePeriod);
    }

    function test_Fuzz_SetProposalGracePeriod(uint48 newProposalGracePeriod) public {
        uint256 min = governor.MIN_PROPOSAL_GRACE_PERIOD();
        uint256 max = governor.MAX_PROPOSAL_GRACE_PERIOD();

        bytes memory data = abi.encodeCall(governor.setProposalGracePeriod, newProposalGracePeriod);
        string memory signature = "setProposalGracePeriod(uint256)";
        uint256 proposalId = _proposeQueueAndPassOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedProposalGracePeriod = GOVERNOR.gracePeriod;
        if (newProposalGracePeriod < min || newProposalGracePeriod > max) {
            err = abi.encodeWithSelector(GovernorSettingsRanges.GovernorProposalGracePeriodOutOfRange.selector, min, max);
        } else {
            expectedProposalGracePeriod = newProposalGracePeriod;
            vm.expectEmit(false, false, false, true);
            emit IProposals.ProposalGracePeriodUpdate(GOVERNOR.gracePeriod, newProposalGracePeriod);
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedProposalGracePeriod, governor.proposalGracePeriod());
    }
}
