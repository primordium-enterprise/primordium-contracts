// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./TestAccountsSetup.t.sol";

contract Delegation is Test, TestAccountsSetup {

    function test_Votes() public {
        // Should not be delegated by default
        assertEq(
            token.getVotes(a1),
            0
        );
        // But after delegation, should be equal to the expected values
        vm.prank(a1);
        token.delegate(a1);
        assertEq(
            token.getVotes(a1),
            amnt1 / 10
        );
    }

}