// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ERC20CheckpointsUpgradeable} from "./ERC20CheckpointsUpgradeable.sol";
import {ERC20VotesUpgradeable} from "./ERC20VotesUpgradeable.sol";
import {ISharesManager} from "../interfaces/ISharesManager.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {ITreasury} from "contracts/executor/interfaces/ITreasury.sol";
import {Ownable1Or2StepUpgradeable} from "contracts/utils/Ownable1Or2StepUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../utils/Math512.sol";

/**
 * @dev Extension of {Votes} to support decentralized DAO formation.
 *
 * Complete with deposit/withraw functionality.
 *
 * Anyone can mint vote tokens in exchange for the DAO's base asset. Any member can withdraw pro rata.
 */
abstract contract SharesManager is ERC20VotesUpgradeable, ISharesManager, Ownable1Or2StepUpgradeable {
    using Math for uint256;
    using SafeCast for *;

    bytes32 private constant WITHDRAW_TYPEHASH = keccak256(
        "Withdraw(address owner,address receiver,uint256 amount,uint256 nonce,uint256 expiry)"
    );

    struct SharePrice {
        uint128 quoteAmount; // Minimum amount of base asset tokens required to mint {mintAmount} amount of votes.
        uint128 mintAmount; // Number of votes that can be minted per {quoteAmount} count of base asset.
    }

    /// @custom:storage-location erc7201:SharesManager.Storage
    struct SharesManagerStorage {
        uint256 _maxSupply;

        // Funding parameters
        ITreasury _treasury;
        uint48 _fundingBeginsAt;
        uint48 _fundingEndsAt;

        /// @dev _sharePrice updates should always go through {_setSharesPrice} to avoid setting price to zero
        SharePrice _sharePrice;

        IERC20 _quoteAsset; // (address(0) for ETH)
    }

    bytes32 private immutable SHARES_MANAGER_STORAGE =
        keccak256(abi.encode(uint256(keccak256("SharesManager.Storage")) - 1)) & ~bytes32(uint256(0xff));

    function _getSharesManagerStorage() private view returns (SharesManagerStorage storage $) {
        bytes32 sharesManagerStorageSlot = SHARES_MANAGER_STORAGE;
        assembly {
            $.slot := sharesManagerStorageSlot
        }
    }

    function __SharesManager_init(
        address owner_,
        address treasury_,
        uint256 maxSupply_,
        address quoteAsset_,
        bool checkQuoteAssetInterface_,
        SharePrice calldata sharePrice_
    ) internal virtual onlyInitializing {
        __Ownable_init(owner_);
        _setTreasury(treasury_);
        _setMaxSupply(maxSupply_);
        _setQuoteAsset(quoteAsset_, checkQuoteAssetInterface_);
        _setSharePrice(sharePrice_.quoteAmount, sharePrice_.mintAmount);
    }

    function treasury() public view virtual returns (ITreasury _treasury) {
        _treasury = _getSharesManagerStorage()._treasury;
    }

    function setTreasury(address newTreasury) external virtual onlyOwner {
        _setTreasury(newTreasury);
    }

    function _setTreasury(address newTreasury) internal virtual {
        if (
            newTreasury == address(0) ||
            newTreasury == address(this)
        ) revert InvalidTreasuryAddress(newTreasury);

        if (!IERC165(newTreasury).supportsInterface(type(ITreasury).interfaceId)) {
            revert TreasuryInterfaceNotSupported(newTreasury);
        }

        SharesManagerStorage storage $ = _getSharesManagerStorage();
        emit TreasuryChange(address($._treasury), newTreasury);
        $._treasury = ITreasury(newTreasury);
    }

    /**
     * @notice Function to get the current max supply of vote tokens available for minting.
     * @dev Overrides to use the updateable _maxSupply
     */
    function maxSupply() public view virtual override(
        ERC20CheckpointsUpgradeable,
        ISharesManager
    ) returns (uint256 _maxSupply) {
        _maxSupply = _getSharesManagerStorage()._maxSupply;
    }

    /**
     * @notice Executor-only function to update the max supply of vote tokens.
     * @param newMaxSupply The new max supply. Must be no greater than type(uint224).max.
     */
    function setMaxSupply(uint256 newMaxSupply) external virtual onlyOwner {
        _setMaxSupply(newMaxSupply);
    }

    /**
     * @dev Internal function to update the max supply.
     * We DO allow the max supply to be set below the current totalSupply(), because this would allow a DAO to
     * remain in Funding mode, and continue to reject deposits ABOVE the max supply threshold of tokens minted.
     * May never be used, but preserves DAO optionality.
     */
    function _setMaxSupply(uint256 newMaxSupply) internal virtual {
        // Max supply is limited by ERC20Checkpoints
        uint256 maxSupplyLimit = super.maxSupply();
        if (newMaxSupply > maxSupplyLimit) revert MaxSupplyTooLarge(maxSupplyLimit);

        SharesManagerStorage storage $ = _getSharesManagerStorage();
        emit MaxSupplyChange($._maxSupply, newMaxSupply);
        $._maxSupply = newMaxSupply;
    }

    function quoteAsset() public view virtual override returns (IERC20 quoteAsset_) {
        quoteAsset_ = _getSharesManagerStorage()._quoteAsset;
    }

    function setQuoteAsset(address newQuoteAsset) external virtual override onlyOwner {
        _setQuoteAsset(newQuoteAsset, false);
    }

    function setQuoteAssetAndCheckInterfaceSupport(address newQuoteAsset) external virtual override onlyOwner {
        _setQuoteAsset(newQuoteAsset, true);
    }

    function _setQuoteAsset(address newQuoteAsset, bool checkInterfaceSupport) internal virtual {
        if (newQuoteAsset == address(this)) revert CannotSetQuoteAssetToSelf();
        if (checkInterfaceSupport) {
            if (!IERC165(newQuoteAsset).supportsInterface(type(IERC20).interfaceId)) {
                revert UnsupportedQuoteAssetInterface();
            }
        }

        SharesManagerStorage storage $ = _getSharesManagerStorage();
        emit QuoteAssetChange(address($._quoteAsset), newQuoteAsset);
        $._quoteAsset = IERC20(newQuoteAsset);
    }

    function isFundingActive() public view override returns (bool fundingActive) {
        (fundingActive,) = _isFundingActive();
    }

    function _isFundingActive() internal view returns (bool fundingActive, ITreasury treasury_) {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
        treasury_ = $._treasury;
        uint256 fundingBeginsAt_ = $._fundingBeginsAt;
        uint256 fundingEndsAt_ = $._fundingEndsAt;

        fundingActive = address(treasury_) != address(0) &&
            block.timestamp >= fundingBeginsAt_ &&
            block.timestamp < fundingEndsAt_;
    }

    function fundingPeriods() public view override returns (uint256 fundingBeginsAt, uint256 fundingEndsAt) {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
        (fundingBeginsAt, fundingEndsAt) = ($._fundingBeginsAt, $._fundingEndsAt);
    }

    function setFundingPeriods(
        uint256 newFundingBeginsAt,
        uint256 newFundingEndsAt
    ) external virtual override onlyOwner {
        _setFundingPeriods(newFundingBeginsAt, newFundingEndsAt);
    }

    function _setFundingPeriods(uint256 newFundingBeginsAt, uint256 newFundingEndsAt) internal virtual {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
        uint256 currentFundingBeginsAt = $._fundingBeginsAt;
        uint256 currentFundingEndsAt = $._fundingEndsAt;

        // Cast to uint48, which will revert on overflow
        uint48 castedFundingBeginsAt = newFundingBeginsAt.toUint48();
        uint48 castedFundingEndsAt = newFundingEndsAt.toUint48();

        emit FundingPeriodChange(currentFundingBeginsAt, newFundingBeginsAt, currentFundingEndsAt, newFundingEndsAt);
        $._fundingBeginsAt = castedFundingBeginsAt;
        $._fundingEndsAt = castedFundingEndsAt;
    }

    /**
     * @notice Returns the quoteAmount and the mintAmount of the token price.
     *
     * The {quoteAmount} is the minimum amount of the quote asset tokens required to mint {mintAmount} amount of votes.
     */
    function sharePrice() public view override returns (uint128 quoteAmount, uint128 mintAmount) {
        SharePrice storage _sharePrice = _getSharesManagerStorage()._sharePrice;
        (quoteAmount, mintAmount) = (_sharePrice.quoteAmount, _sharePrice.mintAmount);
    }

    /**
     * @notice Public function to update the token price. Only the executor can make an update to the token price.
     * @param newQuoteAmount The new quoteAmount value (the amount of base asset required for {mintAmount} amount of
     * shares). Set to zero to keep the quoteAmount unchanged.
     * @param newMintAmount The new mintAmount value (the amount of shares minted for every {quoteAmount} amount of the
     * base asset). Set to zero to keep the mintAmount unchanged.
     */
    function setSharePrice(uint256 newQuoteAmount, uint256 newMintAmount) external virtual override onlyOwner {
        _setSharePrice(newQuoteAmount, newMintAmount);
    }

    /**
     * @dev Private function to update the tokenPrice quoteAmount and mintAmount. Skips update of zero values (unless the
     * current value is zero, in which case it throws an error).
     */
    function _setSharePrice(uint256 newQuoteAmount, uint256 newMintAmount) private {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
        uint256 currentQuoteAmount = $._sharePrice.quoteAmount;
        uint256 currentMintAmount = $._sharePrice.mintAmount;
        // Only update if the new value is not zero
        if (newQuoteAmount > 0) {
            $._sharePrice.quoteAmount = SafeCast.toUint128(newQuoteAmount);
        } else {
            // Don't allow keeping a zero value
            if (currentQuoteAmount == 0) {
                revert SharePriceCannotBeZero();
            }
        }
        if (newMintAmount > 0) {
            $._sharePrice.mintAmount = SafeCast.toUint128(newMintAmount);
        } else {
            // Don't allow keeping a zero value
            if (currentMintAmount == 0) {
                revert SharePriceCannotBeZero();
            }
        }
        emit SharePriceChange(currentQuoteAmount, newQuoteAmount, currentMintAmount, newMintAmount);
    }

    /**
     * @notice Allows exchanging the depositAmount of base asset for votes (if votes are available for purchase).
     * @param account The account address to deposit to.
     * @param depositAmount The amount of the base asset being deposited. Will mint tokenPrice.mintAmount votes for
     * every tokenPrice.quoteAmount count of base asset tokens.
     * @dev This calls _depositFor, but should be overridden for any additional checks.
     * @return Amount of vote tokens minted.
     */
    function depositFor(address account, uint256 depositAmount) public payable virtual returns (uint256) {
        return _depositFor(account, depositAmount);
    }

    /**
     * @notice Calls {depositFor} with msg.sender as the account.
     * @param depositAmount The amount of the base asset being deposited. Will mint tokenPrice.mintAmount votes for
     * every tokenPrice.quoteAmount count of base asset tokens.
     */
    function deposit(uint256 depositAmount) public payable virtual returns (uint256) {
        return depositFor(_msgSender(), depositAmount);
    }

    /**
     * @dev Internal function for processing the deposit. Calls _transferDepositToExecutor, which must be implemented in
     * an inheriting contract.
     */
    function _depositFor(
        address account,
        uint256 depositAmount
    ) internal virtual returns (uint256) {
        (bool fundingActive, ITreasury treasury_) = _isFundingActive();
        if (!fundingActive) {
            revert FundingIsNotActive();
        }

        // Zero address is checked in the _mint function
        if (depositAmount == 0) revert InvalidDepositAmount();

        (uint256 quoteAmount, uint256 mintAmount) = sharePrice();

        // The "depositAmount" must be a multiple of the token price quoteAmount
        if (depositAmount % quoteAmount != 0) revert InvalidDepositAmountMultiple();

        // In founding mode, block.timestamp must be past the tokenSaleBeginsAt timestamp
        // if (currentProvisionMode == ProvisionMode.Founding) {
        //     if (block.timestamp < tokenSaleBeginsAt) revert TokenSalesNotAvailableYet(tokenSaleBeginsAt);
        // // The current price per token must not exceed the current value per token, or the treasury will be at risk
        // // NOTE: We should bypass this check in founding mode to prevent an attack locking deposits
        // } else {
        //     if (
        //         Math512.mul512Lt(quoteAmount, totalSupply(), mintAmount, _treasuryBalance())
        //     ) revert TokenPriceTooLow();
        // }
        uint256 totalMintAmount = depositAmount / quoteAmount * mintAmount;
        _transferDepositToExecutor(depositAmount);
        _mint(account, totalMintAmount);
        emit Deposit(account, depositAmount, totalMintAmount);
        return totalMintAmount;
    }

    /**
     * @notice Allows burning the provided amount of vote tokens owned by the transaction sender and withdrawing the
     * proportional share of the base asset in the treasury.
     * @param receiver The address for the base asset to be sent to.
     * @param amount The amount of vote tokens to be burned.
     * @return The amount of base asset withdrawn.
     */
    function withdrawTo(address receiver, uint256 amount) public virtual returns (uint256) {
        return _withdraw(_msgSender(), receiver, amount);
    }

    /**
     * @notice Allows burning the provided amount of vote tokens and withdrawing the proportional share of the base
     * asset from the treasury. The tokens are burned for msg.sender, and the base asset is sent to msg.sender as well.
     * @param amount The amount of vote tokens to be burned.
     * @return The amount of base asset withdrawn.
     */
    function withdraw(uint256 amount) public virtual returns (uint256) {
        return _withdraw(_msgSender(), _msgSender(), amount);
    }

    /**
     * @dev Allow withdrawal by EIP712 signature
     */
    function withdrawBySig(
        address owner,
        address receiver,
        uint256 amount,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual returns (uint256) {
        if (block.timestamp > expiry) revert ERC2612ExpiredSignature(expiry);
        address signer = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(WITHDRAW_TYPEHASH, owner, receiver, amount, _useNonce(owner), expiry)
                )
            ),
            v,
            r,
            s
        );
        if (signer != owner) revert ERC2612InvalidSigner(signer, owner);
        return _withdraw(signer, receiver, amount);
    }

    /**
     * @dev Internal function for processing the withdrawal. Calls _transferWithdrawalToReciever, which must be
     * implemented in an inheriting contract.
     */
    function _withdraw(address account, address receiver, uint256 amount) internal virtual returns(uint256) {
        if (account == address(0)) revert WithdrawFromZeroAddress();
        if (receiver == address(0)) revert WithdrawToZeroAddress();
        if (amount == 0) revert WithdrawAmountInvalid();

        uint256 withdrawAmount = _valuePerToken(amount); // [ (amount/supply) * treasuryBalance ]

        // _burn checks for InsufficientBalance
        _burn(account, amount);
        // Transfer withdrawal funds AFTER burning tokens to ensure no re-entrancy
        _transferWithdrawalToReceiver(receiver, withdrawAmount);

        emit Withdrawal(account, receiver, withdrawAmount, amount);

        return withdrawAmount;
    }

    function _valuePerToken(uint256 multiplier) internal view returns (uint256) {
        uint256 supply = totalSupply();
        uint256 balance = _treasuryBalance();
        return supply > 0 ? Math.mulDiv(balance, multiplier, supply) : 0;
    }

    /**
     * @dev Internal function that returns the balance of the base asset in the Executor.
     */
    function _treasuryBalance() internal view virtual returns (uint256) {
        return treasury().treasuryBalance();
    }

    /**
     * @dev Internal function that should be overridden with functionality to transfer the depositAmount of base asset
     * to the Executor from the msg.sender.
     */
    function _transferDepositToExecutor(uint256 depositAmount) internal virtual;

    /**
     * @dev Internal function that should be overridden with functionality to transfer the withdrawal to the recipient.
     */
    function _transferWithdrawalToReceiver(address receiver, uint256 withdrawAmount) internal virtual;

    /**
     * @dev Relays a transaction or function call to an arbitrary target, only callable by the executor. If the relay
     * target is the executor, only allows sending ETH via the value (as the calldata length is required to be zero in
     * this case). This is to protect against relay functions calling token-only functions on the executor.
     */
    function relay(address target, uint256 value, bytes calldata data) external payable virtual onlyOwner {
        if (
            target == owner() && data.length > 0
        ) revert RelayDataToExecutorNotAllowed(data);
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        // Revert with return data on unsuccessful calls
        if (!success) {
            assembly {
                revert(add(32, returndata), mload(returndata))
            }
        }
    }

}