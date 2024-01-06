// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {BalanceSharesTestUtils} from "test/helpers/BalanceSharesTestUtils.sol";
import {ISharesOnboarder} from "src/onboarder/interfaces/ISharesOnboarder.sol";
import {Treasurer} from "src/executor/base/Treasurer.sol";
import {ITreasury} from "src/executor/interfaces/ITreasury.sol";
import {ERC20Utils} from "src/libraries/ERC20Utils.sol";
import {IERC20Snapshots} from "src/token/interfaces/IERC20Snapshots.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SharesOnboarderTest is BaseTest, BalanceSharesTestUtils {
    function setUp() public virtual override {
        super.setUp();
    }

    /// @dev Overload where the `account` is the `depositor`
    function _setupDepositExpectations(
        address account,
        uint256 depositAmount,
        bytes memory err
    )
        internal
        virtual
        returns (uint256, uint256, uint256)
    {
        return _setupDepositExpectations(account, account, depositAmount, err);
    }

    /// @dev Setup expected events, or expected error if the bytes error is supplied, prank as the depositor
    function _setupDepositExpectations(
        address depositor,
        address account,
        uint256 depositAmount,
        bytes memory err
    )
        internal
        virtual
        returns (uint256 value, uint256 expectedMintAmount, uint256 expectedBalanceShareAllocation)
    {
        value = _giveQuoteAsset(depositor, depositAmount);
        if (err.length > 0) {
            vm.expectRevert(err);
        } else {
            (uint256 quoteAmount, uint256 mintAmount) = onboarder.sharePrice();
            expectedMintAmount = depositAmount / quoteAmount * mintAmount;
            expectedBalanceShareAllocation =
                _expectedTreasuryBalanceShareAllocation(DEPOSITS_ID, address(onboarder.quoteAsset()), depositAmount);

            if (expectedBalanceShareAllocation > 0) {
                vm.expectEmit(true, true, false, true, address(executor));
                emit Treasurer.BalanceShareAllocated(
                    executor.balanceSharesManager(), DEPOSITS_ID, ONBOARDER.quoteAsset, expectedBalanceShareAllocation
                );
            }

            vm.expectEmit(true, true, false, true, address(token));
            emit IERC20.Transfer(address(0), account, expectedMintAmount);

            vm.expectEmit(true, false, false, true, address(executor));
            emit ITreasury.DepositRegistered(account, ONBOARDER.quoteAsset, depositAmount, expectedMintAmount);

            vm.expectEmit(true, false, false, true, address(onboarder));
            emit ISharesOnboarder.Deposit(account, depositAmount, expectedMintAmount, depositor);
        }

        vm.prank(depositor);
    }

    function test_Revert_OutsideFundingPeriods() public {
        bytes memory fundingNotActiveError = abi.encodeWithSelector(ISharesOnboarder.FundingIsNotActive.selector);
        uint256 depositAmount = ONBOARDER.quoteAmount;
        address depositor = users.gwart;

        vm.warp(ONBOARDER.fundingBeginsAt - 1);
        (uint256 value,,) = _setupDepositExpectations(depositor, depositAmount, fundingNotActiveError);
        onboarder.deposit{value: value}(depositAmount);

        vm.warp(ONBOARDER.fundingEndsAt);
        (value,,) = _setupDepositExpectations(depositor, depositAmount, fundingNotActiveError);
        onboarder.deposit{value: value}(depositAmount);
    }

    function test_Fuzz_SetSharePrices(uint256 quoteAmount, uint256 mintAmount) public {
        address owner = onboarder.owner();
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

        vm.prank(owner);
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
        // forgefmt: disable-next-item
        vm.assume(
            depositAmount > 0 &&
            depositAmount < type(uint128).max &&
            depositMultiple > 0
        );

        address owner = onboarder.owner();

        uint256 maxSharePrice = type(uint128).max;
        quoteAmount = Math.min(quoteAmount, maxSharePrice);
        mintAmount = Math.min(mintAmount, token.maxSupply() / depositMultiple); // Ensures no max supply overflow
        vm.prank(owner);
        onboarder.setSharePrice(quoteAmount, mintAmount);

        uint256 value;
        address depositor = users.gwart;

        // Funding not active for zero values
        if (quoteAmount == 0 || mintAmount == 0) {
            (value,,) = _setupDepositExpectations(
                depositor, depositAmount, abi.encodeWithSelector(ISharesOnboarder.FundingIsNotActive.selector)
            );
            onboarder.deposit{value: value}(depositAmount);
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
        _setupDepositExpectations(
            depositor, depositAmount, abi.encodeWithSelector(ISharesOnboarder.InvalidDepositAmountMultiple.selector)
        );
        onboarder.deposit{value: value}(depositAmount);
    }

    function test_Fuzz_DepositMsgValues(uint8 depositMultiple, uint256 value) public {
        vm.assume(depositMultiple > 0);
        uint256 depositAmount = depositMultiple * ONBOARDER.quoteAmount;
        uint256 expectedMintAmount = depositMultiple * ONBOARDER.mintAmount;
        uint256 correctValue = _giveQuoteAsset(users.gwart, depositAmount);

        // deal gwart the eth amount
        vm.deal(users.gwart, value);

        if (value != correctValue) {
            vm.expectRevert(abi.encodeWithSelector(ERC20Utils.InvalidMsgValue.selector, correctValue, value));
            expectedMintAmount = 0;
        }
        vm.prank(users.gwart);
        uint256 mintAmount = onboarder.deposit{value: value}(depositAmount);

        assertEq(expectedMintAmount, mintAmount);
        assertEq(expectedMintAmount, token.balanceOf(users.gwart));
    }

    function test_Fuzz_RandomDepositAmounts(uint128 depositAmount) public {
        bytes memory err;
        if (depositAmount == 0) {
            err = abi.encodeWithSelector(ISharesOnboarder.InvalidDepositAmount.selector);
        } else if (depositAmount % ONBOARDER.quoteAmount != 0) {
            err = abi.encodeWithSelector(ISharesOnboarder.InvalidDepositAmountMultiple.selector);
        }
        (uint256 value, uint256 expectedMintAmount,) = _setupDepositExpectations(users.gwart, depositAmount, err);
        uint256 mintAmount = onboarder.deposit{value: value}(depositAmount);

        assertEq(expectedMintAmount, mintAmount);
        assertEq(expectedMintAmount, token.balanceOf(users.gwart));
        assertEq(expectedMintAmount, token.totalSupply());
    }

    function test_Fuzz_ValidDepositAmounts(uint8 depositMultiple) public {
        vm.assume(depositMultiple > 0);
        uint256 depositAmount = ONBOARDER.quoteAmount * depositMultiple;
        address depositor = users.gwart;

        (uint256 value, uint256 expectedMintAmount, uint256 expectedBalanceShareAllocation) =
            _setupDepositExpectations(depositor, depositAmount, "");
        uint256 mintAmount = onboarder.deposit{value: value}(depositAmount);

        assertEq(expectedMintAmount, mintAmount);
        assertEq(expectedMintAmount, token.balanceOf(users.gwart));
        assertEq(expectedMintAmount, token.totalSupply());
        assertEq(depositAmount - expectedBalanceShareAllocation, _quoteAssetBalanceOf(address(executor)));
    }

    function test_Fuzz_ValidDepositForAmounts(uint8 depositMultiple) public {
        // gwart deposits to mint shares for alice
        vm.assume(depositMultiple > 0);
        uint256 depositAmount = ONBOARDER.quoteAmount * depositMultiple;
        address depositor = users.gwart;
        address account = users.alice;

        (uint256 value, uint256 expectedMintAmount, uint256 expectedBalanceShareAllocation) =
            _setupDepositExpectations(depositor, account, depositAmount, "");
        uint256 mintAmount = onboarder.depositFor{value: value}(account, depositAmount);

        assertEq(_quoteAssetBalanceOf(account), 0); // Alice should not have any quote asset to deposit
        assertEq(expectedMintAmount, mintAmount);
        assertEq(expectedMintAmount, token.balanceOf(account));
        assertEq(0, token.balanceOf(depositor));
        assertEq(expectedMintAmount, token.totalSupply());
        assertEq(depositAmount - expectedBalanceShareAllocation, _quoteAssetBalanceOf(address(executor)));
    }

    function test_Revert_MaxSupplyOverflow() public {
        // Equal to max supply should work fine
        uint256 maxSupply = TOKEN.maxSupply;
        uint256 depositMultiple = (maxSupply / ONBOARDER.mintAmount);
        uint256 depositAmount = ONBOARDER.quoteAmount * depositMultiple;
        address depositor = users.gwart;

        (uint256 value, uint256 expectedMintAmount,) = _setupDepositExpectations(depositor, depositAmount, "");
        uint256 mintAmount = onboarder.deposit{value: value}(depositAmount);
        assertEq(expectedMintAmount, mintAmount);
        assertEq(expectedMintAmount, token.balanceOf(depositor));

        // Expect revert due to overflow
        depositAmount = ONBOARDER.quoteAmount;
        (value, expectedMintAmount,) = _setupDepositExpectations(
            depositor,
            depositAmount,
            abi.encodeWithSelector(
                IERC20Snapshots.ERC20MaxSupplyOverflow.selector, maxSupply, maxSupply + ONBOARDER.mintAmount
            )
        );
        onboarder.deposit{value: value}(depositAmount);

        // Increase max supply by mintAmount
        maxSupply += ONBOARDER.mintAmount;
        vm.prank(token.owner());
        token.setMaxSupply(maxSupply);

        // Now deposit should work
        (value, expectedMintAmount,) = _setupDepositExpectations(depositor, depositAmount, "");
        mintAmount = onboarder.deposit{value: value}(depositAmount);
        assertEq(expectedMintAmount, mintAmount);

        // But an additional deposit should again revert due to overflow
        (value,,) = _setupDepositExpectations(
            depositor,
            depositAmount,
            abi.encodeWithSelector(
                IERC20Snapshots.ERC20MaxSupplyOverflow.selector, maxSupply, maxSupply + ONBOARDER.mintAmount
            )
        );
        onboarder.deposit{value: value}(depositAmount);
    }

    function test_PauseFunding() public {
        // Revert for non-admin
        vm.prank(users.maliciousUser);
    }
}
