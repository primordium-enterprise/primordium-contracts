// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ITreasury} from "src/executor/interfaces/ITreasury.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

interface ISharesManager is IERC6372 {
    event QuoteAssetChange(address oldQuoteAsset, address newQuoteAsset);

    event TreasuryChange(address oldTreasury, address newTreasury);

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
     * @notice Emitted when the max supply of votes is updated.
     * @param oldMaxSupply The previous max supply.
     * @param newMaxSupply The new max supply.
     */
    event MaxSupplyChange(uint256 oldMaxSupply, uint256 newMaxSupply);

    /**
     * @notice Emitted when a deposit is made and tokens are minted.
     * @param account The account address that votes were minted to.
     * @param amountDeposited The amount of the base asset transferred to the Executor as a deposit.
     * @param votesMinted The amount of vote tokens minted to the account.
     */
    event Deposit(address indexed account, uint256 amountDeposited, uint256 votesMinted);

    /**
     * @notice Emitted when a withdrawal is made and tokens are burned.
     * @param account The account address that votes were burned for.
     * @param receiver The receiver address that the withdrawal was sent to.
     * @param totalSharesBurned The amount of vote tokens burned from the account.
     * @param tokens The tokens withdrawn.
     */
    event Withdrawal(address indexed account, address receiver, uint256 totalSharesBurned, IERC20[] tokens);

    event AdminStatusChange(address indexed account, uint256 oldExpiresAt, uint256 newExpiresAt);

    event AdminPausedFunding(address indexed admin);

    error InvalidTreasuryAddress(address treasury);
    error TreasuryInterfaceNotSupported(address treasury);
    error QuoteAssetInterfaceNotSupported(address quoteAsset);
    error CannotSetQuoteAssetToSelf();
    error MaxSupplyTooLarge(uint256 max);
    error FundingIsNotActive();
    error InvalidDepositAmount();
    error InvalidPermitSpender(address providedSpender, address correctSpender);
    error TokenSalesNotAvailableYet(uint256 tokenSaleBeginsAt);
    error InvalidDepositAmountMultiple();
    error TokenPriceTooLow();
    error WithdrawFromZeroAddress();
    error WithdrawToZeroAddress();
    error WithdrawAmountInvalid();
    // error RelayDataToExecutorNotAllowed();
    // error RelayTransferFromNotAllowed();

    /**
     * Returns the address for the treasury that processes deposits and withdrawals (usually the DAO executor contract).
     * @return _treasury
     */
    function treasury() external view returns (ITreasury _treasury);

    /**
     * Sets the address of the treasury to register deposits and process withdrawals.
     * @notice Only the owner can update the treasury address.
     */
    function setTreasury(address newTreasury) external;

    /**
     * Mints vote shares to an account.
     * @notice Only the owner can mint shares. Shares can be otherwise minted through the deposit functionality.
     * @param account The address to receive the newly minted shares.
     * @param amount The amount of vote shares to mint.
     */
    function mint(address account, uint256 amount) external;

    /**
     * The current max supply of vote shares available for minting.
     */
    function maxSupply() external view returns (uint256 _maxSupply);

    /**
     * Function to update the max supply of vote tokens available to be minted by deposits during active funding.
     * @notice Only the owner can update the max supply.
     * @notice The max supply can be set below the total supply of tokens.
     * @param newMaxSupply The new max supply. Must be no greater than type(uint224).max.
     */
    function setMaxSupply(uint256 newMaxSupply) external;

    /**
     * Gets the admin status for the account. The owning contract can approve "admin" accounts that will have the
     * ability to pause deposits by expiring the funding period. This can enable faster protectionary measures against a
     * DAO's permissionless funding in the case that the owner is a DAO executor that does not have the ability to take
     * immediate protectionary actions.
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

    function quoteAsset() external view returns (IERC20 _quoteAsset);
    function setQuoteAsset(address newQuoteAsset) external;
    function setQuoteAssetAndCheckInterfaceSupport(address newQuoteAsset) external;

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

    /// Function to make a deposit, and have votes minted to the supplied account
    function depositFor(address account, uint256 depositAmount) external payable returns (uint256 totalMintAmount);

    /// Function to make a deposit and have votes minted to the msg.sender
    function deposit(uint256 depositAmount) external payable returns (uint256 totalMintAmount);

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

    /**
     * Withdraw the supplied amount of tokens, with the pro-rata amount of the base asset sent from the treasury to the
     * receiver
     */
    function withdrawTo(
        address receiver,
        uint256 amount,
        IERC20[] calldata tokens
    )
        external
        returns (uint256 totalSharesBurned);

    /**
     * Withdraw the supplied amount of tokens, with the pro-rata amount of the base asset sent from the treasury to the
     * msg.sender
     */
    function withdraw(uint256 amount, IERC20[] calldata tokens) external returns (uint256 totalSharesBurned);

    function withdrawToBySig(
        address owner,
        address receiver,
        uint256 amount,
        IERC20[] calldata tokens,
        uint256 deadline,
        bytes memory signature
    )
        external
        returns (uint256 totalSharesBurned);
}
