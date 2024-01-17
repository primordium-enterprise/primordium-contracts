// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest, ERC165Contract, console2} from "test/Base.t.sol";
import {ProposalTestUtils} from "test/helpers/ProposalTestUtils.sol";
import {IGovernorBase} from "src/governor/interfaces/IGovernorBase.sol";
import {IGovernorBase} from "src/governor/interfaces/IGovernorBase.sol";
import {IProposalVoting} from "src/governor/interfaces/IProposalVoting.sol";
import {IProposalVoting} from "src/governor/interfaces/IProposalVoting.sol";
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
        // Mint tokens to create total supply
        _mintSharesForVoting(users.gwart, GOVERNOR.governorBaseInit.governanceThresholdBps * TOKEN.sharesTokenInit.maxSupply / MAX_BPS);
    }

    function _proposeAndExecuteUpdate(
        bytes memory data,
        string memory signature,
        bytes memory expectedExecutionError
    )
        internal
    {
        uint256 proposalId = _proposePassAndQueueOnlyGovernanceUpdate(data, signature);
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
        uint256 proposalId = _proposePassAndQueueOnlyGovernanceUpdate(data, signature);
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
        governor.setProposalThresholdBps(GOVERNOR.governorBaseInit.proposalThresholdBps);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setProposalThresholdBps(GOVERNOR.governorBaseInit.proposalThresholdBps);
    }

    function test_Fuzz_SetProposalThresholdBps(uint16 newProposalThresholdBps) public {
        bytes memory data = abi.encodeCall(governor.setProposalThresholdBps, newProposalThresholdBps);
        string memory signature = "setProposalThresholdBps(uint256)";
        uint256 proposalId = _proposePassAndQueueOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedProposalThresholdBps = GOVERNOR.governorBaseInit.proposalThresholdBps;
        if (newProposalThresholdBps > MAX_BPS) {
            err = abi.encodeWithSelector(BasisPoints.BPSValueTooLarge.selector, newProposalThresholdBps);
        } else {
            expectedProposalThresholdBps = newProposalThresholdBps;
            vm.expectEmit(false, false, false, true, address(governor));
            emit IGovernorBase.ProposalThresholdBPSUpdate(GOVERNOR.governorBaseInit.proposalThresholdBps, newProposalThresholdBps);
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedProposalThresholdBps, governor.proposalThresholdBps());
        assertEq(token.totalSupply() * expectedProposalThresholdBps / MAX_BPS, governor.proposalThreshold());
    }

    function test_Revert_SetVotingDelay_OnlyGovernance() public {
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setVotingDelay(GOVERNOR.governorBaseInit.votingDelay);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setVotingDelay(GOVERNOR.governorBaseInit.votingDelay);
    }

    function test_Fuzz_SetVotingDelay(uint32 newVotingDelay) public {
        uint256 min = governor.MIN_VOTING_DELAY();
        uint256 max = governor.MAX_VOTING_DELAY();

        bytes memory data = abi.encodeCall(governor.setVotingDelay, newVotingDelay);
        string memory signature = "setVotingDelay(uint256)";
        uint256 proposalId = _proposePassAndQueueOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedVotingDelay = GOVERNOR.governorBaseInit.votingDelay;
        if (newVotingDelay < min || newVotingDelay > max) {
            err = abi.encodeWithSelector(GovernorSettingsRanges.GovernorVotingDelayOutOfRange.selector, min, max);
        } else {
            expectedVotingDelay = newVotingDelay;
            vm.expectEmit(false, false, false, true);
            emit IGovernorBase.VotingDelayUpdate(GOVERNOR.governorBaseInit.votingDelay, newVotingDelay);
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedVotingDelay, governor.votingDelay());
    }

    function test_Revert_SetVotingPeriod_OnlyGovernance() public {
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setVotingPeriod(GOVERNOR.governorBaseInit.votingPeriod);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setVotingPeriod(GOVERNOR.governorBaseInit.votingPeriod);
    }

    function test_Fuzz_SetVotingPeriod(uint32 newVotingPeriod) public {
        uint256 min = governor.MIN_VOTING_PERIOD();
        uint256 max = governor.MAX_VOTING_PERIOD();

        bytes memory data = abi.encodeCall(governor.setVotingPeriod, newVotingPeriod);
        string memory signature = "setVotingPeriod(uint256)";
        uint256 proposalId = _proposePassAndQueueOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedVotingPeriod = GOVERNOR.governorBaseInit.votingPeriod;
        if (newVotingPeriod < min || newVotingPeriod > max) {
            err = abi.encodeWithSelector(GovernorSettingsRanges.GovernorVotingPeriodOutOfRange.selector, min, max);
        } else {
            expectedVotingPeriod = newVotingPeriod;
            vm.expectEmit(false, false, false, true);
            emit IGovernorBase.VotingPeriodUpdate(GOVERNOR.governorBaseInit.votingPeriod, newVotingPeriod);
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedVotingPeriod, governor.votingPeriod());
    }

    function test_Revert_SetProposalGracePeriod_OnlyGovernance() public {
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setProposalGracePeriod(GOVERNOR.governorBaseInit.gracePeriod);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setProposalGracePeriod(GOVERNOR.governorBaseInit.gracePeriod);
    }

    function test_Fuzz_SetProposalGracePeriod(uint48 newProposalGracePeriod) public {
        uint256 min = governor.MIN_PROPOSAL_GRACE_PERIOD();
        uint256 max = governor.MAX_PROPOSAL_GRACE_PERIOD();

        bytes memory data = abi.encodeCall(governor.setProposalGracePeriod, newProposalGracePeriod);
        string memory signature = "setProposalGracePeriod(uint256)";
        uint256 proposalId = _proposePassAndQueueOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedProposalGracePeriod = GOVERNOR.governorBaseInit.gracePeriod;
        if (newProposalGracePeriod < min || newProposalGracePeriod > max) {
            err =
                abi.encodeWithSelector(GovernorSettingsRanges.GovernorProposalGracePeriodOutOfRange.selector, min, max);
        } else {
            expectedProposalGracePeriod = newProposalGracePeriod;
            vm.expectEmit(false, false, false, true);
            emit IGovernorBase.ProposalGracePeriodUpdate(GOVERNOR.governorBaseInit.gracePeriod, newProposalGracePeriod);
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedProposalGracePeriod, governor.proposalGracePeriod());
    }

    /**
     * ProposalVoting
     */
    function test_Revert_SetPercentMajority_OnlyGovernance() public {
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setPercentMajority(GOVERNOR.proposalVotingInit.percentMajority);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setPercentMajority(GOVERNOR.proposalVotingInit.percentMajority);
    }

    function test_Fuzz_SetPercentMajority(uint8 newPercentMajority) public {
        uint256 min = 50;
        uint256 max = 66;

        bytes memory data = abi.encodeCall(governor.setPercentMajority, newPercentMajority);
        string memory signature = "setPercentMajority(uint256)";
        uint256 proposalId = _proposePassAndQueueOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedPercentMajority = GOVERNOR.proposalVotingInit.percentMajority;
        if (newPercentMajority < min || newPercentMajority > max) {
            err = abi.encodeWithSelector(IProposalVoting.GovernorPercentMajorityOutOfRange.selector, min, max);
        } else {
            expectedPercentMajority = newPercentMajority;
            vm.expectEmit(false, false, false, true);
            emit IProposalVoting.PercentMajorityUpdate(GOVERNOR.proposalVotingInit.percentMajority, newPercentMajority);
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedPercentMajority, governor.percentMajority(governor.clock()));
    }

    function test_Revert_SetQuorumBps_OnlyGovernance() public {
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setQuorumBps(GOVERNOR.proposalVotingInit.quorumBps);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setQuorumBps(GOVERNOR.proposalVotingInit.quorumBps);
    }

    function test_Fuzz_SetQuorumBps(uint16 newQuorumBps) public {
        bytes memory data = abi.encodeCall(governor.setQuorumBps, newQuorumBps);
        string memory signature = "setQuorumBps(uint256)";
        uint256 proposalId = _proposePassAndQueueOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedQuorumBps = GOVERNOR.proposalVotingInit.quorumBps;
        if (newQuorumBps > MAX_BPS) {
            err = abi.encodeWithSelector(BasisPoints.BPSValueTooLarge.selector, newQuorumBps);
        } else {
            expectedQuorumBps = newQuorumBps;
            vm.expectEmit(false, false, false, true);
            emit IProposalVoting.QuorumBpsUpdate(GOVERNOR.proposalVotingInit.quorumBps, newQuorumBps);
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedQuorumBps, governor.quorumBps(governor.clock()));
        // Roll forward 1 to check quorum (or will be a future lookup error on the token)
        vm.roll(governor.clock() + 1);
        assertEq(token.totalSupply() * expectedQuorumBps / MAX_BPS, governor.quorum(governor.clock() - 1));

        console2.log(token.totalSupply());
    }

    /**
     * ProposalDeadlineExtensions
     */
    function test_Revert_SetMaxDeadlineExtension_OnlyGovernance() public {
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setMaxDeadlineExtension(GOVERNOR.proposalVotingInit.maxDeadlineExtension);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setMaxDeadlineExtension(GOVERNOR.proposalVotingInit.maxDeadlineExtension);
    }

    function test_Fuzz_SetMaxDeadlineExtension(uint32 newMaxDeadlineExtension) public {
        uint256 max = governor.ABSOLUTE_MAX_DEADLINE_EXTENSION();

        bytes memory data = abi.encodeCall(governor.setMaxDeadlineExtension, newMaxDeadlineExtension);
        string memory signature = "setMaxDeadlineExtension(uint256)";
        uint256 proposalId = _proposePassAndQueueOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedMaxDeadlineExtension = GOVERNOR.proposalVotingInit.maxDeadlineExtension;
        if (newMaxDeadlineExtension > max) {
            err = abi.encodeWithSelector(GovernorSettingsRanges.GovernorMaxDeadlineExtensionTooLarge.selector, max);
        } else {
            expectedMaxDeadlineExtension = newMaxDeadlineExtension;
            vm.expectEmit(false, false, false, true);
            emit IProposalVoting.MaxDeadlineExtensionUpdate(
                GOVERNOR.proposalVotingInit.maxDeadlineExtension, newMaxDeadlineExtension
            );
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedMaxDeadlineExtension, governor.maxDeadlineExtension());
    }

    function test_Revert_SetBaseDeadlineExtension_OnlyGovernance() public {
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setBaseDeadlineExtension(GOVERNOR.proposalVotingInit.baseDeadlineExtension);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setBaseDeadlineExtension(GOVERNOR.proposalVotingInit.baseDeadlineExtension);
    }

    function test_Fuzz_SetBaseDeadlineExtension(uint32 newBaseDeadlineExtension) public {
        uint256 min = governor.MIN_BASE_DEADLINE_EXTENSION();
        uint256 max = governor.MAX_BASE_DEADLINE_EXTENSION();

        bytes memory data = abi.encodeCall(governor.setBaseDeadlineExtension, newBaseDeadlineExtension);
        string memory signature = "setBaseDeadlineExtension(uint256)";
        uint256 proposalId = _proposePassAndQueueOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedBaseDeadlineExtension = GOVERNOR.proposalVotingInit.baseDeadlineExtension;
        if (newBaseDeadlineExtension < min || newBaseDeadlineExtension > max) {
            err = abi.encodeWithSelector(
                GovernorSettingsRanges.GovernorBaseDeadlineExtensionOutOfRange.selector, min, max
            );
        } else {
            expectedBaseDeadlineExtension = newBaseDeadlineExtension;
            vm.expectEmit(false, false, false, true);
            emit IProposalVoting.BaseDeadlineExtensionUpdate(
                GOVERNOR.proposalVotingInit.baseDeadlineExtension, newBaseDeadlineExtension
            );
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedBaseDeadlineExtension, governor.baseDeadlineExtension());
    }

    function test_Revert_SetExtensionDecayPeriod_OnlyGovernance() public {
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setExtensionDecayPeriod(GOVERNOR.proposalVotingInit.decayPeriod);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setExtensionDecayPeriod(GOVERNOR.proposalVotingInit.decayPeriod);
    }

    function test_Fuzz_SetExtensionDecayPeriod(uint32 newExtensionDecayPeriod) public {
        uint256 min = governor.MIN_EXTENSION_DECAY_PERIOD();
        uint256 max = governor.MAX_EXTENSION_DECAY_PERIOD();

        bytes memory data = abi.encodeCall(governor.setExtensionDecayPeriod, newExtensionDecayPeriod);
        string memory signature = "setExtensionDecayPeriod(uint256)";
        uint256 proposalId = _proposePassAndQueueOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedExtensionDecayPeriod = GOVERNOR.proposalVotingInit.decayPeriod;
        if (newExtensionDecayPeriod < min || newExtensionDecayPeriod > max) {
            err =
                abi.encodeWithSelector(GovernorSettingsRanges.GovernorExtensionDecayPeriodOutOfRange.selector, min, max);
        } else {
            expectedExtensionDecayPeriod = newExtensionDecayPeriod;
            vm.expectEmit(false, false, false, true);
            emit IProposalVoting.ExtensionDecayPeriodUpdate(
                GOVERNOR.proposalVotingInit.decayPeriod, newExtensionDecayPeriod
            );
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedExtensionDecayPeriod, governor.extensionDecayPeriod());
    }

    function test_Revert_SetExtensionPercentDecay_OnlyGovernance() public {
        vm.prank(address(executor));
        vm.expectRevert(DoubleEndedQueue.QueueEmpty.selector);
        governor.setExtensionPercentDecay(GOVERNOR.proposalVotingInit.percentDecay);

        vm.prank(users.maliciousUser);
        vm.expectRevert(IGovernorBase.OnlyGovernance.selector);
        governor.setExtensionPercentDecay(GOVERNOR.proposalVotingInit.percentDecay);
    }

    function test_Fuzz_SetExtensionPercentDecay(uint32 newExtensionPercentDecay) public {
        uint256 min = 1;
        uint256 max = 100;

        bytes memory data = abi.encodeCall(governor.setExtensionPercentDecay, newExtensionPercentDecay);
        string memory signature = "setExtensionPercentDecay(uint256)";
        uint256 proposalId = _proposePassAndQueueOnlyGovernanceUpdate(data, signature);

        bytes memory err;
        uint256 expectedExtensionPercentDecay = GOVERNOR.proposalVotingInit.percentDecay;
        if (newExtensionPercentDecay < min || newExtensionPercentDecay > max) {
            err = abi.encodeWithSelector(
                IProposalVoting.GovernorExtensionPercentDecayOutOfRange.selector, min, max
            );
        } else {
            expectedExtensionPercentDecay = newExtensionPercentDecay;
            vm.expectEmit(false, false, false, true);
            emit IProposalVoting.ExtensionPercentDecayUpdate(
                GOVERNOR.proposalVotingInit.percentDecay, newExtensionPercentDecay
            );
        }

        _executeOnlyGovernanceUpdate(proposalId, data, err);
        assertEq(expectedExtensionPercentDecay, governor.extensionPercentDecay());
    }
}
