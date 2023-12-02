// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BalanceSharesStorage} from "./BalanceSharesStorage.sol";

contract BalanceSharesWithdrawals is BalanceSharesStorage {

    function _getAccountPeriodAssetBalances(
        BalanceShare storage _balanceShare,
        address account,
        address[] memory assets,
        uint256 periodIndex
    ) internal {
        AccountSharePeriod storage _accountSharePeriod = _balanceShare.accounts[account].periods[periodIndex];

        uint256 bps;
        uint256 startBalanceSumIndex;
        uint256 endBalanceSumIndex;

        assembly {
            mstore(0, sload(_accountSharePeriod.slot))
            // bps is first 16 bits
            bps := and(mload(0), MASK_UINT16)
            // startIndex - shift right 16 bits, mask 48 bits
            startBalanceSumIndex := and(shr(0x10, mload(0)), MASK_UINT48)
            // endIndex - shift right 16 + 48 bits, mask 48 bits
            endBalanceSumIndex := and(shr(0x40, mload(0)), MASK_UINT48)
        }

    }
}