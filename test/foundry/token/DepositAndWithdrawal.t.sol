// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./TestAccountsSetup.t.sol";

contract DepositAndWithdrawal is Test, TestAccountsSetup {

    function test_Balances() public {
        assertEq(token.balanceOf(a1), _expectedTokenBalance(amnt1));
        assertEq(token.balanceOf(a2), _expectedTokenBalance(amnt2));
        assertEq(token.balanceOf(a3), _expectedTokenBalance(amnt3));
        assertEq(token.balanceOf(a4), 0);
    }

    function testFuzz_InvalidAssetMultipleOnDeposit(uint8 amount) public {
        (uint256 num,) = token.tokenPrice();
        if (amount % num == 0) {
            if (amount == 0) vm.expectRevert(); // Throws an error in the TreasurerOld if the deposit amount is zero
            token.deposit{value: amount}();
            assertEq(token.balanceOf(address(this)), _expectedTokenBalance(amount));
        } else {
            vm.expectRevert();
            token.deposit{value: amount}();
        }
    }

    function test_TotalSupply() public {
        assertEq(token.totalSupply(), _expectedTokenBalance(amntTotal));
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
        (uint256 pk, address a) = _generateTestPrivateKey();
        uint256 n = 1 ether;
        token.depositFor{ value: 1 ether}(a);
        assertEq(token.balanceOf(a), _expectedTokenBalance(n));

        uint256 expiry = block.timestamp + 1 days;
        uint256 amount = token.balanceOf(a) / 2;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Withdraw(address owner,address receiver,uint256 amount,uint256 nonce,uint256 expiry)"),
                a,
                a,
                amount,
                token.nonces(a),
                expiry
            )
        );
        bytes32 dataHash = ECDSA.toTypedDataHash(_generateEIP712DomainSeperator(), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, dataHash);
        token.withdrawBySig(
            a,
            a,
            amount,
            expiry,
            v,
            r,
            s
        );

        assertEq(token.balanceOf(a), _expectedTokenBalance(n / 2));
        assertEq(a.balance, n / 2);
    }

    function test_WithdrawAfterRevenue() public {
        (bool success,) = address(executor).call{ value: amntTotal }("");
        assertEq(success, true);
        uint256 a1Balance = token.balanceOf(a1);
        vm.prank(a1);
        token.withdraw(a1Balance);
        assertEq(token.balanceOf(a1), 0);
        assertEq(a1.balance, amnt1 * 2); // Should be twice as much since we doubled the treasury
    }

}