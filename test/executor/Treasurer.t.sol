// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {BalanceSharesTestUtils} from "test/helpers/BalanceSharesTestUtils.sol";
import {TimelockAvatarTestUtils} from "test/helpers/TimelockAvatarTestUtils.sol";
import {ITreasurer} from "src/executor/interfaces/ITreasurer.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {IBalanceShareAllocations} from "balance-shares-protocol/interfaces/IBalanceShareAllocations.sol";
import {SelfAuthorized} from "src/executor/base/SelfAuthorized.sol";
import {ISharesOnboarder} from "src/onboarder/interfaces/ISharesOnboarder.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ExecutorV1Harness} from "test/harness/ExecutorV1Harness.sol";
import {DistributorV1Harness} from "test/harness/DistributorV1Harness.sol";
import {IDistributor} from "src/executor/extensions/interfaces/IDistributor.sol";
import {IDistributionCreator} from "src/executor/interfaces/IDistributionCreator.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {ERC165Verifier} from "src/libraries/ERC165Verifier.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TreasurerTest is BalanceSharesTestUtils, TimelockAvatarTestUtils {
    using ERC165Checker for address;

    function setUp() public virtual override(BaseTest, TimelockAvatarTestUtils) {
        super.setUp();
    }

    function test_DistributorSetUp() public {
        assertEq(address(executor.distributor()), address(distributor), "Invalid distributor address on executor");

        assertEq(address(executor), distributor.owner(), "Invalid distributor owner.");

        assertTrue(address(distributor).supportsInterface(type(IDistributionCreator).interfaceId));
        assertTrue(address(distributor).supportsInterface(type(IDistributor).interfaceId));
    }

    function test_InitBalanceShares() public {
        // Create a new executor proxy for re-initialization (and new distributor)
        executor = ExecutorV1Harness(payable(address(new ERC1967Proxy(executorImpl, ""))));
        vm.label({account: address(executor), newLabel: "NewExecutor"});

        DISTRIBUTOR.owner = address(executor);
        distributor = DistributorV1Harness(address(new ERC1967Proxy(distributorImpl, "")));
        _initializeDistributor();
        EXECUTOR.treasurerInit.distributor = address(distributor);

        address balanceSharesManager = address(balanceSharesSingleton);

        // Setup the default balance shares
        (address[] memory accounts, uint256[] memory basisPoints) = _getDefaultBalanceShareAccounts();
        bytes[] memory balanceSharesManagerCalldatas = new bytes[](2);
        balanceSharesManagerCalldatas[0] =
            abi.encodeCall(balanceSharesSingleton.setAccountSharesBps, (DEPOSITS_ID, accounts, basisPoints));
        balanceSharesManagerCalldatas[1] =
            abi.encodeCall(balanceSharesSingleton.setAccountSharesBps, (DISTRIBUTIONS_ID, accounts, basisPoints));

        // Before setup, should be uninitialized
        assertEq(address(0), address(executor.balanceSharesManager()));

        // Update initialization params
        EXECUTOR.treasurerInit.balanceSharesManager = balanceSharesManager;
        EXECUTOR.treasurerInit.balanceSharesManagerCalldatas = balanceSharesManagerCalldatas;

        // Initialize executor
        vm.expectEmit(false, false, false, true, address(executor));
        emit ITreasurer.BalanceSharesManagerUpdate(address(0), balanceSharesManager);
        executor.setUp(EXECUTOR);

        // After setup, should be the new address
        assertEq(balanceSharesManager, address(executor.balanceSharesManager()));
        assertEq(
            defaultBalanceShareBps, balanceSharesSingleton.getAccountBps(address(executor), DEPOSITS_ID, accounts[0])
        );
        assertEq(
            defaultBalanceShareBps,
            balanceSharesSingleton.getAccountBps(address(executor), DISTRIBUTIONS_ID, accounts[0])
        );
    }

    function test_SetSharesOnboarder() public {
        assertEq(address(onboarder), address(executor.sharesOnboarder()));

        address newSharesOnboarder = users.gwart;

        // Only self can set
        vm.prank(users.maliciousUser);
        vm.expectRevert(SelfAuthorized.OnlySelfAuthorized.selector);
        executor.setSharesOnboarder(newSharesOnboarder);

        // Successful
        vm.prank(address(executor));
        vm.expectEmit(false, false, false, true, address(executor));
        emit ITreasurer.SharesOnboarderUpdate(address(onboarder), newSharesOnboarder);
        executor.setSharesOnboarder(newSharesOnboarder);
        assertEq(newSharesOnboarder, address(executor.sharesOnboarder()));

        // Now only gwart can call registerDeposit()
        vm.prank(address(onboarder));
        vm.expectRevert(ITreasurer.OnlySharesOnboarder.selector);
        executor.registerDeposit(
            users.bob,
            IERC20(ONBOARDER.sharesOnboarderInit.quoteAsset),
            ONBOARDER.sharesOnboarderInit.quoteAmount,
            ONBOARDER.sharesOnboarderInit.mintAmount
        );
    }

    function test_SetBalanceSharesManager() public {
        assertEq(address(0), address(executor.balanceSharesManager()));

        address newBalanceSharesManager = erc165Address;

        // Only self can set
        vm.prank(users.maliciousUser);
        vm.expectRevert(SelfAuthorized.OnlySelfAuthorized.selector);
        executor.setBalanceSharesManager(newBalanceSharesManager);

        // IBalanceShareAllocations interface support must be valid
        vm.prank(address(executor));
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC165Verifier.InvalidERC165InterfaceSupport.selector,
                newBalanceSharesManager,
                type(IBalanceShareAllocations).interfaceId
            )
        );
        executor.setBalanceSharesManager(newBalanceSharesManager);

        // Success
        newBalanceSharesManager = address(balanceSharesSingleton);
        vm.prank(address(executor));
        vm.expectEmit(false, false, false, true, address(executor));
        emit ITreasurer.BalanceSharesManagerUpdate(address(0), newBalanceSharesManager);
        executor.setBalanceSharesManager(newBalanceSharesManager);
        assertEq(newBalanceSharesManager, address(executor.balanceSharesManager()));

        // Enable balance shares
        vm.prank(address(executor));
        executor.enableBalanceShares(false);
        assertEq(true, executor.balanceSharesEnabled());

        // Setting back to address(0) to disable balance shares is also valid
        vm.prank(address(executor));
        vm.expectEmit(false, false, false, true, address(executor));
        emit ITreasurer.BalanceSharesManagerUpdate(newBalanceSharesManager, address(0));
        executor.setBalanceSharesManager(address(0));
        assertEq(address(0), address(executor.balanceSharesManager()));
        assertEq(false, executor.balanceSharesEnabled());
    }

    function test_RevertWhen_RegisterDeposit_IsNotSentFromSharesOnboarder() public {
        assertEq(address(onboarder), address(executor.sharesOnboarder()));

        vm.prank(users.maliciousUser);
        vm.expectRevert(ITreasurer.OnlySharesOnboarder.selector);
        executor.registerDeposit(
            users.bob,
            IERC20(ONBOARDER.sharesOnboarderInit.quoteAsset),
            ONBOARDER.sharesOnboarderInit.quoteAmount,
            ONBOARDER.sharesOnboarderInit.mintAmount
        );
    }

    function test_RevertWhen_ProcessWithdrawal_IsNotSentFromToken() public {
        assertEq(address(token), executor.token());

        IERC20[] memory assets;
        vm.prank(users.maliciousUser);
        vm.expectRevert(ITreasurer.OnlyToken.selector);
        executor.processWithdrawal(users.bob, users.bob, 0, 0, assets);
    }
}
