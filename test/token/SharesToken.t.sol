// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {ISharesToken} from "src/token/interfaces/ISharesToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ITreasury} from "src/executor/interfaces/ITreasury.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SharesTokenTest is BaseTest {
    uint256 gwartShares = 200;
    uint256 bobShares = 300;
    uint256 aliceShares = 500;

    function setUp() public virtual override {
        super.setUp();
        // Mint shares to gwart, bob, and alice
        vm.startPrank(token.owner());
        token.mint(users.gwart, gwartShares);
        token.mint(users.bob, bobShares);
        token.mint(users.alice, aliceShares);
        vm.stopPrank();
    }

    function test_TotalSupply() public {
        assertEq(token.totalSupply(), gwartShares + bobShares + aliceShares);
    }

    function test_SetMaxSupply() public {
        uint256 newMaxSupply = uint256(type(uint208).max) + 1;
        vm.startPrank(token.owner());
        vm.expectRevert(abi.encodeWithSelector(ISharesToken.MaxSupplyTooLarge.selector, type(uint208).max));
        token.setMaxSupply(newMaxSupply);

        newMaxSupply = type(uint208).max;
        vm.expectEmit(false, false, false, true, address(token));
        emit ISharesToken.MaxSupplyChange(token.maxSupply(), newMaxSupply);
        token.setMaxSupply(newMaxSupply);
        vm.stopPrank();
    }

    function test_Mint() public {}

    function test_Transfer() public {
        // Transfer half of gwart's shares to alice
        uint256 cachedTotalSupply = token.totalSupply();
        uint256 transferAmount = gwartShares / 2;
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(users.gwart, users.alice, transferAmount);
        vm.prank(users.gwart);
        token.transfer(users.alice, transferAmount);
        assertEq(gwartShares - transferAmount, token.balanceOf(users.gwart));
        assertEq(aliceShares + transferAmount, token.balanceOf(users.alice));
        // Total supply should not change
        assertEq(cachedTotalSupply, token.totalSupply());

        // Transfer double of what gwart has left, which should revert
        transferAmount = gwartShares;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                users.gwart,
                token.balanceOf(users.gwart),
                transferAmount
            )
        );
        vm.prank(users.gwart);
        token.transfer(users.alice, transferAmount);
        assertEq(cachedTotalSupply, token.totalSupply());
    }

    function test_Fuzz_Transfer(uint8 transferAmount) public {
        // Transfer half of gwart's shares to alice
        uint256 cachedTotalSupply = token.totalSupply();

        if (transferAmount <= gwartShares) {
            vm.expectEmit(true, true, false, true);
            emit IERC20.Transfer(users.gwart, users.alice, transferAmount);
            vm.prank(users.gwart);
            token.transfer(users.alice, transferAmount);
            assertEq(gwartShares - transferAmount, token.balanceOf(users.gwart));
            assertEq(aliceShares + transferAmount, token.balanceOf(users.alice));
            // Total supply should not change
            assertEq(cachedTotalSupply, token.totalSupply());
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector,
                    users.gwart,
                    token.balanceOf(users.gwart),
                    transferAmount
                )
            );
            vm.prank(users.gwart);
            token.transfer(users.alice, transferAmount);
            assertEq(cachedTotalSupply, token.totalSupply());
        }
    }

    function test_TransferFrom() public {
        // Approve bob to send half of gwart's shares to alice
        uint256 cachedTotalSupply = token.totalSupply();
        uint256 transferAmount = gwartShares / 2;
        vm.prank(users.gwart);
        token.approve(users.bob, transferAmount);
        assertEq(token.allowance(users.gwart, users.bob), transferAmount);

        // Bob sends the amount from gwart to alice
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(users.gwart, users.alice, transferAmount);
        vm.prank(users.bob);
        token.transferFrom(users.gwart, users.alice, transferAmount);
        assertEq(gwartShares - transferAmount, token.balanceOf(users.gwart));
        assertEq(aliceShares + transferAmount, token.balanceOf(users.alice));
        // Total supply should not change
        assertEq(cachedTotalSupply, token.totalSupply());

        // Bob attempts to send more, which should revert with insufficient allowance
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, users.bob, 0, transferAmount)
        );
        vm.prank(users.bob);
        token.transferFrom(users.gwart, users.alice, transferAmount);

        // Bob is approved to spend more, but gwart does not have enough balance
        transferAmount = gwartShares;
        vm.prank(users.gwart);
        token.approve(users.bob, transferAmount);
        assertEq(token.allowance(users.gwart, users.bob), transferAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                users.gwart,
                token.balanceOf(users.gwart),
                transferAmount
            )
        );
        vm.prank(users.bob);
        token.transferFrom(users.gwart, users.alice, transferAmount);
    }

    function test_Fuzz_TransferFrom(uint8 transferAmount, uint8 allowance) public {
        // Approve bob to send half of gwart's shares to alice
        uint256 cachedTotalSupply = token.totalSupply();

        vm.prank(users.gwart);
        token.approve(users.bob, allowance);
        assertEq(token.allowance(users.gwart, users.bob), allowance);

        bool noRevert;
        if (transferAmount > allowance) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, users.bob, allowance, transferAmount
                )
            );
        } else {
            if (transferAmount > gwartShares) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IERC20Errors.ERC20InsufficientBalance.selector,
                        users.gwart,
                        token.balanceOf(users.gwart),
                        transferAmount
                    )
                );
            } else {
                vm.expectEmit(true, true, false, true);
                emit IERC20.Transfer(users.gwart, users.alice, transferAmount);
                noRevert = true;
            }
        }
        vm.prank(users.bob);
        token.transferFrom(users.gwart, users.alice, transferAmount);
        if (noRevert) {
            assertEq(gwartShares - transferAmount, token.balanceOf(users.gwart));
            assertEq(aliceShares + transferAmount, token.balanceOf(users.alice));
        } else {
            assertEq(gwartShares, token.balanceOf(users.gwart));
            assertEq(aliceShares, token.balanceOf(users.alice));
        }
        // Total supply should not change
        assertEq(cachedTotalSupply, token.totalSupply());
    }

    function _setupWithdrawExpectations(
        address treasury,
        address withdrawer,
        address receiver,
        uint256 withdrawAmount,
        uint256 treasuryETHAmount,
        uint256 treasuryERC20Amount
    )
        internal
        returns (
            uint256 expectedETHPayout,
            uint256 expectedERC20Payout,
            uint256 expectedWithdrawerResultingShares,
            uint256 expectedTotalSupply,
            IERC20[] memory assets
        )
    {
        return _setupWithdrawExpectations(treasury, withdrawer, receiver, withdrawAmount, treasuryETHAmount, treasuryERC20Amount, '');
    }

    function _setupWithdrawExpectations(
        address treasury,
        address withdrawer,
        address receiver,
        uint256 withdrawAmount,
        uint256 treasuryETHAmount,
        uint256 treasuryERC20Amount,
        bytes memory expectedRevertOverride
    )
        internal
        returns (
            uint256 expectedETHPayout,
            uint256 expectedERC20Payout,
            uint256 expectedWithdrawerResultingShares,
            uint256 expectedTotalSupply,
            IERC20[] memory assets
        )
    {
        deal(treasury, treasuryETHAmount);
        deal(address(mockERC20), treasury, treasuryERC20Amount);

        expectedWithdrawerResultingShares = token.balanceOf(withdrawer);
        expectedTotalSupply = token.totalSupply();

        assets = new IERC20[](2);
        assets[0] = IERC20(address(0)); // ETH
        assets[1] = IERC20(address(mockERC20));

        if (expectedRevertOverride.length > 0) {
            vm.expectRevert(expectedRevertOverride);
        } else if (receiver == address(0)) {
            vm.expectRevert(ISharesToken.WithdrawToZeroAddress.selector);
        } else if (withdrawAmount == 0) {
            vm.expectRevert(ISharesToken.WithdrawAmountInvalid.selector);
        } else if (withdrawAmount > expectedWithdrawerResultingShares) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, withdrawer, expectedWithdrawerResultingShares, withdrawAmount
                )
            );
        } else {
            expectedETHPayout = Math.mulDiv(treasuryETHAmount, withdrawAmount, expectedTotalSupply);
            expectedERC20Payout = Math.mulDiv(treasuryERC20Amount, withdrawAmount, expectedTotalSupply);
            expectedWithdrawerResultingShares = expectedWithdrawerResultingShares - withdrawAmount;

            // Anticipated events
            if (expectedTotalSupply > 0 && withdrawAmount > 0) {
                vm.expectEmit(true, true, false, true, address(token));
                emit IERC20.Transfer(withdrawer, address(0), withdrawAmount);

                if (expectedETHPayout > 0) {
                    vm.expectEmit(true, false, false, true, treasury);
                    emit ITreasury.WithdrawalAssetProcessed(withdrawer, receiver, assets[0], expectedETHPayout);
                }

                if (expectedERC20Payout > 0) {
                    vm.expectEmit(true, false, false, true, treasury);
                    emit ITreasury.WithdrawalAssetProcessed(withdrawer, receiver, assets[1], expectedERC20Payout);
                }

                vm.expectEmit(true, false, false, true, treasury);
                emit ITreasury.WithdrawalProcessed(withdrawer, receiver, withdrawAmount, expectedTotalSupply, assets);
            }

            expectedTotalSupply -= withdrawAmount;
        }
    }

    function test_Fuzz_Withdraw(uint8 withdrawAmount, uint96 treasuryETHAmount, uint96 treasuryERC20Amount) public {
        address treasury = address(executor);

        (
            uint256 expectedETHPayout,
            uint256 expectedERC20Payout,
            uint256 expectedGwartShares,
            uint256 totalSupply,
            IERC20[] memory assets
        ) = _setupWithdrawExpectations(
            treasury, users.gwart, users.gwart, withdrawAmount, treasuryETHAmount, treasuryERC20Amount
        );

        vm.prank(users.gwart);
        token.withdraw(withdrawAmount, assets);

        assertEq(users.gwart.balance, expectedETHPayout);
        assertEq(mockERC20.balanceOf(users.gwart), expectedERC20Payout);
        assertEq(expectedGwartShares, token.balanceOf(users.gwart));
        assertEq(totalSupply, token.totalSupply());
        assertEq(treasuryETHAmount - expectedETHPayout, treasury.balance);
        assertEq(treasuryERC20Amount - expectedERC20Payout, mockERC20.balanceOf(treasury));
    }

    function test_Fuzz_WithdrawTo(
        uint8 withdrawAmount,
        address receiver,
        uint96 treasuryETHAmount,
        uint96 treasuryERC20Amount
    )
        public
    {
        address treasury = address(executor);

        (
            uint256 expectedETHPayout,
            uint256 expectedERC20Payout,
            uint256 expectedGwartShares,
            uint256 totalSupply,
            IERC20[] memory assets
        ) = _setupWithdrawExpectations(
            treasury, users.gwart, receiver, withdrawAmount, treasuryETHAmount, treasuryERC20Amount
        );

        vm.prank(users.gwart);
        token.withdrawTo(receiver, withdrawAmount, assets);

        assertEq(receiver.balance, expectedETHPayout);
        assertEq(mockERC20.balanceOf(receiver), expectedERC20Payout);
        assertEq(expectedGwartShares, token.balanceOf(users.gwart));
        assertEq(totalSupply, token.totalSupply());
        assertEq(treasuryETHAmount - expectedETHPayout, treasury.balance);
        assertEq(treasuryERC20Amount - expectedERC20Payout, mockERC20.balanceOf(treasury));
    }

    function test_Fuzz_WithdrawToBySig(
        uint8 withdrawAmount,
        address receiver,
        uint96 treasuryETHAmount,
        uint96 treasuryERC20Amount,
        uint48 deadline,
        address sender
    ) public {
        vm.assume(sender != address(0));

        // Transfer gwart's shares to signer
        vm.prank(users.gwart);
        token.transfer(users.signer, gwartShares);

        address treasury = address(executor);

        (, string memory name, string memory version,,,,) = token.eip712Domain();

        uint256 nonce = token.nonces(users.signer);

        bytes memory expiredRevert;
        if (block.timestamp > deadline) {
            expiredRevert = abi.encodeWithSelector(ISharesToken.WithdrawToExpiredSignature.selector, deadline);
        }

        (
            uint256 expectedETHPayout,
            uint256 expectedERC20Payout,
            uint256 expectedSignerShares,
            uint256 totalSupply,
            IERC20[] memory assets
        ) = _setupWithdrawExpectations(
            treasury, users.signer, receiver, withdrawAmount, treasuryETHAmount, treasuryERC20Amount, expiredRevert
        );

        bytes32 tokensContentHash = keccak256(abi.encodePacked(assets));

        bytes32 WITHDRAW_TO_TYPEHASH = keccak256(
            "WithdrawTo(address owner,address receiver,uint256 amount,address[] tokens,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(WITHDRAW_TO_TYPEHASH, users.signer, receiver, withdrawAmount, tokensContentHash, nonce, deadline)
        );

        bytes32 dataHash = _hashTypedData(_buildEIP712DomainSeparator(name, version, address(token)), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signerPrivateKey, dataHash);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(sender);
        token.withdrawToBySig(users.signer, receiver, withdrawAmount, assets, deadline, signature);

        assertEq(receiver.balance, expectedETHPayout, "Invalid ETH payout");
        assertEq(mockERC20.balanceOf(receiver), expectedERC20Payout, "Invalid ERC20 payout");
        assertEq(expectedSignerShares, token.balanceOf(users.signer), "Invalid shares balance");
        assertEq(totalSupply, token.totalSupply(), "Invalid total supply");
        assertEq(treasuryETHAmount - expectedETHPayout, treasury.balance);
        assertEq(treasuryERC20Amount - expectedERC20Payout, mockERC20.balanceOf(treasury));
    }
}
