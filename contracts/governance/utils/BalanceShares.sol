// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

uint constant MAX_BPS = 10_000;

library BalanceShares {

    struct BalanceShare {
        uint256 _totalBps; // Tracks the current total basis points for all accounts currently receiving balance shares
        uint256[] _balances;
        mapping(address => AccountShare) _accounts;
    }

    struct AccountShare {
        uint bps; // The basis points share of this account
        uint removableAt; // A timestamp (in UTC seconds) at which the revenue share can be removed by the DAO
        uint startIndex;
        uint endIndex;
        uint lastPulledIndex;
        uint lastPulledBalance;
    }

    struct NewAccountShare {
        address account;
        uint bps;
        uint removableAt;
        uint endIndex;
    }

    function addAccountShares(
        BalanceShare storage self,
        NewAccountShare[] memory newAccountShares
    ) internal {
        require(newAccountShares.length > 0);

        // Adding a new balance index
        uint length = self._balances.length;
        if (length == 0 || self._balances[length - 1] > 0) {
            self._balances.push(0);
            length += 1;
        }
        uint currentBalancesIndex = length - 1;

        // Loop through accounts and track changes
        uint totalBps = self._totalBps;
        for (uint i = 0; i < newAccountShares.length;) {
            NewAccountShare memory nas = newAccountShares[i];
            totalBps += nas.bps;
            self._accounts[nas.account] = AccountShare({
                bps: nas.bps,
                removableAt: nas.removableAt,
                startIndex: currentBalancesIndex,
                endIndex: nas.endIndex,
                lastPulledIndex: currentBalancesIndex,
                lastPulledBalance: 0
            });
            unchecked {
                i++;
            }
        }

        require(totalBps <= MAX_BPS);
        self._totalBps = totalBps;
    }

}