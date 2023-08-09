// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "../VotesProvisioner.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

using SafeMath for uint256;

abstract contract VotesProvisionerERC20 is VotesProvisioner {

    constructor() {
        require(address(_baseAsset) != address(0), "VotesProvisionerERC20: the address for the baseAsset cannot be address(0)");
    }

    error CannotAcceptETHDeposits();
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
        if (msg.value > 0) revert CannotAcceptETHDeposits();
        return _depositFor(account, depositAmount);
    }

    error InvalidSpender(address providedSpender, address correctSpender);
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
        if (spender != address(this)) revert InvalidSpender(spender, address(this));
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
        _getTreasurer().registerDeposit(depositAmount);
    }

    /**
     * @dev Override to transfer the ERC20 withdrawal from the Executor.
     */
    function _transferWithdrawalToReceiver(address receiver, uint256 withdrawAmount) internal virtual override {
        _getTreasurer().processWithdrawal(receiver, withdrawAmount);
    }

}