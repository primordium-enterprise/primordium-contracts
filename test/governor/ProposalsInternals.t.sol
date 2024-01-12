// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PRBTest} from "@prb/test/PRBTest.sol";
import {GovernorBaseLogicV1} from "src/governor/base/logic/GovernorBaseLogicV1.sol";
import {GovernorBase} from "src/governor/base/GovernorBase.sol";
import {IGovernorBase} from "src/governor/interfaces/IGovernorBase.sol";

contract ProposalsHarness is GovernorBase {
    function validateCalldataSignatures(bytes[] calldata calldatas, string[] memory signatures) public pure {
        GovernorBaseLogicV1._validateCalldataSignatures(calldatas, signatures);
    }

    function aFunctionSignature(uint256 a) public pure {}
}

contract ProposalsInternalsTest is PRBTest {
    ProposalsHarness proposals;

    constructor() {
        proposals = new ProposalsHarness();
    }

    /// forge-config: default.fuzz.runs = 512
    /// forge-config: lite.fuzz.runs = 512
    function test_Fuzz_HashProposalActions(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
    {
        assertEq(
            proposals.hashProposalActions(targets, values, calldatas), keccak256(abi.encode(targets, values, calldatas))
        );
    }

    function test_Fuzz_ValidateCalldataSignatures(string[] memory signatures) public view {
        // Test fuzz values
        bytes[] memory calldatas = new bytes[](signatures.length);
        for (uint256 i = 0; i < signatures.length; i++) {
            if (bytes(signatures[i]).length > 0) {
                bytes memory data = abi.encodeWithSignature(signatures[i]);
                calldatas[i] = data;
            }
        }
        proposals.validateCalldataSignatures(calldatas, signatures);
    }

    function test_Revert_InvalidCalldataSignatures() public {
        // Test specific signature
        bytes[] memory calldatas = new bytes[](2);
        string[] memory signatures = new string[](2);
        signatures[0] = "aFunctionSignature(uint256)";
        calldatas[0] = abi.encodeWithSignature(signatures[0], (1));
        signatures[1] = "aFunctionSignature(uint256)";
        calldatas[1] = abi.encodeWithSignature(signatures[0], (1));
        proposals.validateCalldataSignatures(calldatas, signatures);

        // Test signature is incorrect
        signatures[1] = "incorrectSignature(uint256)";
        vm.expectRevert(abi.encodeWithSelector(IGovernorBase.GovernorInvalidActionSignature.selector, (1)));
        proposals.validateCalldataSignatures(calldatas, signatures);

        // Test missing signature
        signatures[0] = "";
        vm.expectRevert(abi.encodeWithSelector(IGovernorBase.GovernorInvalidActionSignature.selector, (0)));
        proposals.validateCalldataSignatures(calldatas, signatures);
    }
}
