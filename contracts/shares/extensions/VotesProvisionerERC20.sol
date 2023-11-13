// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import "../base/SharesManager.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

using Math for uint256;

abstract contract VotesProvisionerERC20 is SharesManager {

    error CannotInitializeBaseAssetToETH();
    error CannotAcceptETHDeposits();
    error InvalidSpender(address providedSpender, address correctSpender);

    constructor() {
        if (address(_baseAsset) == address(0)) revert CannotInitializeBaseAssetToETH();
    }

    /**
     * @notice Allows exchanging the "depositAmount" of base asset for votes (if votes are available for purchase).
     * The "depositAmount" is transferred from the msg.sender's account, so this contract must be approved to spend at
     * least the "depositAmount" of the ERC20 base asset.
     * @param account The account address to make the deposit for.
     * @param depositAmount The amount of the base asset being deposited. Will mint tokenPrice.denominator votes for
     * every `tokenPrice.numerator` count of base asset tokens.
     * @dev Override to deposit ERC20 base asset in exchange for votes.
     * While this function is marked as "payable" (since it overrides SharesManager), it requires msg.value to be
     * zero.
     * @return Amount of vote tokens minted.
     */
    function depositFor(address account, uint256 depositAmount) public payable virtual override returns(uint256) {
        if (msg.value > 0) revert CannotAcceptETHDeposits();
        return super.depositFor(account, depositAmount);
    }

    /**
     * @dev Additional depositFor function, but ommitting the "account" parameter to make the deposit for the
     * msg.sender.
     */
    function depositFor(uint256 depositAmount) public virtual returns(uint256) {
        return super.depositFor(_msgSender(), depositAmount);
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
        if (spender != address(this)) revert InvalidSpender(spender, address(this));
        IERC20Permit(address(_baseAsset)).permit(
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
    function _transferDepositToExecutor(
        uint256 depositAmount,
        ProvisionMode currentProvisionMode
    ) internal virtual override {
        SafeERC20.safeTransferFrom(_baseAsset, _msgSender(), treasury(), depositAmount);
        _getTreasurer().registerDeposit(baseAsset(), depositAmount, currentProvisionMode);
    }

    /**
     * @dev Override to transfer the ERC20 withdrawal from the Executor.
     */
    function _transferWithdrawalToReceiver(address receiver, uint256 withdrawAmount) internal virtual override {
        _getTreasurer().processWithdrawal(baseAsset(), receiver, withdrawAmount);
    }

}