// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {BalanceSharesTestUtils} from "test/helpers/BalanceSharesTestUtils.sol";
import {ISharesToken} from "src/token/interfaces/ISharesToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ITreasury} from "src/executor/interfaces/ITreasury.sol";
import {Treasurer} from "src/executor/base/Treasurer.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SharesTokenTest is BaseTest, BalanceSharesTestUtils {
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

    struct WithdrawParameters {
        address treasury;
        address withdrawer;
        address receiver;
        uint256 withdrawAmount;
        IERC20[] assets;
        uint96[2] treasuryAssetAmounts;
        uint256[2] expectedPayouts;
        uint256[2] expectedBalanceShareAllocations;
        uint256 expectedWithdrawerResultingShares;
        uint256 expectedTotalSupply;
        bool expectedSuccess;
    }

    function _setupWithdrawExpectations(
        address treasury,
        address withdrawer,
        address receiver,
        uint256 withdrawAmount,
        uint96[2] memory treasuryAssetAmounts,
        bytes memory expectedRevertOverride
    )
        internal
        returns (WithdrawParameters memory $)
    {
        $.treasury = treasury;
        $.withdrawer = withdrawer;
        $.receiver = receiver;
        $.withdrawAmount = withdrawAmount;
        $.treasuryAssetAmounts = treasuryAssetAmounts;

        deal($.treasury, $.treasuryAssetAmounts[0]);
        deal(address(mockERC20), $.treasury, $.treasuryAssetAmounts[1]);

        $.expectedWithdrawerResultingShares = token.balanceOf($.withdrawer);
        $.expectedTotalSupply = token.totalSupply();

        $.assets = new IERC20[](2);
        $.assets[0] = IERC20(address(0)); // ETH
        $.assets[1] = IERC20(address(mockERC20));

        if (expectedRevertOverride.length > 0) {
            vm.expectRevert(expectedRevertOverride);
        } else if ($.receiver == address(0)) {
            vm.expectRevert(ISharesToken.WithdrawToZeroAddress.selector);
        } else if ($.withdrawAmount == 0) {
            vm.expectRevert(ISharesToken.WithdrawAmountInvalid.selector);
        } else if ($.withdrawAmount > $.expectedWithdrawerResultingShares) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector,
                    $.withdrawer,
                    $.expectedWithdrawerResultingShares,
                    $.withdrawAmount
                )
            );
        } else {
            $.expectedSuccess = true;

            $.expectedPayouts[0] = Math.mulDiv($.treasuryAssetAmounts[0], $.withdrawAmount, $.expectedTotalSupply);
            $.expectedBalanceShareAllocations[0] =
                _expectedTreasuryBalanceShareAllocation(DISTRIBUTIONS_ID, address(0), $.expectedPayouts[0]);
            $.expectedPayouts[0] -= $.expectedBalanceShareAllocations[0];

            $.expectedPayouts[1] = Math.mulDiv($.treasuryAssetAmounts[1], $.withdrawAmount, $.expectedTotalSupply);
            $.expectedBalanceShareAllocations[1] =
                _expectedTreasuryBalanceShareAllocation(DISTRIBUTIONS_ID, address(mockERC20), $.expectedPayouts[1]);
            $.expectedPayouts[1] -= $.expectedBalanceShareAllocations[1];

            $.expectedWithdrawerResultingShares = $.expectedWithdrawerResultingShares - $.withdrawAmount;

            // Anticipated events
            if ($.expectedTotalSupply > 0 && $.withdrawAmount > 0) {
                vm.expectEmit(true, true, false, true, address(token));
                emit IERC20.Transfer($.withdrawer, address(0), $.withdrawAmount);

                if ($.expectedPayouts[0] > 0) {
                    if ($.expectedBalanceShareAllocations[0] > 0) {
                        vm.expectEmit(true, true, false, true, $.treasury);
                        emit Treasurer.BalanceShareAllocated(
                            address(balanceSharesSingleton),
                            DISTRIBUTIONS_ID,
                            IERC20(address(0)),
                            $.expectedBalanceShareAllocations[0]
                        );
                    }

                    vm.expectEmit(true, false, false, true, $.treasury);
                    emit ITreasury.WithdrawalAssetProcessed($.withdrawer, $.receiver, $.assets[0], $.expectedPayouts[0]);
                }

                if ($.expectedPayouts[1] > 0) {
                    if ($.expectedBalanceShareAllocations[1] > 0) {
                        vm.expectEmit(true, true, false, true, $.treasury);
                        emit Treasurer.BalanceShareAllocated(
                            address(balanceSharesSingleton),
                            DISTRIBUTIONS_ID,
                            IERC20(address(mockERC20)),
                            $.expectedBalanceShareAllocations[1]
                        );
                    }

                    vm.expectEmit(true, false, false, true, $.treasury);
                    emit ITreasury.WithdrawalAssetProcessed($.withdrawer, $.receiver, $.assets[1], $.expectedPayouts[1]);
                }

                vm.expectEmit(true, false, false, true, $.treasury);
                emit ITreasury.WithdrawalProcessed(
                    $.withdrawer, $.receiver, $.withdrawAmount, $.expectedTotalSupply, $.assets
                );
            }

            $.expectedTotalSupply -= $.withdrawAmount;
        }

        return $;
    }

    function _defaultWithdrawAsserts(WithdrawParameters memory $) internal {
        for (uint256 i = 0; i < $.assets.length; i++) {
            assertEq(_balanceOf($.receiver, $.assets[i]), $.expectedPayouts[i]);
            assertEq(
                _balanceOf($.treasury, $.assets[i]),
                $.treasuryAssetAmounts[i] - $.expectedPayouts[i] - $.expectedBalanceShareAllocations[i]
            );
        }
        assertEq($.expectedWithdrawerResultingShares, token.balanceOf($.withdrawer));
        assertEq($.expectedTotalSupply, token.totalSupply());
    }

    function test_Fuzz_Withdraw(uint8 withdrawAmount, uint96[2] memory treasuryAssetAmounts) public {
        address withdrawer = users.gwart;

        WithdrawParameters memory $ = _setupWithdrawExpectations(
            address(executor), withdrawer, withdrawer, withdrawAmount, treasuryAssetAmounts, ""
        );

        vm.prank($.withdrawer);
        token.withdraw(withdrawAmount, $.assets);

        _defaultWithdrawAsserts($);
    }

    function test_Fuzz_WithdrawTo(
        uint8 withdrawAmount,
        address receiver,
        uint96[2] memory treasuryAssetAmounts
    )
        public
    {
        address withdrawer = users.gwart;

        WithdrawParameters memory $ = _setupWithdrawExpectations(
            address(executor), withdrawer, receiver, withdrawAmount, treasuryAssetAmounts, ""
        );

        vm.prank($.withdrawer);
        token.withdrawTo(receiver, withdrawAmount, $.assets);

        _defaultWithdrawAsserts($);
    }

    function test_Fuzz_WithdrawToBySig(
        uint8 withdrawAmount,
        address receiver,
        uint96[2] memory treasuryAssetAmounts,
        uint48 deadline,
        address sender
    )
        public
    {
        vm.assume(sender != address(0));

        address owner = users.signer.addr;

        // Transfer gwart's shares to signer
        vm.prank(users.gwart);
        token.transfer(owner, gwartShares);

        (, string memory name, string memory version,,,,) = token.eip712Domain();

        uint256 nonce = token.nonces(owner);

        bytes memory expiredRevert;
        if (block.timestamp > deadline) {
            expiredRevert = abi.encodeWithSelector(ISharesToken.WithdrawToExpiredSignature.selector, deadline);
        }

        WithdrawParameters memory $ = _setupWithdrawExpectations(
            address(executor), owner, receiver, withdrawAmount, treasuryAssetAmounts, expiredRevert
        );

        bytes32 tokensContentHash = keccak256(abi.encodePacked($.assets));

        bytes32 WITHDRAW_TO_TYPEHASH = keccak256(
            "WithdrawTo(address owner,address receiver,uint256 amount,address[] tokens,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(WITHDRAW_TO_TYPEHASH, owner, receiver, withdrawAmount, tokensContentHash, nonce, deadline)
        );

        bytes32 dataHash = _hashTypedData(_buildEIP712DomainSeparator(name, version, address(token)), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signer.privateKey, dataHash);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(sender);
        token.withdrawToBySig(owner, receiver, withdrawAmount, $.assets, deadline, signature);

        _defaultWithdrawAsserts($);
        assertEq($.expectedSuccess ? nonce + 1 : nonce, token.nonces(owner));
    }
}
