// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";

uint constant MAX_BPS = 10_000; // Max total BPS (1 basis point == 0.01%, which is 1 / 10_000)

library BalanceShares {

    struct BalanceShare {
        BalanceCheck[] _balanceChecks; // New balanceCheck pushed every time totalBps changes, or when balance overflow occurs, max length is type(uint40).max
        mapping(address => AccountShare) _accounts;
        mapping(address => mapping(address => bool)) _accountApprovals;
    }

    struct BalanceCheck {
        uint16 totalBps; // Tracks the totalBps among all balance shares for this checkpoint
        uint240 balance; // The balance sum to be shared among receiving accounts for this checkpoint, only increases
    }

    struct AccountShare {
        uint16 bps; // The basis points share of this account
        uint40 createdAt; // A timestamp indicating when this account share was created
        uint40 removableAt; // A timestamp (in UTC seconds) at which the revenue share can be removed by the DAO
        uint40 lastWithdrawnAt; // A timestamp (in UTC seconds) at which the revenue share was last withdrawn
        uint40 startIndex; // Balance index at which this account share starts participating
        uint40 endIndex; // Where this account finished participating
        uint40 lastBalanceIndex; // The last balanceCheck index that was withdrawn from
        uint256 lastBalance; // The balance of balanceChecks[lastBalanceIndex] when it was last withdrawn
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

        // Initialize the lastBalanceCheck
        BalanceCheck memory lastBalanceCheck = BalanceCheck(0, 0);

        // Get startIndex of the nextBalanceCheck (assumed to be equal to length since we are pushing a new balanceCheck)
        uint startIndex = self._balanceChecks.length;

        // If length is greater than zero, then copy the last array element to the nextBalanceCheck
        if (startIndex > 0) {
            lastBalanceCheck = self._balanceChecks[startIndex - 1];
            // If the balance of the last element is zero, then we plan to just overwrite this checkpoint
            if (lastBalanceCheck.balance == 0) {
                startIndex -= 1;
            }
        } else {
            // If length not greater than zero, initialize the first element
            self._balanceChecks.push(lastBalanceCheck);
        }

        // Cache as uint40 for loop below, SafeCast ensures array length is no larger than type(uint40).max
        uint40 startIndexUint40 = SafeCast.toUint40(startIndex);

        // Loop through accounts and track BPS changes
        uint addToTotalBps = 0;
        uint40 currentTimestamp = uint40(block.timestamp); // Cache timestamp in memory to save gas in loop
        for (uint i = 0; i < newAccountShares.length;) {
            NewAccountShare memory nas = newAccountShares[i];
            addToTotalBps += nas.bps; // We don't verify the BPS amount here, because total will be verified below
            self._accounts[nas.account] = AccountShare({
                bps: SafeCast.toUint16(nas.bps),
                createdAt: currentTimestamp,
                removableAt: SafeCast.toUint40(nas.removableAt),
                lastWithdrawnAt: currentTimestamp,
                startIndex: startIndexUint40,
                endIndex: 0,
                lastBalanceIndex: startIndexUint40,
                lastBalance: 0
            });
            unchecked {
                i++;
            }
        }

        // Calculate the new totalBps, and make sure it is valid
        uint newTotalBps = lastBalanceCheck.totalBps + addToTotalBps;
        require(newTotalBps <= MAX_BPS);

        // Push a new balance check (or just overwrite the bps if the balance of the last check is still zero)
        if (lastBalanceCheck.balance > 0) {
            self._balanceChecks.push(BalanceCheck(uint16(newTotalBps), 0));
        } else {
            self._balanceChecks[startIndex].totalBps = uint16(newTotalBps);
        }

    }

}