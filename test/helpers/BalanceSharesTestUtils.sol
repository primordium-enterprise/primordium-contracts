// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {BalanceShareIds} from "src/common/BalanceShareIds.sol";

contract BalanceSharesTestUtils is BaseTest, BalanceShareIds {
    uint256 defaultBalanceShareBps;

    constructor() {
        defaultBalanceShareBps = 1000; // 10%
    }

    function _setupDefaultBalanceShares() internal {
        _setupDefaultBalanceShares(true); // Defaults to enabling balance shares
    }

    function _setupDefaultBalanceShares(bool enableBalanceShares) internal {
        (address[] memory accounts, uint256[] memory basisPoints) = _getDefaultBalanceShareAccounts();

        vm.startPrank(address(executor));
        executor.setBalanceSharesManager(address(balanceSharesSingleton));
        if (enableBalanceShares) {
            executor.enableBalanceShares(false);
        }
        balanceSharesSingleton.setAccountSharesBps(DEPOSITS_ID, accounts, basisPoints);
        balanceSharesSingleton.setAccountSharesBps(DISTRIBUTIONS_ID, accounts, basisPoints);
        vm.stopPrank();
    }

    function _getDefaultBalanceShareAccounts()
        internal
        view
        returns (address[] memory accounts, uint256[] memory basisPoints)
    {
        accounts = new address[](1);
        basisPoints = new uint256[](1);
        accounts[0] = users.balanceSharesReceiver;
        basisPoints[0] = defaultBalanceShareBps;
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
