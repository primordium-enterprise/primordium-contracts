// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../VotesProvisioner.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

using SafeMath for uint256;

abstract contract ERC20VotesProvisioner is VotesProvisioner {

    constructor(
        Treasurer executor_,
        uint256 maxSupply_,
        TokenPrice memory tokenPrice_,
        IERC20 baseAsset_
    ) VotesProvisioner(executor_, maxSupply_, tokenPrice_, baseAsset_) {
        require(address(baseAsset_) != address(0), "ERC20VotesProvisioner: the address for the baseAsset cannot be address(0)");
    }

    /**
     * @notice Allows exchanging the depositAmount of base asset for votes (if votes are available for purchase).
     * @param account The account address to deposit to.
     * @param depositAmount The amount of the base asset being deposited. Will mint tokenPrice.denominator votes for every
     * tokenPrice.numerator count of base asset tokens.
     * @dev Override to deposit ERC20 base asset in exchange for votes.
     * While this function is marked as "payable" (since it overrides VotesProvisioner), it requires msg.value to be zero.
     * @return Amount of vote tokens minted.
     */
    function depositFor(address account, uint256 depositAmount) public payable virtual override returns(uint256) {
        require(msg.value == 0, "ERC20VotesProvisioner: Cannot accept ETH deposits.");
        return _depositFor(account, depositAmount);
    }

    /**
     * @dev Additional function helper to use permit on the base asset contract to transfer in a single transaction
     * (if supported).
     */
    function depositForWithPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual returns(uint256) {
        require(
            spender == address(this),
            "ERC20VotesProvisioner: deposits using ERC20 permit must set this contract address as the 'spender'"
        );
        IERC20Permit(baseAsset()).permit(
            owner,
            spender,
            value,
            deadline,
            v,
            r,
            s
        );
        return _depositFor(owner, value);
    }

    /**
     * @dev Override to transfer the ERC20 deposit to the Executor, and register on the Executor.
     */
    function _transferDepositToExecutor(address account, uint256 depositAmount) internal virtual override {
        SafeERC20.safeTransferFrom(_baseAsset, account, executor(), depositAmount);
        _getTreasurer().registerDepositERC20(depositAmount);
    }

    /**
     * @dev Override to transfer the ERC20 withdrawal from the Executor.
     */
    function _transferWithdrawalToReceiver(address receiver, uint256 withdrawAmount) internal virtual override {
        _getTreasurer().processWithdrawalERC20(_baseAsset, receiver, withdrawAmount);
    }

    function _treasuryBalance() internal view virtual override returns(uint256) {
        return _baseAsset.balanceOf(executor());
    }

}