// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest, console2} from "test/Base.t.sol";
import {ISharesOnboarder} from "src/onboarder/interfaces/ISharesOnboarder.sol";
import {IERC20Snapshots} from "src/token/interfaces/IERC20Snapshots.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SharesOnboarderTest is BaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    // Helper to make a deposit as the provided account, with optional bytes for expected error
    function _deposit(address account, uint256 depositAmount, bytes memory err) internal returns (uint256 mintAmount) {
        uint256 value = _giveQuoteAsset(account, depositAmount);
        vm.prank(account);
        if (err.length > 0) {
            vm.expectRevert(err);
        }
        mintAmount = onboarder.deposit{value: value}(depositAmount);
    }

    function test_Deposits() public {}

    function test_Revert_OutsideFundingPeriods() public {
        bytes memory fundingNotActiveErr = abi.encodeWithSelector(ISharesOnboarder.FundingIsNotActive.selector);

        vm.warp(ONBOARDER.fundingBeginsAt - 1);
        _deposit(users.gwart, ONBOARDER.quoteAmount, fundingNotActiveErr);

        vm.warp(ONBOARDER.fundingEndsAt);
        _deposit(users.gwart, ONBOARDER.quoteAmount, fundingNotActiveErr);
    }

    function test_Fuzz_SetSharePrices(uint256 quoteAmount, uint256 mintAmount) public {
        vm.prank(onboarder.owner());

        uint256 maxSharePrice = type(uint128).max;
        if (quoteAmount > maxSharePrice || mintAmount > maxSharePrice) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    SafeCast.SafeCastOverflowedUintDowncast.selector,
                    128,
                    quoteAmount > maxSharePrice ? quoteAmount : mintAmount
                )
            );
        }
        onboarder.setSharePrice(quoteAmount, mintAmount);
    }

    function test_Fuzz_SharePrices(
        uint256 quoteAmount,
        uint256 mintAmount,
        uint256 depositAmount,
        uint8 depositMultiple
    )
        public
    {
        vm.assume(depositAmount > 0 && depositAmount < type(uint128).max && depositMultiple > 0);

        address owner = onboarder.owner();

        uint256 maxSharePrice = type(uint128).max;
        quoteAmount = Math.min(quoteAmount, maxSharePrice);
        mintAmount = Math.min(mintAmount, token.maxSupply() / depositMultiple); // Ensures no max supply overflow
        vm.prank(owner);
        onboarder.setSharePrice(quoteAmount, mintAmount);

        // Funding not active for zero values
        if (quoteAmount == 0 || mintAmount == 0) {
            _deposit(users.gwart, depositAmount, abi.encodeWithSelector(ISharesOnboarder.FundingIsNotActive.selector));
        }

        // Set values to minimum of 2 (modulus of 1 is always zero)
        quoteAmount = Math.max(quoteAmount, 2);
        mintAmount = Math.max(mintAmount, 2);
        vm.prank(owner);
        onboarder.setSharePrice(quoteAmount, mintAmount);

        // Test reversion for deposit amount
        if (depositAmount % quoteAmount == 0) {
            depositAmount += 1;
        }
        _deposit(
            users.gwart, depositAmount, abi.encodeWithSelector(ISharesOnboarder.InvalidDepositAmountMultiple.selector)
        );

        // Test successful deposit amount multiple
        depositAmount = quoteAmount * depositMultiple;
        uint256 expectedMintAmount = depositAmount / quoteAmount * mintAmount;
        assertEq(expectedMintAmount, _deposit(users.gwart, depositAmount, ""));
    }

    function test_Fuzz_DepositAmounts(uint128 depositAmount) public {
        bytes memory err;
        if (depositAmount == 0) {
            err = abi.encodeWithSelector(ISharesOnboarder.InvalidDepositAmount.selector);
        } else if (depositAmount % ONBOARDER.quoteAmount != 0) {
            err = abi.encodeWithSelector(ISharesOnboarder.InvalidDepositAmountMultiple.selector);
        }
        _deposit(users.gwart, depositAmount, err);
    }

    function test_Fuzz_DepositMultiples(uint8 depositMultiple) public {
        vm.assume(depositMultiple > 0);
        uint256 depositAmount = ONBOARDER.quoteAmount * depositMultiple;
        uint256 expectedMintAmount = depositAmount / ONBOARDER.quoteAmount * ONBOARDER.mintAmount;
        vm.expectEmit(true, false, false, true);
        emit ISharesOnboarder.Deposit(
            users.gwart, depositAmount, expectedMintAmount, users.gwart
        );
        assertEq(expectedMintAmount, _deposit(users.gwart, depositAmount, ''));
    }
}
