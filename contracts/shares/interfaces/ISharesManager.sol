// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ITreasury} from "contracts/executor/interfaces/ITreasury.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface ISharesManager {

    event QuoteAssetChange(address oldQuoteAsset, address newQuoteAsset);

    event TreasuryChange(address oldTreasury, address newTreasury);

    event FundingPeriodChange(
        uint256 oldFundingBeginsAt,
        uint256 newFundingBeginsAt,
        uint256 oldFundingEndsAt,
        uint256 newFundingEndsAt
    );

    /**
     * @notice Emitted when the tokenPrice is updated.
     * @param oldQuoteAmount Previous numerator before the update.
     * @param newQuoteAmount The new minimum amount of base asset tokens required to mint {denominator} amount of votes.
     * @param oldMintAmount The previous denominator before the update.
     * @param newMintAmount The new number of votes that can be minted per {numerator} count of base asset.
     */
    event SharePriceChange(
        uint256 oldQuoteAmount,
        uint256 newQuoteAmount,
        uint256 oldMintAmount,
        uint256 newMintAmount
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
    event Withdrawal(
        address indexed account,
        address receiver,
        uint256 totalSharesBurned,
        IERC20[] tokens
    );

    error InvalidTreasuryAddress(address treasury);
    error TreasuryInterfaceNotSupported(address treasury);
    error CannotSetQuoteAssetToSelf();
    error UnsupportedQuoteAssetInterface();
    error MaxSupplyTooLarge(uint256 max);
    error FundingIsNotActive();
    error InvalidDepositAmount();
    error InvalidPermitSpender(address providedSpender, address correctSpender);
    error QuoteAssetIsNotNativeCurrency(address quoteAsset);
    error TokenSalesNotAvailableYet(uint256 tokenSaleBeginsAt);
    error InvalidDepositAmountMultiple();
    error TokenPriceTooLow();
    error WithdrawFromZeroAddress();
    error WithdrawToZeroAddress();
    error WithdrawAmountInvalid();
    error RelayDataToExecutorNotAllowed(bytes data);

    function treasury() external view returns (ITreasury _treasury);
    function setTreasury() external;

    /// Function to query the max supply
    function maxSupply() external view returns (uint256 _maxSupply);

    /// Function to update the max supply, executor only
    function setMaxSupply(uint256 newMaxSupply) external;

    function quoteAsset() external view returns (IERC20 _quoteAsset);
    function setQuoteAsset(address newQuoteAsset) external;
    function setQuoteAssetAndCheckInterfaceSupport(address newQuoteAsset) external;

    function isFundingActive() external view returns (bool fundingActive);
    function fundingPeriods() external view returns (uint256 fundingBeginsAt, uint256 fundingEndsAt);

    function setFundingBeginsAt(uint256 fundingBeginsAt) external;
    function setFundingEndsAt(uint256 fundingEndsAt) external;
    function setFundingPeriods(uint256 newFundingBeginsAt, uint256 newFundingEndsAt) external;

    /// Function to query the current price per share
    function sharePrice() external view returns (uint128 quoteAmount, uint128 mintAmount);

    /// Function to update the share price, executor only
    function setSharePrice(uint256 quoteAmount, uint256 mintAmount) external;

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
    ) external returns (uint256 totalMintAmount);

    /**
     * Withdraw the supplied amount of tokens, with the pro-rata amount of the base asset sent from the treasury to the
     * receiver
     */
    function withdrawTo(
        address receiver,
        uint256 amount,
        IERC20[] calldata tokens
    ) external returns (uint256 totalSharesBurned);

    /**
     * Withdraw the supplied amount of tokens, with the pro-rata amount of the base asset sent from the treasury to the
     * msg.sender
     */
    function withdraw(uint256 amount, IERC20[] calldata tokens) external returns (uint256 totalSharesBurned);

    function withdrawBySig(
        address owner,
        address receiver,
        uint256 amount,
        IERC20[] calldata tokens,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 totalSharesBurned);

}