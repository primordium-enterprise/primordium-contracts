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
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title SharesManager - Contract responsible for managing permissionless deposits and withdrawals (rage quit).
 *
 * @dev Extends the ERC20Votes to access the internal _mint and _burn functionalities. Deposits and withdrawals are
 * processed through the specified "treasury" address (usually a DAO executor contract).
 *
 * The owner (also likely the DAO executor contract) can update the funding period, set the treasury address for where
 * to send the deposits and process the withdrawals from. The owner can also update the share price and the quote asset
 * (an ERC20 address or address(0) for native ETH) for the permissionless funding.
 *
 * Anyone can mint vote tokens in exchange for the DAO's quote asset as long as funding is active. Any member can
 * withdraw (rage quit) pro rata at any time.
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract SharesManager is ERC20VotesUpgradeable, ISharesManager, Ownable1Or2StepUpgradeable {
    using Math for uint256;
    using SafeCast for *;
    using SafeERC20 for IERC20;

    bytes32 private constant WITHDRAW_TYPEHASH = keccak256(
        "Withdraw(address owner,address receiver,uint256 amount,address[] tokens,uint256 nonce,uint256 expiry)"
    );

    struct SharePrice {
        uint128 quoteAmount; // Minimum amount of quote asset tokens required to mint {mintAmount} amount of votes.
        uint128 mintAmount; // Number of votes that can be minted per {quoteAmount} count of quote asset.
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
        SharePrice calldata sharePrice_,
        uint256 fundingBeginsAt_,
        uint256 fundingEndsAt_
    ) internal virtual onlyInitializing {
        __Ownable_init(owner_);
        _setTreasury(treasury_);
        _setMaxSupply(maxSupply_);
        _setQuoteAsset(quoteAsset_, checkQuoteAssetInterface_);
        _setSharePrice(sharePrice_.quoteAmount, sharePrice_.mintAmount);
        _setFundingPeriods(fundingBeginsAt_, fundingEndsAt_);
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

    function quoteAsset() public view virtual override returns (IERC20 _quoteAsset) {
        _quoteAsset = _getSharesManagerStorage()._quoteAsset;
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
     * @param newQuoteAmount The new quoteAmount value (the amount of quote asset required for {mintAmount} amount of
     * shares). Set to zero to keep the quoteAmount unchanged.
     * @param newMintAmount The new mintAmount value (the amount of shares minted for every {quoteAmount} amount of the
     * quote asset). Set to zero to keep the mintAmount unchanged.
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
     * @notice Allows exchanging the depositAmount of quote asset for vote shares (if shares are currently available).
     * @param account The recipient account address to receive the newly minted share tokens.
     * @param depositAmount The amount of the quote asset being deposited by the msg.sender. Will mint
     * {sharePrice.mintAmount} votes for every {sharePrice.quoteAmount} amount of quote asset tokens. The depositAmount
     * must be an exact multiple of the {sharePrice.quoteAmount}. The  depositAmount also must match the msg.value if
     * the current quoteAsset is the native chain currency (address(0)).
     * @return totalSharesMinted The amount of vote share tokens minted to the account.
     */
    function depositFor(
        address account,
        uint256 depositAmount
    ) public payable virtual returns (uint256 totalSharesMinted) {
        totalSharesMinted = _depositFor(account, depositAmount, _msgSender());
    }

    /**
     * @notice Same as the {depositFor} function, but uses the msg.sender as the recipient account of the newly minted
     * shares.
     */
    function deposit(uint256 depositAmount) public payable virtual returns (uint256 totalSharesMinted) {
        address account = _msgSender();
        totalSharesMinted = _depositFor(account, depositAmount, account);
    }

    /**
     * @notice Additional function helper to use permit on the quote asset contract to approve and deposit in a single
     * transaction (if supported by the ERC20 quote asset).
     */
    function depositWithPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual returns (uint256 totalSharesMinted) {
        if (spender != address(this)) revert InvalidPermitSpender(spender, address(this));
        IERC20Permit(address(quoteAsset())).permit(
            owner,
            spender,
            value,
            deadline,
            v,
            r,
            s
        );
        // The "owner" should be the receiver and the depositor
        totalSharesMinted = _depositFor(owner, value, owner);
    }

    /**
     * @dev Internal function for processing the deposit. Runs several checks before transferring the deposit to the
     * treasury and minting shares to the provided account address. Main checks:
     * - Funding is active (treasury is not zero address, and block.timestamp is in funding window)
     * - depositAmount cannot be zero, and must be a multiple of the quoteAmount
     * - msg.value is proper based on the current quoteAsset
     */
    function _depositFor(
        address account,
        uint256 depositAmount,
        address depositor
    ) internal virtual returns (uint256 totalSharesMinted) {
        (bool fundingActive, ITreasury treasury_) = _isFundingActive();
        if (!fundingActive) {
            revert FundingIsNotActive();
        }

        // NOTE: The {_mint} function already checks to ensure the account address != address(0)
        if (depositAmount == 0) revert InvalidDepositAmount();

        (uint256 quoteAmount, uint256 mintAmount) = sharePrice();

        // The "depositAmount" must be a multiple of the share price quoteAmount
        if (depositAmount % quoteAmount != 0) revert InvalidDepositAmountMultiple();

        // Transfer the deposit to the treasury, and register the deposit on the treasury
        IERC20 _quoteAsset = quoteAsset();
        uint256 msgValue;
        if (address(_quoteAsset) == address(0)) {
            if (depositAmount != msg.value) {
                revert InvalidDepositAmount();
            }
            msgValue = msg.value;
        } else {
            if (msg.value > 0) {
                revert QuoteAssetIsNotNativeCurrency(address(_quoteAsset));
            }
            _quoteAsset.safeTransferFrom(depositor, address(treasury_), depositAmount);
        }
        treasury_.registerDeposit{value: msgValue}(_quoteAsset, depositAmount);

        // Mint the vote shares to the receiver
        totalSharesMinted = depositAmount / quoteAmount * mintAmount;
        _mint(account, totalSharesMinted);

        emit Deposit(account, depositAmount, totalSharesMinted);
    }

    /**
     * @notice Allows burning the provided amount of vote tokens owned by the msg.sender and withdrawing the
     * proportional share of the provided tokens in the treasury.
     * @param receiver The address for the share of provided tokens to be sent to.
     * @param amount The amount of vote shares to be burned.
     * @param tokens A list of token addresses to withdraw from the treasury. Use address(0) for the native currency,
     * such as ETH.
     * @return totalSharesBurned The amount of shares burned.
     */
    function withdrawTo(
        address receiver,
        uint256 amount,
        IERC20[] calldata tokens
    ) public virtual override returns (uint256 totalSharesBurned) {
        totalSharesBurned = _withdraw(_msgSender(), receiver, amount, tokens);
    }

    /**
     * @notice Same as the {withdrawTo} function, but uses the msg.sender as the receiver of all token withdrawals.
     */
    function withdraw(
        uint256 amount,
        IERC20[] calldata tokens
    ) public virtual override returns (uint256 totalSharesBurned) {
        address account = _msgSender();
        totalSharesBurned = _withdraw(account, account, amount, tokens);
    }

    /**
     * @dev Allow withdrawal by EIP712 signature
     */
    function withdrawBySig(
        address owner,
        address receiver,
        uint256 amount,
        IERC20[] calldata tokens,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual returns (uint256 totalSharesBurned) {
        if (block.timestamp > expiry) revert ERC2612ExpiredSignature(expiry);
        address signer = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(WITHDRAW_TYPEHASH, owner, receiver, amount, tokens, _useNonce(owner), expiry)
                )
            ),
            v,
            r,
            s
        );
        if (signer != owner) revert ERC2612InvalidSigner(signer, owner);
        totalSharesBurned = _withdraw(signer, receiver, amount, tokens);
    }

    /**
     * @dev Internal function for processing the withdrawal. Calls _transferWithdrawalToReciever, which must be
     * implemented in an inheriting contract.
     */
    function _withdraw(
        address account,
        address receiver,
        uint256 amount,
        IERC20[] calldata tokens
    ) internal virtual returns (uint256 totalSharesBurned) {
        if (account == address(0)) revert WithdrawFromZeroAddress();
        if (receiver == address(0)) revert WithdrawToZeroAddress();
        if (amount == 0) revert WithdrawAmountInvalid();

        totalSharesBurned = amount;

        // Cache the total supply before burning
        uint256 totalSupply = totalSupply();

        // _burn checks for InsufficientBalance
        _burn(account, amount);

        // Transfer withdrawal funds AFTER burning tokens to ensure no re-entrancy

        treasury().processWithdrawal(receiver, amount, totalSupply, tokens);

        emit Withdrawal(account, receiver, totalSharesBurned, tokens);
    }

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