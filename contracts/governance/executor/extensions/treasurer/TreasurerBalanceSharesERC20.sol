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

    function _beforeExecute(address target, uint256 value, bytes calldata data) internal virtual override {
        super._beforeExecute(target, value, data);
        if (value > 0) {
            // UPDATE BALANCE AND THEN ADJUST BASED ON ETH VALUE, DON'T ALLOW IF MORE THAN BALANCE
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