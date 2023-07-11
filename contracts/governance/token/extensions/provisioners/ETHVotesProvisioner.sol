// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../VotesProvisioner.sol";

abstract contract ETHVotesProvisioner is VotesProvisioner {

    constructor(
        ExecutorVoteProvisions executor_,
        uint256 initialTokenPrice
    ) VotesProvisioner(executor_, initialTokenPrice, IERC20(address(0))) {

    }

    /**
     * @dev Additional depositFor function, but ommitting the unused "amount" parameter (since base asset is ETH)
     */
    function depositFor(address account) public payable virtual {
        _depositFor(account, msg.value);
    }

    /**
     * @dev Override to deposit ETH base asset in exchange for votes.
     * @notice For override compatibility, the "amount" parameter is included, but is not used.
     */
    function depositFor(address account, uint256 amount) public payable virtual override {
        _depositFor(account, msg.value);
    }

    /**
     * @dev Override to transfer the ETH deposit to the Executor, and register it on the Executor.
     */
    function _transferDepositToExecutor(address account, uint256 amount) internal virtual override {
        _getExecutorVoteProvisions().registerDepositEth{value: msg.value}(amount);
    }


}