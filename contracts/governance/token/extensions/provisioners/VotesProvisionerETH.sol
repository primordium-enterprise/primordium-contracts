// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../VotesProvisioner.sol";

abstract contract VotesProvisionerETH is VotesProvisioner {

    constructor() {
        require(address(_baseAsset) == address(0));
    }

    /**
     * @notice Allows exchanging the depositAmount of base asset for votes (if votes are available for purchase).
     * The "depositAmount" parameter is not used.
     * @param account The account address to deposit to.
     * @dev Override to deposit ETH base asset in exchange for votes. Mints tokenPrice.denominator votes for every
     * tokenPrice.numerator amount of Wei.
     * For override compatibility, the "depositAmount" parameter is included, but is not used.
     * @return Amount of vote tokens minted.
     */
    function depositFor(address account, uint256 /*depositAmount*/) public payable virtual override returns(uint256) {
        return _depositFor(account, msg.value);
    }

    /**
     * @dev Additional depositFor function, but ommitting the unused "depositAmount" parameter (since msg.value is used)
     */
    function depositFor(address account) public payable virtual returns(uint256) {
        return _depositFor(account, msg.value);
    }

    /**
     * @dev Additional deposit function, but omitting the unused "depositAmount" parameter (since base asset is ETH)
     */
    function deposit() public payable virtual returns(uint256) {
        return _depositFor(_msgSender(), msg.value);
    }

    /**
     * @dev Override to transfer the ETH deposit to the Executor, and register it on the Executor.
     */

    function _transferDepositToExecutor(address /*account*/, uint256 depositAmount) internal virtual override {
        _getTreasurer().registerDeposit{value: msg.value}(depositAmount);
    }

    /**
     * @dev Override to transfer the ETH withdrawal from the Executor.
     */
    function _transferWithdrawalToReceiver(address receiver, uint256 withdrawAmount) internal virtual override {
        _getTreasurer().processWithdrawal(receiver, withdrawAmount);
    }

    function _treasuryBalance() internal view virtual override returns(uint256) {
        return executor().balance;
    }

}