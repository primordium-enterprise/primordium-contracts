// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "./governance/executor/extensions/treasurer/TreasurerETH.sol";
import "./governance/executor/extensions/treasurer/TreasurerBalanceShares.sol";

contract PrimordiumExecutor is Executor, TreasurerETH, TreasurerBalanceShares {

    constructor(
        uint256 minDelay,
        address owner,
        VotesProvisioner votes_
    ) Executor(minDelay, owner) Treasurer(votes_) {

    }

    function _registerDeposit(
        uint256 depositAmount
    ) internal virtual override(TreasurerETH, TreasurerBalanceShares) {
        super._registerDeposit(depositAmount);
    }

    function _processWithdrawal(
        address receiver,
        uint256 withdrawAmount
    ) internal virtual override(TreasurerETH, TreasurerBalanceShares) {
        super._processWithdrawal(receiver, withdrawAmount);
    }

}