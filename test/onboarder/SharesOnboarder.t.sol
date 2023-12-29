// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest, console2} from "test/Base.t.sol";
import {ISharesOnboarder} from "src/onboarder/interfaces/ISharesOnboarder.sol";

contract SharesOnboarderTest is BaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    // deposits the quote amount of the base asset
    function _defaultDepositExpectError(bytes memory err) internal {
        uint256 msgValue = _giveQuoteAsset(users.gwart, ONBOARDER.quoteAmount);
        hoax(users.gwart);
        if (err.length > 0) {
            vm.expectRevert(err);
        }
        onboarder.deposit{value: msgValue}(ONBOARDER.quoteAmount);
    }

    function _defaultDeposit() internal {
        _defaultDepositExpectError('');
    }

    function test_Revert_OutsideFundingPeriods() public {
        bytes memory fundingNotActiveErr = abi.encodeWithSelector(ISharesOnboarder.FundingIsNotActive.selector);

        vm.warp(ONBOARDER.fundingBeginsAt - 1);
        _defaultDepositExpectError(fundingNotActiveErr);

        vm.warp(ONBOARDER.fundingEndsAt);
        _defaultDepositExpectError(fundingNotActiveErr);
    }
}