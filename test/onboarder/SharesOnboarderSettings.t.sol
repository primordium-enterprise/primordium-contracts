// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {ISharesOnboarder} from "src/onboarder/interfaces/ISharesOnboarder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "src/utils/OwnableUpgradeable.sol";

contract SharesOnboarderSettingsTest is BaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_SetQuoteAsset() public {
        address currentQuoteAsset = address(onboarder.quoteAsset());
        address newQuoteAsset = address(mockERC20);

        // Only owner can make updates
        vm.prank(users.maliciousUser);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.maliciousUser));
        onboarder.setQuoteAsset(address(mockERC20));

        // Cannot set to self
        vm.prank(onboarder.owner());
        vm.expectRevert(ISharesOnboarder.CannotSetQuoteAssetToSelf.selector);
        onboarder.setQuoteAsset(address(onboarder));

        // Allow change
        vm.prank(onboarder.owner());
        vm.expectEmit(false, false, false, true, address(onboarder));
        emit ISharesOnboarder.QuoteAssetChange(currentQuoteAsset, newQuoteAsset);
        onboarder.setQuoteAsset(address(mockERC20));
        assertEq(newQuoteAsset, address(onboarder.quoteAsset()));
    }

    function test_SetAdmin() public {
        // Make gwart an admin
        address admin = users.gwart;

        // Should not be an admin yet
        (bool expectedIsAdmin, uint256 expectedExpiresAt) = onboarder.adminStatus(admin);
        assertFalse(expectedIsAdmin);
        assertEq(0, expectedExpiresAt);

        // Prepare set admin call
        expectedIsAdmin = true;
        expectedExpiresAt = block.timestamp + 1;
        address[] memory accounts = new address[](1);
        uint256[] memory expiresAts = new uint256[](1);
        accounts[0] = admin;
        expiresAts[0] = expectedExpiresAt;

        // Only owner
        vm.prank(users.maliciousUser);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.maliciousUser));
        onboarder.setAdminExpirations(accounts, expiresAts);

        // Update admin for gwart
        vm.prank(onboarder.owner());
        vm.expectEmit(true, false, false, true, address(onboarder));
        emit ISharesOnboarder.AdminStatusChange(admin, 0, expectedExpiresAt);
        onboarder.setAdminExpirations(accounts, expiresAts);

        (bool isAdmin, uint256 expiresAt) = onboarder.adminStatus(admin);
        assertEq(expectedIsAdmin, isAdmin);
        assertEq(expectedExpiresAt, expiresAt);

        // Fast forward, no longer admin
        vm.warp(block.timestamp + 1);
        expectedIsAdmin = false;
        (isAdmin, expiresAt) = onboarder.adminStatus(admin);
        assertEq(expectedIsAdmin, isAdmin);
        assertEq(expectedExpiresAt, expiresAt);
    }

    function test_AdminPausesFunding() public {
        (uint256 expectedFundingBeginsAt, uint256 expectedFundingEndsAt) = onboarder.fundingPeriods();

        // Make gwart an admin
        address admin = users.gwart;
        address owner = onboarder.owner();
        address[] memory accounts = new address[](1);
        uint256[] memory expiresAts = new uint256[](1);
        accounts[0] = admin;
        expiresAts[0] = block.timestamp + 1;
        vm.prank(owner);
        onboarder.setAdminExpirations(accounts, expiresAts);

        // Another user cannot pause funding
        vm.prank(users.maliciousUser);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.maliciousUser));
        onboarder.pauseFunding();
        (uint256 fundingBeginsAt, uint256 fundingEndsAt) = onboarder.fundingPeriods();
        assertEq(fundingBeginsAt, expectedFundingBeginsAt);
        assertEq(fundingEndsAt, expectedFundingEndsAt);

        // Create snapshot to test admin and owner
        uint256 snapshot = vm.snapshot();

        // Admin can pause funding
        expectedFundingEndsAt = block.timestamp;
        vm.prank(admin);
        vm.expectEmit(true, false, false, false, address(onboarder));
        emit ISharesOnboarder.AdminPausedFunding(admin);
        onboarder.pauseFunding();
        (fundingBeginsAt, fundingEndsAt) = onboarder.fundingPeriods();
        assertEq(fundingBeginsAt, expectedFundingBeginsAt);
        assertEq(fundingEndsAt, expectedFundingEndsAt);

        // Owner can pause funding
        vm.revertTo(snapshot);
        vm.prank(owner);
        vm.expectEmit(true, false, false, false, address(onboarder));
        emit ISharesOnboarder.AdminPausedFunding(owner);
        onboarder.pauseFunding();
        (fundingBeginsAt, fundingEndsAt) = onboarder.fundingPeriods();
        assertEq(fundingBeginsAt, expectedFundingBeginsAt);
        assertEq(fundingEndsAt, expectedFundingEndsAt);
    }
}