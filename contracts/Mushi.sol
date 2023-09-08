// SPDX-License-Identifier: MIT
// Primordium Contracts

import "./token/Votes.sol";
import "./token/extensions/provisioners/VotesProvisionerETH.sol";
import "./executor/Executor.sol";

pragma solidity ^0.8.4;

string constant TOKEN_NAME = "Primordium";
string constant TOKEN_SYMBOL = "MUSHI";

contract Mushi is VotesProvisionerETH {

    constructor(
        Treasurer executor_,
        uint256 maxSupply_,
        TokenPrice memory tokenPrice_
    )
        ERC20Permit(TOKEN_NAME)
        ERC20Checkpoints(TOKEN_NAME, TOKEN_SYMBOL)
        VotesProvisioner(
            executor_,
            IERC20(address(0)),
            maxSupply_,
            tokenPrice_,
            block.timestamp,
            block.timestamp + 1
        )
    {}

}
