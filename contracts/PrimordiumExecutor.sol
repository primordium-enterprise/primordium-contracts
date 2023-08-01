// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "./governance/executor/extensions/treasurer/TreasurerETH.sol";
import "./governance/executor/extensions/treasurer/TreasurerBalanceSharesETH.sol";

contract PrimordiumExecutor is Executor, TreasurerBalanceSharesETH {

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
    ) internal virtual override(Executor, TreasurerBalanceSharesETH) {
        super._beforeExecute(target, value, data);
    }

}