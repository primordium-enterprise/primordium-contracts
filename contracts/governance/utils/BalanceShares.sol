// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";

uint constant MAX_BPS = 10_000;

library BalanceShares {

    struct BalanceShare {
        uint256 _totalBps; // Tracks the current total basis points for all accounts currently receiving balance shares
        uint256[] _balances;
        mapping(address => AccountShare) _accounts;
        mapping(address => mapping(address => bool)) _accountApprovals;
    }

    struct AccountShare {
        uint16 bps; // The basis points share of this account
        uint40 createdAt; // A timestamp indicating when this account share was created
        uint40 removableAt; // A timestamp (in UTC seconds) at which the revenue share can be removed by the DAO
        uint40 lastWithdrawnAt; // A timestamp (in UTC seconds) at which the revenue share was last withdrawn
        uint40 startIndex;
        uint40 endIndex;
        uint40 lastBalanceIndex;
        uint256 lastBalance;
    }

    struct NewAccountShare {
        address account;
        uint bps;
        uint removableAt;
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
        uint40 currentBalancesIndex = SafeCast.toUint40(length) - 1; // Cache current balances index

        // Loop through accounts and track changes
        uint totalBps = self._totalBps;
        uint40 currentTimestamp = uint40(block.timestamp); // Cache timestamp in memory to save gas
        for (uint i = 0; i < newAccountShares.length;) {
            NewAccountShare memory nas = newAccountShares[i];
            totalBps += nas.bps;
            self._accounts[nas.account] = AccountShare({
                bps: SafeCast.toUint16(nas.bps),
                createdAt: currentTimestamp,
                removableAt: SafeCast.toUint40(nas.removableAt),
                lastWithdrawnAt: currentTimestamp,
                startIndex: currentBalancesIndex,
                endIndex: 0,
                lastBalanceIndex: currentBalancesIndex,
                lastBalance: 0
            });
            unchecked {
                i++;
            }
        }

        require(totalBps <= MAX_BPS);
        self._totalBps = totalBps;
    }

}