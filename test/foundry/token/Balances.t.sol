// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./TestAccountsSetup.t.sol";

contract Balances is Test, TestAccountsSetup {

    function test_Transfer() public {
        uint256 a1BalanceBefore = token.balanceOf(a1);
        uint256 a2BalanceBefore = token.balanceOf(a2);
        vm.prank(a1);
        bool success = token.transfer(a2, a1BalanceBefore);
        assertEq(success, true);
        assertEq(token.balanceOf(a1), 0);
        assertEq(token.balanceOf(a2), a1BalanceBefore + a2BalanceBefore);
    }

    function test_PastBalances() public {
        uint256 b1 = 1;
        uint256 b2 = 2;
        uint256 b3 = 3;
        uint256 a1Balance1 = token.balanceOf(a1);
        uint256 a2Balance1 = token.balanceOf(a2);
        uint256 transferAmount = a1Balance1 / 2;
        vm.roll(b2);

        vm.prank(a1);
        token.transfer(a2, a1Balance1 / 2);

        assertEq(token.balanceOf(a1), a1Balance1 - transferAmount);
        assertEq(token.balanceOf(a2), a2Balance1 + transferAmount);
        assertEq(token.getPastBalanceOf(a1, b1), a1Balance1);
        assertEq(token.getPastBalanceOf(a2, b1), a2Balance1);

        vm.expectRevert(bytes("ERC20Checkpoints: future lookup"));
        token.getPastBalanceOf(a1, block.number);
        vm.roll(b3);
        assertEq(token.getPastBalanceOf(a1, b2), a1Balance1 - transferAmount);
    }

    function test_PastSupply() public {
        uint256 a1Balance1 = token.balanceOf(a1);
        uint256 supply1 = token.totalSupply();
        uint256 expectedSupply1 = _expectedTokenBalance(amntTotal);
        assertEq(supply1, expectedSupply1);

        vm.roll(2);

        vm.prank(a1);
        token.withdraw(a1Balance1 / 2);

        uint256 supply2 = token.totalSupply();
        uint256 expectedSupply2 = supply1 - (a1Balance1 / 2);
        assertEq(token.balanceOf(a1), a1Balance1 / 2);
        assertEq(supply2, expectedSupply2);

        vm.roll(3);

        token.depositFor{value: amnt1}(a1);

        uint256 expectedSupply3 = supply2 + _expectedTokenBalance(amnt1);
        assertEq(token.balanceOf(a1), a1Balance1 * 3 / 2);
        assertEq(token.totalSupply(), expectedSupply3);

        vm.expectRevert("ERC20Checkpoints: future lookup");
        token.getPastTotalSupply(block.number);
        assertEq(token.getPastTotalSupply(block.number - 1), supply2);
        assertEq(token.getPastTotalSupply(block.number - 2), supply1);
    }

    function testFail_TransferTooMuch() public {
        uint256 a1Balance = token.balanceOf(a1);
        vm.prank(a1);
        token.transfer(a2, a1Balance + 1);
    }

}