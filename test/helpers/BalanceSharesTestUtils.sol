// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {BalanceShareIds} from "src/common/BalanceShareIds.sol";

contract BalanceSharesTestUtils is BaseTest, BalanceShareIds {
    uint256 defaultShareBPS;

    function _setupDefaultBalanceShares() internal {
        defaultShareBPS = 1000; // 10%

        address[] memory accounts = new address[](1);
        uint256[] memory basisPoints = new uint256[](1);
        accounts[0] = users.balanceSharesReceiver;
        basisPoints[0] = defaultShareBPS;

        vm.startPrank(address(executor));
        executor.setBalanceSharesManager(address(balanceSharesSingleton));
        executor.enableBalanceShares(false);
        balanceSharesSingleton.setAccountSharesBps(DEPOSITS_ID, accounts, basisPoints);
        balanceSharesSingleton.setAccountSharesBps(DISTRIBUTIONS_ID, accounts, basisPoints);
        vm.stopPrank();
    }

    /**
     * @dev Should be called before any balance share allocations are expected to be run, as this will ensure the
     * remainder calculation is correctly predicted ahead of time.
     */
    function _expectedTreasuryBalanceShareAllocation(
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncrease
    )
        internal
        view
        returns (uint256 expectedAllocation)
    {
        if (executor.balanceSharesManager() != address(0) && executor.balanceSharesEnabled()) {
            (expectedAllocation,) = balanceSharesSingleton.checkBalanceShareAllocationWithRemainder(
                address(executor), balanceShareId, asset, balanceIncrease
            );
        }
    }
}
