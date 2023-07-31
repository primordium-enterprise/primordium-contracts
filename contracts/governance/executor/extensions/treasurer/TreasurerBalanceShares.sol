// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../Treasurer.sol";
import "contracts/governance/utils/BalanceShares.sol";

abstract contract TreasurerBalanceShares is Treasurer {

    using BalanceShares for BalanceShares.BalanceShare;
    BalanceShares.BalanceShare private _balanceShares;

    // The treasury balance accessible to the DAO (some funds may be allocated to BalanceShares)
    uint256 _treasuryBalance;


}