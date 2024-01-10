// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest, console2} from "test/Base.t.sol";
import {TimelockAvatarTestUtils} from "test/helpers/TimelockAvatarTestUtils.sol";
import {Enum} from "src/common/Enum.sol";

contract TimelockAvatarTest is BaseTest, TimelockAvatarTestUtils {
    function setUp() public virtual override(BaseTest, TimelockAvatarTestUtils) {
        super.setUp();
    }

    function test_Fuzz_HashOperation(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    )
        public
    {
        // Operation must not be greater than type(Enum.Operation).max, or error will occur
        operation = operation % (uint8(type(Enum.Operation).max) + 1);
        assertEq(
            executor.hashOperation(to, value, data, Enum.Operation(operation)),
            keccak256(abi.encode(to, value, data, operation))
        );
    }

}
