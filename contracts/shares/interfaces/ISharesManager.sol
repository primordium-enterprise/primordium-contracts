// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface ISharesManager {

    struct TokenPrice {
        uint128 numerator; // Minimum amount of base asset tokens required to mint {denominator} amount of votes.
        uint128 denominator; // Number of votes that can be minted per {numerator} count of base asset.
    }

    event TreasuryChange(address oldTreasury, address newTreasury);

    /**
     * @notice Emitted when the tokenPrice is updated.
     * @param oldNumerator Previous numerator before the update.
     * @param newNumerator The new minimum amount of base asset tokens required to mint {denominator} amount of votes.
     * @param oldDenominator The previous denominator before the update.
     * @param newDenominator The new number of votes that can be minted per {numerator} count of base asset.
     */
    event TokenPriceChange(
        uint256 oldNumerator,
        uint256 newNumerator,
        uint256 oldDenominator,
        uint256 newDenominator
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
     * @param amountWithdrawn The amount of base asset tokens trånsferred from the Executor as a withdrawal.
     * @param votesBurned The amount of vote tokens burned from the account.
     */
    event Withdrawal(address indexed account, address receiver, uint256 amountWithdrawn, uint256 votesBurned);

    error TreasuryIsNotReady();
    error InvalidTreasuryAddress(address treasury);
    error TreasuryInterfaceNotSupported(address treasury);
    error CannotInitializeBaseAssetToSelf();
    error CannotInitializeTokenPriceToZero();
    error MaxSupplyTooLarge(uint256 max);
    error TokenPriceCannotBeZero();
    error DepositsUnavailable();
    error InvalidDepositAmount();
    error TokenSalesNotAvailableYet(uint256 tokenSaleBeginsAt);
    error InvalidDepositAmountMultiple();
    error TokenPriceTooLow();
    error WithdrawFromZeroAddress();
    error WithdrawToZeroAddress();
    error WithdrawAmountInvalid();
    error RelayDataToExecutorNotAllowed(bytes data);

    /// Function to query the max supply
    function maxSupply() external view returns (uint256);

    /// Function to update the max supply, executor only
    function setMaxSupply(uint256 newMaxSupply) external;

    function quoteAsset() external view returns (IERC20);
    function setQuoteAsset() external;

    function isFundingActive() external view returns (bool fundingActive);
    function fundingPeriods() external view returns (uint256 fundingBeginsAt, uint256 fundingExpiresAt);

    function setFundingBeginsAt(uint256 fundingBeginsAt) external;
    function setFundingExpiresAt(uint256 fundingExpiresAt) external;
    function setFundingPeriods(uint256 fundingBeginsAt, uint256 fundingExpiresAt) external;


    /// Function to query the ERC20 base asset (address(0) for ETH)
    function baseAsset() external view returns (address);

    /// Function to query the current token price
    function tokenPrice() external view returns (uint128, uint128);

    /// Function to update the token price, executor only
    function setTokenPrice(uint256 numerator, uint256 denominator) external;

    /// Returns the current value per token in the existing supply of votes, quoted in the base asset
    function valuePerToken() external view returns (uint256);

    /// Function to make a deposit, and have votes minted to the supplied account
    function depositFor(address account, uint256 depositAmount) external payable returns (uint256);

    /// Function to make a dposit and have votes minted to the msg.sender
    function deposit(uint256 depositAmount) external payable returns(uint256);

    /**
     * Withdraw the supplied amount of tokens, with the pro-rata amount of the base asset sent from the treasury to the
     * receiver
     */
    function withdrawTo(address receiver, uint256 amount) external returns (uint256);

    /**
     * Withdraw the supplied amount of tokens, with the pro-rata amount of the base asset sent from the treasury to the
     * msg.sender
     */
    function withdraw(uint256 amount) external returns (uint256);

}