// SPDX-License-Identifier: MIT
// Primordium Contracts

import "./governance/token/Votes.sol";
import "./governance/token/extensions/VotesProvisioner.sol";
import "./governance/executor/Executor.sol";

pragma solidity ^0.8.10;

string constant TOKEN_NAME = "Primordium";
string constant TOKEN_SYMBOL = "MUSHI";

contract Mushi is Votes, VotesProvisioner {

    constructor(
        Executor executor_
    )
        ERC20Permit(TOKEN_NAME)
        ERC20(TOKEN_NAME, TOKEN_SYMBOL)
        VotesProvisioner(executor_, 1, IERC20(address(0)))
    {

    }

}
