// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {SelectorChecker} from "contracts/libraries/SelectorChecker.sol";

interface IVerifySignaturesTest {
    function add(uint256) external;

    function subtract(uint256) external;

    function veryLongFunctionSignature(uint256, address, uint256) external;
}

contract Verifier {
    function verifySolidity(bytes[] calldata calldatas, string[] calldata signatures) external pure returns (bool) {
        for (uint256 i = 0; i < signatures.length;) {
            if (calldatas[i].length > 0) {
                if (bytes4(calldatas[i]) != bytes4(keccak256(bytes(signatures[i])))) revert();
            } else {
                // Revert if signature is provided with no calldata
                if (bytes(signatures[i]).length > 0) {
                    revert();
                }
            }
            unchecked {
                ++i;
            }
        }

        return true;
    }

    function verifyYul(bytes[] calldata calldatas, string[] calldata signatures) external pure returns (bool) {
        SelectorChecker.verifySelectors(calldatas, signatures);
        return true;
    }
}

contract SelectorCheckerTest is Test {
    Verifier verifier = new Verifier();

    function _createTestData() internal view returns (bytes[] memory calldatas, string[] memory signatures) {
        calldatas = new bytes[](5);
        signatures = new string[](5);

        calldatas[0] = abi.encodeCall(IVerifySignaturesTest.add, (1));
        signatures[0] = "add(uint256)";

        calldatas[1] = abi.encodeCall(IVerifySignaturesTest.subtract, (1));
        signatures[1] = "subtract(uint256)";

        calldatas[2] = abi.encodeCall(IVerifySignaturesTest.veryLongFunctionSignature, (1, address(this), 1));
        signatures[2] = "veryLongFunctionSignature(uint256,address,uint256)";

        // Manually skip calldatas[3] to ensure an empty calldata works properly

        calldatas[4] = abi.encodeCall(IVerifySignaturesTest.veryLongFunctionSignature, (1, address(this), 20));
        signatures[4] = "veryLongFunctionSignature(uint256,address,uint256)";
    }

    function test_VerifySolidity() public view {
        (bytes[] memory calldatas, string[] memory signatures) = _createTestData();
        verifier.verifySolidity(calldatas, signatures);
    }

    function test_VerifyYul() public view {
        (bytes[] memory calldatas, string[] memory signatures) = _createTestData();
        verifier.verifyYul(calldatas, signatures);
    }

    function test_VerifyYulRevertsShortString() public {
        bytes[] memory calldatas = new bytes[](1);
        string[] memory signatures = new string[](1);
        calldatas[0] = abi.encodeCall(IVerifySignaturesTest.add, (1));
        signatures[0] = "badSignature(uint256)";
        vm.expectRevert(abi.encodeWithSelector(SelectorChecker.InvalidActionSignature.selector, 0));
        verifier.verifyYul(calldatas, signatures);
    }

    function test_VerifyYulRevertsLongString() public {
        bytes[] memory calldatas = new bytes[](1);
        string[] memory signatures = new string[](1);
        calldatas[0] = abi.encodeCall(IVerifySignaturesTest.veryLongFunctionSignature, (1, address(this), 1));
        signatures[0] = "badVeryLongFunctionSignature(uint256,address,uint256)";
        vm.expectRevert(abi.encodeWithSelector(SelectorChecker.InvalidActionSignature.selector, 0));
        verifier.verifyYul(calldatas, signatures);
    }

    function test_VerifyYulRevertsEmptyCalldata() public {
        bytes[] memory calldatas = new bytes[](1);
        string[] memory signatures = new string[](1);
        // No calldata, but signature provided, should revert
        signatures[0] = "signatureShouldNotBeHereWithoutCalldata(uint256)";
        vm.expectRevert(abi.encodeWithSelector(SelectorChecker.InvalidActionSignature.selector, 0));
        verifier.verifyYul(calldatas, signatures);
    }
}
