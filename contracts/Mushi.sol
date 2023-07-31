// SPDX-License-Identifier: MIT
// Primordium Contracts

import "./governance/token/Votes.sol";
import "./governance/token/extensions/provisioners/VotesProvisionerETH.sol";
import "./governance/token/extensions/provisioners/extensions/PermitWithdraw.sol";
import "./governance/executor/Executor.sol";

pragma solidity ^0.8.10;

string constant TOKEN_NAME = "Primordium";
string constant TOKEN_SYMBOL = "MUSHI";

contract Mushi is PermitWithdraw, VotesProvisionerETH {

    constructor(
        Treasurer executor_,
        uint256 maxSupply_,
        TokenPrice memory tokenPrice_
    )
        ERC20Permit(TOKEN_NAME)
        ERC20Checkpoints(TOKEN_NAME, TOKEN_SYMBOL)
        VotesProvisioner(executor_, maxSupply_, tokenPrice_, IERC20(address(0)))
    {}

}
