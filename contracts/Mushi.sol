// SPDX-License-Identifier: MIT
// Primordium Contracts

import "./governance/token/Votes.sol";
import "./governance/Executor.sol";

pragma solidity ^0.8.10;

string constant TOKEN_NAME = "Primordium";
string constant TOKEN_SYMBOL = "MUSHI";

contract Mushi is Votes {

    constructor(
        Executor executor_
    ) ERC20Permit(TOKEN_NAME) ERC20(TOKEN_NAME, TOKEN_SYMBOL) {

    }

}
