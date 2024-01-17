// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {BalanceSharesTestUtils} from "test/helpers/BalanceSharesTestUtils.sol";
import {TimelockAvatarTestUtils} from "test/helpers/TimelockAvatarTestUtils.sol";
import {ITreasurer} from "src/executor/interfaces/ITreasurer.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TreasurerBalanceSharesTest is BalanceSharesTestUtils, TimelockAvatarTestUtils {
    function setUp() public virtual override(BaseTest, TimelockAvatarTestUtils) {
        super.setUp();
    }

    function test_Fuzz_EnableBalanceShares(uint64 totalSupply, uint96 quoteAssetBalance) public {
        _mintShares(users.gwart, totalSupply);
        _giveQuoteAsset(address(executor), quoteAssetBalance);
        assertEq(totalSupply, token.totalSupply());
        assertEq(quoteAssetBalance, _quoteAssetBalanceOf(address(executor)));

        IERC20 quoteAsset = onboarder.quoteAsset();

        /**
         * totalDeposits / totalSupply = quoteAmount / mintAmount
         * or
         * totalDeposits = totalSupply * quoteAmount / mintAmount
         */
        (uint256 quoteAmount, uint256 mintAmount) = onboarder.sharePrice();
        uint256 calculatedTotalDeposits = Math.mulDiv(totalSupply, quoteAmount, mintAmount);

        // Total deposits cannot exceed the quote asset balance
        uint256 expectedTotalDeposits =
            quoteAssetBalance < calculatedTotalDeposits ? quoteAssetBalance : calculatedTotalDeposits;
        uint256 expectedDepositsAllocated =
            _expectedTreasuryBalanceShareAllocation(DEPOSITS_ID, address(quoteAsset), expectedTotalDeposits);

        uint256 snapshot = vm.snapshot();

        // Can only enable as the executor or a currently executing module
        vm.expectRevert(
            abi.encodeWithSelector(ITimelockAvatar.SenderMustBeExecutingModule.selector, address(this), MODULES_HEAD)
        );
        executor.enableBalanceShares(true);

        // Without any balance shares manager
        vm.expectEmit(false, false, false, true, address(executor));
        emit ITreasurer.BalanceSharesInitialized(address(0), expectedTotalDeposits, expectedDepositsAllocated);
        vm.prank(address(executor));
        executor.enableBalanceShares(true);
        assertEq(quoteAssetBalance, _quoteAssetBalanceOf(address(executor)));

        // With a balance shares manager
        vm.revertTo(snapshot);
        _setupDefaultBalanceShares(false);

        address manager = executor.balanceSharesManager();
        assertEq(manager, address(balanceSharesSingleton));
        (expectedDepositsAllocated,) = balanceSharesSingleton.checkBalanceShareAllocationWithRemainder(
            address(executor), DEPOSITS_ID, address(quoteAsset), expectedTotalDeposits
        );

        if (expectedDepositsAllocated > 0) {
            vm.expectEmit(true, true, false, true, address(executor));
            emit ITreasurer.BalanceShareAllocated(
                manager, DEPOSITS_ID, quoteAsset, expectedDepositsAllocated
            );
        }
        vm.expectEmit(false, false, false, true, address(executor));
        emit ITreasurer.BalanceSharesInitialized(manager, expectedTotalDeposits, expectedDepositsAllocated);
        vm.prank(address(executor));
        executor.enableBalanceShares(true);
        assertEq(quoteAssetBalance - expectedDepositsAllocated, _quoteAssetBalanceOf(address(executor)));
    }
}
