// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./TestAccountsSetup.t.sol";

contract Approval is Test, TestAccountsSetup {

    uint256 a1Balance1;
    uint256 allowance;

    function setUp() public override {
        super.setUp();
        a1Balance1 = token.balanceOf(a1);
        allowance = 100;
        vm.prank(a1);
        token.approve(address(this), allowance);
    }

    function test_TransferApproved() public {
        uint256 ta = allowance / 2;
        token.transferFrom(a1, address(this), ta);
        assertEq(token.allowance(a1, address(this)), allowance - ta);
        assertEq(token.balanceOf(a1), a1Balance1 - ta);
        assertEq(token.balanceOf(address(this)), ta);
    }

    function testFail_TransferMoreThanApprovedFor() public {
        token.transferFrom(a1, address(this), allowance + 1);
    }

    function test_IncreaseAllowance() public {
        vm.prank(a1);
        token.increaseAllowance(a2, 1);
        assertEq(token.allowance(a1, a2), 1);
        vm.prank(a2);
        token.transferFrom(a1, address(this), 1);
        assertEq(token.balanceOf(a1), a1Balance1 - 1);
        assertEq(token.balanceOf(address(this)), 1);
    }

    function test_DecreaseAllowance() public {
        vm.prank(a1);
        token.decreaseAllowance(address(this), 1);
        assertEq(token.allowance(a1, address(this)), allowance - 1);
        vm.expectRevert(
            abi.encodeWithSelector(ERC20Checkpoints.InsufficientAllowance.selector, allowance - 1)
        );
        token.transferFrom(a1, address(this), allowance);
        vm.startPrank(a1);
        vm.expectRevert(ERC20Checkpoints.DecreasedAllowanceBelowZero.selector);
        token.decreaseAllowance(address(this), allowance);
    }

    function test_ERC20Permit() public {
        (uint256 pk, address a) = _generateTestPrivateKey();
        uint256 amount = 100;

        vm.prank(a1);
        token.transfer(a, amount);

        assertEq(token.balanceOf(a), amount);

        uint256 deadline = block.timestamp + 1 days;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                a,
                address(this),
                amount,
                token.nonces(a),
                deadline
            )
        );
        bytes32 dataHash = ECDSA.toTypedDataHash(_generateEIP712DomainSeperator(), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, dataHash);
        token.permit(
            a,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );

        assertEq(token.allowance(a, address(this)), amount);

        token.transferFrom(a, address(this), amount);
        assertEq(token.balanceOf(address(this)), amount);
        assertEq(token.balanceOf(a), 0);

    }
}