// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../VotesProvisioner.sol";

abstract contract ETHVotesProvisioner is VotesProvisioner {

    constructor(
        Treasurer executor_,
        TokenPrice memory initialTokenPrice
    ) VotesProvisioner(executor_, initialTokenPrice, IERC20(address(0))) {

    }

    /**
     * @notice Allows exchanging the amount of base asset for votes (if votes are available for purchase). The "amount"
     * parameter is not used.
     * @param account The account address to deposit to.
     * @dev Override to deposit ETH base asset in exchange for votes. Mints tokenPrice.denominator votes for every
     * tokenPrice.numerator amount of Wei.
     * For override compatibility, the "amount" parameter is included, but is not used.
     * @return Amount of vote tokens minted.
     */
    function depositFor(address account, uint256 /*amount*/) public payable virtual override returns(uint256) {
        return _depositFor(account, msg.value);
    }

    /**
     * @dev Additional depositFor function, but ommitting the unused "amount" parameter (since msg.value is used)
     */
    function depositFor(address account) public payable virtual returns(uint256) {
        return _depositFor(account, msg.value);
    }

    /**
     * @dev Additional deposit function, but omitting the unused "amount" parameter (since base asset is ETH)
     */
    function deposit() public payable virtual returns(uint256) {
        return _depositFor(_msgSender(), msg.value);
    }

    /**
     * @dev Override to transfer the ETH deposit to the Executor, and register it on the Executor.
     */

    function _transferDepositToExecutor(address /*account*/, uint256 amount) internal virtual override {
        _getTreasurer().registerDepositEth{value: msg.value}(amount);
    }

    function _treasuryBalance() internal view virtual override returns(uint256) {
        return executor().balance;
    }

}