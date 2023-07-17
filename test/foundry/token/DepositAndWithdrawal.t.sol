// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../GovernanceSetup.t.sol";

contract DepositAndWithdrawal is Test, GovernanceSetup {

    address a1 = address(0x01);
    address a2 = address(0x02);
    address a3 = address(0x03);
    address a4 = address(0x04);

    uint256 amnt1 = 1 ether;
    uint256 amnt2 = 2 ether;
    uint256 amnt3 = 3 ether;

    constructor() {
        vm.deal(a1, amnt1);
        vm.deal(a2, amnt2);
    }

    function setUp() public {
        // Test various deposit functions
        vm.prank(a1);
        token.deposit{value: amnt1}();
        vm.prank(a2);
        token.depositFor{value: amnt2}(a2);
        token.depositFor{value: amnt3}(a3, amnt3);
        token.depositFor(a4); // Should deposit 0
    }

    function _expectedTokenBalance(uint256 baseAssetAmount) internal view returns(uint256) {
        (uint256 num, uint256 denom) = token.tokenPrice();
        return baseAssetAmount / num * denom;
    }

    function test_Balances() public {
        assertEq(token.balanceOf(a1), _expectedTokenBalance(amnt1));
        assertEq(token.balanceOf(a2), _expectedTokenBalance(amnt2));
        assertEq(token.balanceOf(a3), _expectedTokenBalance(amnt3));
        assertEq(token.balanceOf(a4), 0);
    }

    function testFuzz_InvalidAssetMultipleOnDeposit(uint8 amount) public {
        (uint256 num,) = token.tokenPrice();
        if (amount % num == 0) {
            token.deposit{value: amount}();
            assertEq(token.balanceOf(address(this)), _expectedTokenBalance(amount));
        } else {
            vm.expectRevert();
            token.deposit{value: amount}();
        }
    }

    function test_TotalSupply() public {
        assertEq(token.totalSupply(), _expectedTokenBalance(amnt1 + amnt2 + amnt3));
    }

    function test_SimpleWithdraw() public {
        uint256 a2Balance = token.balanceOf(a2);
        vm.prank(a2);
        token.withdraw(a2Balance);
        assertEq(token.balanceOf(a2), 0);
        assertEq(token.totalSupply(), _expectedTokenBalance(amnt1 + amnt3));
        assertEq(a2.balance, amnt2);
    }

    function test_SimpleWithdrawTo() public {
        uint256 a2Balance = token.balanceOf(a2);
        vm.prank(a2);
        token.withdrawTo(a1, a2Balance);
        assertEq(token.balanceOf(a2), 0);
        assertEq(token.totalSupply(), _expectedTokenBalance(amnt1 + amnt3));
        assertEq(a2.balance, 0);
        assertEq(a1.balance, amnt2);
    }

    function test_PermitWithdraw() public {
        // NEED TO IMPLEMENT
    }

    function test_WithdrawAfterRevenue() public {
        // NEED TO IMPLEMENT
    }

}