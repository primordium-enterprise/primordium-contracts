// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "./TreasurerERC20.sol";
import "./TreasurerBalanceShares.sol";

abstract contract TreasurerBalanceSharesERC20 is TreasurerERC20, TreasurerBalanceShares {

    /**
     * @dev IMPORTANT to return the TreasurerBalanceShares function, as this is where BalanceShares internal accounting
     * occurs
     */
    function _treasuryBalance() internal view virtual override(TreasurerERC20, TreasurerBalanceShares) returns (uint256) {
        return TreasurerBalanceShares._treasuryBalance();
    }

    // function _beforeExecute(address target, uint256 value, bytes calldata data) internal virtual override {
    //     super._beforeExecute(target, value, data);
    //     if (value > 0) {
    //         // UPDATE BALANCE AND THEN ADJUST BASED ON ETH VALUE, DON'T ALLOW IF MORE THAN BALANCE
    //     }
    // }

    function _beforeExecute(
        address target,
        uint256 value,
        bytes calldata data
    ) internal virtual override(Executor, TreasurerBalanceShares) {
        super._beforeExecute(target, value, data);
    }

    /**
     * @dev Override to prevent invalid base asset operations, and to return the amount of base asset being transferred
     * (or zero if none is being transferred).
     *
     * NOTE: ERC20 base asset operations are restricted to only:
     * - transfer(address to, uint256 amount)
     * - transferFrom(address from, address to, uint256 amount) WHEN from != address(this)
     *
     * Why? The BalanceShares on the treasury require internal accounting to make sure that the Executor does not spend
     * base assets that are owed to the BalanceShares accounts. If the Executor was allowed to approve another account to
     * spend the base asset on its behalf, then those spends would not be accounted for in the internal revenue
     * accounting process.
     *
     * TODO: Create an additional helper contract for accomodating "approval" behavior.
     */
    function _checkExecutionBalanceTransfer(
        address target,
        uint256 /*value*/,
        bytes calldata data
    ) internal virtual override returns (uint256 balanceBeingTransferred) {
        if (target == address(_baseAsset)) {
            bytes4 selector = bytes4(data);
            if (selector == IERC20.transfer.selector) {
                // Return the balance being transferred
                (,balanceBeingTransferred) = abi.decode(
                    data,
                    (address, uint256)
                );
            } else if (selector == IERC20.transferFrom.selector) {
                // Don't allow calling transferFrom with address(this) as the from address
                (address from,,) = abi.decode(
                    data,
                    (address, address, uint256)
                );
                if (from == address(this)) {
                    revert InvalidBaseAssetOperation();
                }
            } else {
                revert InvalidBaseAssetOperation();
            }
        }
    }

    /**
     * @dev Total treasury balance is measured in ERC20 base asset
     */
    function _getBaseAssetBalance() internal view virtual override returns (uint256) {
        return _baseAsset.balanceOf(address(this));
    }

    function _registerDeposit(
        uint256 depositAmount
    ) internal virtual override(Treasurer, TreasurerBalanceShares) {
        super._registerDeposit(depositAmount);
    }

    function _processWithdrawal(
        address receiver,
        uint256 withdrawAmount
    ) internal virtual override(Treasurer, TreasurerBalanceShares) {
        super._processWithdrawal(receiver, withdrawAmount);
    }

}