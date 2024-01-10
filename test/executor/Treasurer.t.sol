// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {BalanceSharesTestUtils} from "test/helpers/BalanceSharesTestUtils.sol";
import {TimelockAvatarTestUtils} from "test/helpers/TimelockAvatarTestUtils.sol";
import {ITreasurer} from "src/executor/interfaces/ITreasurer.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ExecutorV1Harness} from "test/harness/ExecutorV1Harness.sol";
import {IDistributor} from "src/executor/interfaces/IDistributor.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TreasurerTest is BalanceSharesTestUtils, TimelockAvatarTestUtils {
    using ERC165Checker for address;

    function setUp() public virtual override(BaseTest, TimelockAvatarTestUtils) {
        super.setUp();
    }

    function test_DistributorCreate2Address() public {
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                distributorImpl, abi.encodeCall(IDistributor.setUp, (address(token), EXECUTOR.distributionClaimPeriod))
            )
        );

        assertEq(
            address(executor.distributor()),
            address(
                uint160(
                    uint256(keccak256(abi.encodePacked(hex"ff", address(executor), uint256(0), keccak256(bytecode))))
                )
            )
        );

        assertTrue(address(executor.distributor()).supportsInterface(type(IDistributor).interfaceId));
    }

    function test_InitBalanceShares() public {
        executor = ExecutorV1Harness(payable(address(new ERC1967Proxy(executorImpl, ""))));
        vm.label({account: address(executor), newLabel: "NewExecutor"});

        bytes memory timelockAvatarInitParams = abi.encode(EXECUTOR.minDelay, defaultModules);

        // Setup the default balance shares
        (address[] memory accounts, uint256[] memory basisPoints) = _getDefaultBalanceShareAccounts();
        bytes[] memory balanceShareInitCalldatas = new bytes[](2);
        balanceShareInitCalldatas[0] =
            abi.encodeCall(balanceSharesSingleton.setAccountSharesBps, (DEPOSITS_ID, accounts, basisPoints));
        balanceShareInitCalldatas[1] =
            abi.encodeCall(balanceSharesSingleton.setAccountSharesBps, (DISTRIBUTIONS_ID, accounts, basisPoints));

        address balanceSharesManager = address(balanceSharesSingleton);

        bytes memory treasurerInitParams = abi.encode(
            address(token),
            address(onboarder),
            balanceSharesManager,
            balanceShareInitCalldatas,
            type(ERC1967Proxy).creationCode,
            distributorImpl,
            EXECUTOR.distributionClaimPeriod
        );

        // Before setup, should be uninitialized
        assertEq(address(0), address(executor.balanceSharesManager()));

        vm.expectEmit(false, false, false, true, address(executor));
        emit ITreasurer.BalanceSharesManagerUpdate(address(0), balanceSharesManager);
        executor.setUp(timelockAvatarInitParams, treasurerInitParams);

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
}
