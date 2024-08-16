// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ITreasury} from "src/executor/interfaces/ITreasury.sol";
import {ISharesToken} from "src/token/interfaces/ISharesToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISharesOnboarder {
    struct SharesOnboarderInit {
        address treasury;
        address quoteAsset;
        uint128 quoteAmount;
        uint128 mintAmount;
        uint256 fundingBeginsAt;
        uint256 fundingEndsAt;
    }

    struct SharePrice {
        uint128 quoteAmount; // Minimum amount of quote asset tokens required to mint {mintAmount} amount of votes.
        uint128 mintAmount; // Number of votes that can be minted per {quoteAmount} count of quote asset.
    }

    /**
     * @notice Emitted when the quote asset contract address is updated.
     * @param oldQuoteAsset The previous quote asset contract address.
     * @param newQuoteAsset The new quote asset contract address.
     */
    event QuoteAssetChange(address oldQuoteAsset, address newQuoteAsset);

    /**
     * @notice Emitted when the treasury contract address is updated.
     * @param oldTreasury The previous treasury contract address.
     * @param newTreasury The new treasury contract address.
     */
    event TreasuryChange(address oldTreasury, address newTreasury);

    /**
     * Emitted when a funding period parameter is updated.
     * @param oldFundingBeginsAt The old timestamp for when deposits become available.
     * @param newFundingBeginsAt The new timestamp for when deposits become available.
     * @param oldFundingEndsAt The old timestamp for when deposits become unavailable.
     * @param newFundingEndsAt The new timestamp for when depsoits become unavailable.
     */
    event FundingPeriodChange(
        uint256 oldFundingBeginsAt, uint256 newFundingBeginsAt, uint256 oldFundingEndsAt, uint256 newFundingEndsAt
    );

    /**
     * @notice Emitted when the tokenPrice is updated.
     * @param oldQuoteAmount Previous numerator before the update.
     * @param newQuoteAmount The new minimum amount of base asset tokens required to mint {denominator} amount of votes.
     * @param oldMintAmount The previous denominator before the update.
     * @param newMintAmount The new number of votes that can be minted per {numerator} count of base asset.
     */
    event SharePriceChange(
        uint256 oldQuoteAmount, uint256 newQuoteAmount, uint256 oldMintAmount, uint256 newMintAmount
    );

    /**
     * @notice Emitted when a deposit is made and tokens are minted.
     * @param account The account address that votes were minted to.
     * @param amountDeposited The amount of the base asset transferred to the Executor as a deposit.
     * @param votesMinted The amount of vote tokens minted to the account.
     * @param depositor The account that deposited the quote asset.
     */
    event Deposit(address indexed account, uint256 amountDeposited, uint256 votesMinted, address depositor);

    /**
     * Emitted when the admin status of an address is updated.
     * @param account The address being updated.
     * @param oldExpiresAt The previous expiration timestamp for the admin status of the account.
     * @param newExpiresAt The new expiration timestmap for the admin status of the account.
     */
    event AdminStatusChange(address indexed account, uint256 oldExpiresAt, uint256 newExpiresAt);

    /**
     * Emitted when an admin pauses deposits.
     * @param admin The address of the admin who paused the deposits.
     */
    event AdminPausedFunding(address indexed admin);

    error InvalidTreasuryAddress(address treasury);
    error TreasuryInterfaceNotSupported(address treasury);
    error QuoteAssetInterfaceNotSupported(address quoteAsset);
    error CannotSetQuoteAssetToSelf();
    error FundingIsNotActive();
    error InvalidDepositAmount();
    error InvalidPermitSpender(address providedSpender, address correctSpender);
    error TokenSalesNotAvailableYet(uint256 tokenSaleBeginsAt);
    error InvalidDepositAmountMultiple();
    error TokenPriceTooLow();

    /**
     * Returns the address for the treasury that processes deposits and withdrawals (most-likely the business executor
     * contract).
     */
    function treasury() external view returns (ITreasury);

    /**
     * Sets the address of the treasury to register deposits and process withdrawals.
     * @notice Only the owner can update the treasury address.
     */
    function setTreasury(address newTreasury) external;

    /**
     * Gets the admin status for the account. The owning contract can approve "admin" accounts that will have the
     * ability to pause deposits by expiring the funding period. This can enable faster protectionary measures against a
     * business's permissionless funding in the case that the owner is a business executor that does not have the
     * ability to take immediate protectionary actions because of governance delays.
     * @param account The address of the account to check.
     * @return isAdmin True if the account is currently a valid admin.
     * @return expiresAt The timestamp at which this account's admin status expires.
     */
    function adminStatus(address account) external view returns (bool isAdmin, uint256 expiresAt);

    /**
     * Sets the admin expirations for the provided accounts. To disable an account's admin status, simply set the
     * expiresAt timestamp to 0.
     * @notice This is an owner-only operation.
     * @param accounts The list of accounts to update
     * @param expiresAts The respective list of timestamps for each account's admin-status to expire.
     */
    function setAdminExpirations(address[] memory accounts, uint256[] memory expiresAts) external;

    /**
     * Returns the address of the quote asset contract, which is the ERC-20 token used for deposits.
     */
    function quoteAsset() external view returns (IERC20 _quoteAsset);

    /**
     * Sets the address of the quote asset contract.
     * @param newQuoteAsset The new quote asset contract address.
     * @notice Only the owner can update the quote asset address.
     */
    function setQuoteAsset(address newQuoteAsset) external;

    /**
     * Returns true if deposits are currently allowed.
     * @notice Shares can only be minted up to the maxSupply(), so if the max supply is already in circulation, shares
     * may not be mintable even though funding is active.
     */
    function isFundingActive() external view returns (bool fundingActive);

    /**
     * Returns the current funding period timestamps.
     * @return fundingBeginsAt The timestamp when funding opens. Max timestamp is
     * @return fundingEndsAt The timestamp when funding closes.
     */
    function fundingPeriods() external view returns (uint256 fundingBeginsAt, uint256 fundingEndsAt);

    /**
     * An owner-only operation to update the funding periods.
     * @notice For either timestamp parameter, passing a value of zero in the function call will leave the current
     * timestamp value unchanged. This is for convenience when updating a single value. Therefore, neither value can be
     * explicitly set to a value of zero.
     * @param newFundingBeginsAt The updated timestamp for funding to be opened. Max is type(uint48).max.
     * @param newFundingEndsAt The new timestamp for funding to be closed. Max is type(uint48).max.
     */
    function setFundingPeriods(uint256 newFundingBeginsAt, uint256 newFundingEndsAt) external;

    /**
     * Pauses funding by setting the funding ends at timestamp to the current block timestamp minus 1.
     * @notice Only the owner or admins can pause funding.
     */
    function pauseFunding() external;

    /**
     * Returns the quote amount and the mint amount of the share price.
     * @notice Because the decimals value can be different for every ERC20 token, the decimals should be taken into
     * account when representing the human-readable amounts as a ratio of quote asset to vote tokens.
     * @return quoteAmount The amount of quote asset tokens required to mint {mintAmount} of vote shares.
     * @return mintAmount The amount of vote shares minted for every {quoteAmount} of quote asset tokens.
     */
    function sharePrice() external view returns (uint128 quoteAmount, uint128 mintAmount);

    /**
     * Public function to update the share price.
     * @notice Only the owner can make an update to the share price.
     * @param newQuoteAmount The new quoteAmount value (the amount of quote asset required for {mintAmount} amount of
     * shares).
     * @param newMintAmount The new mintAmount value (the amount of shares minted for every {quoteAmount} amount of the
     * quote asset).
     */
    function setSharePrice(uint256 newQuoteAmount, uint256 newMintAmount) external;

    /**
     * Allows exchanging the depositAmount of quote asset for vote shares (if shares are currently available).
     * @param account The recipient account address to receive the newly minted share tokens.
     * @param depositAmount The amount of the quote asset being deposited by the msg.sender. Will mint
     * {sharePrice.mintAmount} votes for every {sharePrice.quoteAmount} amount of quote asset tokens. The depositAmount
     * must be an exact multiple of the {sharePrice.quoteAmount}. The  depositAmount also must match the msg.value if
     * the current quoteAsset is the native chain currency (address(0)).
     * @return totalMintAmount The amount of vote share tokens minted to the account.
     */
    function depositFor(address account, uint256 depositAmount) external payable returns (uint256 totalMintAmount);

    /**
     * Same as the {depositFor} function, but uses the msg.sender as the recipient of the newly minted shares.
     */
    function deposit(uint256 depositAmount) external payable returns (uint256 totalMintAmount);

    /**
     * A deposit function using the ERC-20 "permit" on the quote asset contract to approve and deposit the funds
     * in a single transaction (if supported by the ERC20 quote asset).
     * @param owner The address of the account to spend the ERC-20 quote asset from.
     * @param spender MUST BE equal to the address of this SharesOnboarder contract.
     * @param value The amount of the ERC-20 to spend.
     * @param deadline The deadline for the permit function.
     * @param v The "v" signature parameter.
     * @param r The "r" signature parameter.
     * @param s The "s" signature parameter.
     */
    function depositWithPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        returns (uint256 totalMintAmount);
}
