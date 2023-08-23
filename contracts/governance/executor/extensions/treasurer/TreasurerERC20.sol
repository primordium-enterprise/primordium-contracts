// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "../Treasurer.sol";

abstract contract TreasurerERC20 is Treasurer {

    constructor() {
        require(address(_baseAsset) != address(0));
    }

    /// @dev Override to return the raw base asset balance of this address with an ERC20 as the base asset
    function _baseAssetBalance() internal view virtual override returns (uint256) {
        return _baseAsset.balanceOf(address(this));
    }

    /// @dev Transfers ERC20 base asset
    function _safeTransferBaseAsset(address to, uint256 amount) internal virtual override {
        SafeERC20.safeTransfer(_baseAsset, to, amount);
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
     * base assets that are owed to the BalanceShares accounts. If the Executor was allowed to approve another account
     * to spend the base asset on its behalf, then those spends would not be accounted for in the internal revenue
     * accounting process.
     *
     * TODO: Create an additional helper contract for accomodating "approval" behavior.
     */
    function _checkExecutionBaseAssetTransfer(
        address target,
        uint256 value,
        bytes calldata data
    ) internal virtual override returns (uint256 balanceBeingTransferred) {
        if (target == address(_baseAsset)) {
            bytes4 selector = bytes4(data);
            if (selector == IERC20.transfer.selector) {
                // Return the balance being transferred
                (,balanceBeingTransferred) = abi.decode(data, (address, uint256));
            } else if (selector == IERC20.transferFrom.selector) {
                // Don't allow calling transferFrom with address(this) as the "from" address
                (address from,,) = abi.decode(data, (address, address, uint256));
                if (from == address(this)) revert InvalidBaseAssetOperation(target, value, data);
            } else {
                revert InvalidBaseAssetOperation(target, value, data);
            }
        }
    }

}