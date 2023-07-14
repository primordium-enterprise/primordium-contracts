// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../../token/extensions/VotesProvisioner.sol";
import "../Executor.sol";

abstract contract Treasurer is Executor {

    VotesProvisioner internal immutable _votes;

    constructor(
        VotesProvisioner votes_
    ) {
        _votes = votes_;
    }

    function votes() public view returns(address) {
        return address(_votes);
    }

    modifier onlyVotes() {
        require(_msgSender() == address(_votes), "Treasurer: call must come from the _votes contract.");
        _;
    }

    function registerDeposit(uint256 amount) public virtual onlyVotes {
        _registerDeposit(amount);
    }

    function registerDepositEth(uint256 amount) public payable virtual onlyVotes {
        require(msg.value == amount, "Treasurer: depositEth mismatching amount and msg.value");
        _registerDeposit(amount);
    }

    function _registerDeposit(uint256 amount) private {
        // NEED TO IMPLEMENT BALANCE CHECKS
    }

}