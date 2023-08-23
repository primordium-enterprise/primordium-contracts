// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "./executor/extensions/treasurer/TreasurerETH.sol";
import "./executor/extensions/treasurer/TreasurerBalanceShares.sol";

contract PrimordiumExecutor is Executor, TreasurerETH, TreasurerBalanceShares {

    constructor(
        uint256 minDelay,
        address owner,
        VotesProvisioner votes_
    ) Executor(minDelay, owner) Treasurer(votes_) {

    }

    function _beforeExecute(
        address target,
        uint256 value,
        bytes calldata data
    ) internal virtual override(Executor, Treasurer) {
        super._beforeExecute(target, value, data);
    }

    function _treasuryBalance() internal view virtual override(Treasurer, TreasurerBalanceShares) returns(uint256) {
        return TreasurerBalanceShares._treasuryBalance();
    }

    function _registerDeposit(uint256 depositAmount) internal virtual override(TreasurerETH, TreasurerBalanceShares) {
        super._registerDeposit(depositAmount);
    }

}