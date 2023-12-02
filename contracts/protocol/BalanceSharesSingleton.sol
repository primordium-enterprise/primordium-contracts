// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BalanceSharesStorage} from "./balanceShares/BalanceSharesStorage.sol";
import {BalanceSharesProcessing} from "./balanceShares/BalanceSharesProcessing.sol";
import {BalanceSharesAccounts} from "./balanceShares/BalanceSharesAccounts.sol";
import {BalanceSharesWithdrawals} from "./balanceShares/BalanceSharesWithdrawals.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BasisPoints} from "contracts/libraries/BasisPoints.sol";

/**
 * @title A singleton contract for clients to manage account shares (in basis points) for ETH/ERC20 assets.
 *
 * @author Ben Jett - @BCJdevelopment
 *
 * @dev This singleton allows any client to create balance shares with one or more account shares for each balance
 * share. Each account share is denoted in basis points.
 *
 * The main point of this singleton is to significantly reduce gas costs for a protocol's users by releasing assets to
 * account share recipients in batch withdrawals. A client only needs to specify a balance share ID, for which they can
 * setup any account shares they choose, and add balances to the balance share to be withdrawn by the individual account
 * share recipients at any point in time.
 *
 * The internal accounting of this contract also allows a client to make updates to a balance share (such as
 * adding/removing account shares, updating the BPS for an account, etc.) at any point in time, and account recipients
 * will still be able to withdraw their pro rata claim to the accumulated balance share assets at any point in time.
 *
 * A hypothetical example: 4 accounts need to each receive 5% of the deposit amount for an on-chain mint. Rather than
 * paying huge gas costs to send 5% of the deposit amount to 4 different accounts every time asset(s) are minted, the
 * minting contract creates a new balance share ID for deposits, adds the 4 accounts with 5% each, and then sends 20% of
 * the deposit amount for each mint transaction to this contract. Then, each individual account recipient can process a
 * batch withdrawal of their claim to the accumulated balance share assets at any point in time.
 *
 * Account share recipients can also give permissions to other accounts (or open permissions to any account) to process
 * withdrawals on their behalf (still sending the assets to their own account).
 *
 * As a final dev note, this contract uses mappings instead of arrays to store checkpoints, because the author of this
 * contract has storage collision paranoia. There are gas optimized function helpers to access some of these mapping
 * values, but changing the ordering of any of the mappings in storage will result in errors with these functions.
 */
contract BalanceSharesSingleton is
    BalanceSharesAccounts,
    BalanceSharesWithdrawals,
    BalanceSharesProcessing,
{

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // /**
    //  * @dev Approve the provided list of addresses to initiate withdrawal on the account. Approve address(0) to allow
    //  * anyone.
    //  */
    // function approveAddressesForWithdrawal(
    //     BalanceShare storage _self,
    //     address account,
    //     address[] calldata approvedAddresses
    // ) internal {
    //     for (uint256 i = 0; i < approvedAddresses.length;) {
    //         _self._accountWithdrawalApprovals[account][approvedAddresses[i]] = true;
    //         unchecked { ++i; }
    //     }
    // }

    // /**
    //  * @dev Un-approve the provided list of addresses for initiating withdrawals on the account.
    //  */
    // function unapproveAddressesForWithdrawal(
    //     BalanceShare storage _self,
    //     address account,
    //     address[] calldata unapprovedAddresses
    // ) internal {
    //     for (uint256 i = 0; i < unapprovedAddresses.length;) {
    //         _self._accountWithdrawalApprovals[account][unapprovedAddresses[i]] = false;
    //         unchecked { ++i; }
    //     }
    // }

    // /**
    //  * @dev A function for changing the address that an account receives its shares to. This is only callable by the
    //  * account owner. A list of approved addresses for withdrawal can be provided.
    //  *
    //  * Note that by default, if the address(0) was approved (meaning anyone can process a withdrawal to the account),
    //  * then address(0) will be approved for the new account address as well.
    //  *
    //  * @param account The address for the current account share (which must be msg.sender)
    //  * @param newAccount The new address to copy the account share over to.
    //  * @param approvedAddresses A list of addresses to be approved for processing withdrawals to the account receiver.
    //  */
    // function changeAccountAddress(
    //     BalanceShare storage _self,
    //     address account,
    //     address newAccount,
    //     address[] calldata approvedAddresses
    // ) internal {
    //     if (msg.sender != account) revert Unauthorized();
    //     if (newAccount == address(0)) revert InvalidAddress(newAccount);
    //     // Copy it over
    //     _self._accounts[newAccount] = _self._accounts[account];
    //     // Zero out the old account
    //     delete _self._accounts[account];

    //     // Approve addresses
    //     approveAddressesForWithdrawal(_self, newAccount, approvedAddresses);

    //     if (_self._accountWithdrawalApprovals[account][address(0)]) {
    //         _self._accountWithdrawalApprovals[newAccount][address(0)] = true;
    //     }
    // }

    // /**
    //  * @dev The total basis points sum for all currently active account shares.
    //  * @return totalBps An integer representing the total basis points sum. 1 basis point = 0.01%
    //  */
    // function totalBps(
    //     BalanceShare storage _self
    // ) internal view returns (uint256) {
    //     uint256 length = _self._balanceChecks.length;
    //     return length > 0 ?
    //         _self._balanceChecks[length - 1].totalBps :
    //         0;
    // }

    // /**
    //  * @dev Returns a bool indicating whether or not the address is approved for withdrawal on the specified account.
    //  */
    // function isAddressApprovedForWithdrawal(
    //     BalanceShare storage _self,
    //     address account,
    //     address address_
    // ) internal view returns (bool) {
    //     return _self._accountWithdrawalApprovals[account][address_];
    // }

    // /**
    //  * @dev Returns the following details (in order) for the specified account:
    //  * - bps
    //  * - createdAt
    //  * - removableAt
    //  * - lastWithdrawnAt
    //  */
    // function accountDetails(
    //     BalanceShare storage _self,
    //     address account
    // ) internal view returns (uint256, uint256, uint256, uint256) {
    //     AccountShare storage accountShare = _self._accounts[account];
    //     return (
    //         accountShare.bps,
    //         accountShare.createdAt,
    //         accountShare.removableAt,
    //         accountShare.lastWithdrawnAt
    //     );
    // }

}