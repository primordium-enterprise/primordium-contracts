// SPDX-License-Identifier: MIT
// Primordium Contracts

import "./governance/token/Votes.sol";
import "./governance/token/extensions/provisioners/ETHVotesProvisioner.sol";
import "./governance/executor/Executor.sol";

pragma solidity ^0.8.10;

string constant TOKEN_NAME = "Primordium";
string constant TOKEN_SYMBOL = "MUSHI";

contract Mushi is Votes, ETHVotesProvisioner {
    constructor(
        ExecutorVoteProvisions executor_
    )
        ERC20Permit(TOKEN_NAME)
        ERC20Checkpoints(TOKEN_NAME, TOKEN_SYMBOL)
        ETHVotesProvisioner(executor_, TokenPrice(1, 1))
    {}

}
