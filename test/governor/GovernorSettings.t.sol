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

    function _performUpdate(bytes memory data, string memory signature, bytes memory expectedExecutionError) internal {
        uint256 proposalId = _proposeQueueAndPassOnlyGovernanceUpdate(data, signature);
        _executeOnlyGovernanceUpdate(proposalId, data, expectedExecutionError);
    }

    function _performAddressUpdate(address parameter, string memory signature, bytes memory expectedExecutionError) internal {
        bytes4 selector = bytes4(keccak256(abi.encodePacked(signature)));
        bytes memory data = abi.encodeWithSelector(selector, parameter);
        _performUpdate(data, signature, expectedExecutionError);
    }

    function _performUint256Update(uint256 parameter, string memory signature, bytes memory expectedExecutionError) internal {
        bytes4 selector = bytes4(keccak256(abi.encodePacked(signature)));
        bytes memory data = abi.encodeWithSelector(selector, parameter);
        _performUpdate(data, signature, expectedExecutionError);
    }

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
        _performAddressUpdate(newExecutor, signature, abi.encodeWithSelector(
            ERC165Verifier.InvalidERC165InterfaceSupport.selector, newExecutor, type(IAvatar).interfaceId
        ));

        // Invalid ITimelockAvatar interface support
        newExecutor = address(new AvatarInterfaceMock());
        _performAddressUpdate(newExecutor, signature, abi.encodeWithSelector(
                ERC165Verifier.InvalidERC165InterfaceSupport.selector, newExecutor, type(ITimelockAvatar).interfaceId
            ));

        // No address(0)
        newExecutor = address(0);
        _performAddressUpdate(newExecutor, signature, abi.encodeWithSelector(IGovernorBase.GovernorInvalidExecutorAddress.selector, newExecutor));

        // No address(governor)
        newExecutor = address(governor);
        _performAddressUpdate(newExecutor, signature, abi.encodeWithSelector(IGovernorBase.GovernorInvalidExecutorAddress.selector, newExecutor));

        // Valid address
        newExecutor = address(new ERC1967Proxy(executorImpl, ""));
        _performAddressUpdate(newExecutor, signature, "");
        assertEq(newExecutor, address(governor.executor()));
    }

    function test_SetProposalThresholdBps() public {
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

        uint256 proposalId = _proposeQueueAndPassOnlyGovernanceUpdate(data, signature);
        vm.expectEmit(false, false, false, true, address(governor));
        emit IProposals.ProposalThresholdBPSUpdate(GOVERNOR.proposalThresholdBps, newProposalThresholdBps);
        _executeOnlyGovernanceUpdate(proposalId, data, "");

        assertEq(newProposalThresholdBps, governor.proposalThresholdBps());

        // Out of range BPS
        newProposalThresholdBps = MAX_BPS + 1;
        data = abi.encodeCall(governor.setProposalThresholdBps, newProposalThresholdBps);

        proposalId = _proposeQueueAndPassOnlyGovernanceUpdate(data, signature);
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
