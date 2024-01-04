// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract VotesTest is BaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_Delegate(address account, uint16 amount, address delegatee1, address delegatee2) public {
        vm.assume(account != address(0));

        vm.prank(token.owner());
        token.mint(account, amount);

        // No delegation = no votes
        assertEq(0, token.getVotes(account));
        assertEq(0, token.getVotes(delegatee1));
        assertEq(0, token.getVotes(delegatee2));

       uint256 expectedVotes = delegatee1 == address(0) ? 0 : amount;

        // Delegate to delegatee1
        vm.prank(account);
        vm.expectEmit(true, true, true, true, address(token));
        emit IVotes.DelegateChanged(account, address(0), delegatee1);
        if (amount > 0) {
            if (delegatee1 != address(0)) {
                vm.expectEmit(true, false, false, true, address(token));
                emit IVotes.DelegateVotesChanged(delegatee1, 0, amount);
            }
        }
        token.delegate(delegatee1);

        assertEq(0, token.getVotes(account));
        assertEq(expectedVotes, token.getVotes(delegatee1));

        // Change delegates to delegatee2
        expectedVotes = delegatee2 == address(0) ? 0 : amount;

        vm.prank(account);
        vm.expectEmit(true, true, true, true, address(token));
        emit IVotes.DelegateChanged(account, delegatee1, delegatee2);
        if (delegatee1 != delegatee2 && amount > 0) {
            if (delegatee1 != address(0)) {
                vm.expectEmit(true, false, false, true, address(token));
                emit IVotes.DelegateVotesChanged(delegatee1, amount, 0);
            }
            if (delegatee2 != address(0)) {
                vm.expectEmit(true, false, false, true, address(token));
                emit IVotes.DelegateVotesChanged(delegatee2, 0, amount);
            }
        }
        token.delegate(delegatee2);

        assertEq(0, token.getVotes(delegatee1));
        assertEq(expectedVotes, token.getVotes(delegatee2));
    }
}