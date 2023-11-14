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

    uint256 private constant COMPARE_FRACTIONS_MULTIPLIER = 1_000;

    IERC20 internal immutable _baseAsset; // The address for the DAO's base asset (address(0) for ETH)

    /// @custom:storage-location erc7201:SharesManager.Storage
    struct SharesManagerStorage {
        uint256 _maxSupply;

        /// @dev _tokenPrice updates should always go through {_setTokenPrice} to avoid setting price to zero
        TokenPrice _tokenPrice;

        ITreasury _treasury;
        ProvisionMode _provisionMode;
    }

    bytes32 private immutable SHARES_MANAGER_STORAGE =
        keccak256(abi.encode(uint256(keccak256("SharesManager.Storage")) - 1)) & ~bytes32(uint256(0xff));

    function _getSharesManagerStorage() private view returns (SharesManagerStorage storage $) {
        bytes32 sharesManagerStorageSlot = SHARES_MANAGER_STORAGE;
        assembly {
            $.slot := sharesManagerStorageSlot
        }
    }

    // Timestamps for when token sales begin and when governance can begin
    uint256 public immutable tokenSaleBeginsAt;
    uint256 public immutable governanceCanBeginAt;
    uint256 public immutable governanceThreshold;

    modifier treasuryIsReady() {
        if (treasury() == address(0)) revert TreasuryIsNotReady();
        _;
    }

    constructor(
        address owner_,
        address treasury_,
        IERC20 baseAsset_,
        uint256 maxSupply_,
        TokenPrice memory tokenPrice_,
        uint256 tokenSaleBeginsAt_,
        uint256 governanceCanBeginAt_,
        uint256 governanceThreshold_
    ) {
        __Ownable_init(owner_);
        _setTreasury(treasury_);
        if (address(baseAsset_) == address(this)) revert CannotInitializeBaseAssetToSelf();
        _baseAsset = baseAsset_;
        _setMaxSupply(maxSupply_);
        if (tokenPrice_.numerator == 0 || tokenPrice_.denominator == 0) revert CannotInitializeTokenPriceToZero();
        _setTokenPrice(tokenPrice_.numerator, tokenPrice_.denominator);
        tokenSaleBeginsAt = tokenSaleBeginsAt_;
        governanceCanBeginAt = governanceCanBeginAt_;
        governanceThreshold = governanceThreshold_;
    }

    /**
     * @notice Function to get the current provision mode of the token.
     */
    function provisionMode() public view virtual returns(ProvisionMode) {
        return _getSharesManagerStorage()._provisionMode;
    }

    /**
     * @notice Executor-only function to update the provision mode.
     */
    function setProvisionMode(ProvisionMode mode) public virtual onlyOwner {
        _setProvisionMode(mode);
    }

    /**
     * @dev Internal function to set the provision mode.
     */
    function _setProvisionMode(ProvisionMode mode) internal virtual {
        if (block.timestamp < governanceCanBeginAt) revert CannotSetProvisionModeYet(governanceCanBeginAt);
        if (mode <= ProvisionMode.Founding) revert ProvisionModeTooLow();

        SharesManagerStorage storage $ = _getSharesManagerStorage();
        ProvisionMode currentProvisionMode = $._provisionMode;
        if (currentProvisionMode == ProvisionMode.Founding) {
            _governanceInitialized($);
        }

        emit ProvisionModeChange(currentProvisionMode, mode);
        $._provisionMode = mode;
    }

    function _governanceInitialized(SharesManagerStorage storage $) internal virtual {
        uint256 tokenPriceNumerator = $._tokenPrice.numerator;
        uint256 tokenPriceDenominator = $._tokenPrice.denominator;
        uint256 currentTotalSupply = totalSupply();
        uint256 baseAssetDeposits = Math.mulDiv(currentTotalSupply, tokenPriceNumerator, tokenPriceDenominator);
        _getTreasurer().governanceInitialized(baseAsset(), baseAssetDeposits);
    }

    /**
     * @notice Returns true if the governanceThreshold of tokens is met and the governanceCanBeginAt timestamp has been
     * reached. Also returns the current provision mode.
     */
    function isGovernanceAllowed() public view virtual returns(bool, ProvisionMode) {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
        return  (
            totalSupply() >= governanceThreshold && block.timestamp >= governanceCanBeginAt,
            $._provisionMode
        );
    }

    /**
     * @notice Function to get the current max supply of vote tokens available for minting.
     * @dev Overrides to use the updateable _maxSupply
     */
    function maxSupply() public view virtual override(
        ERC20CheckpointsUpgradeable,
        ISharesManager
    ) returns (uint256) {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
        return $._maxSupply;
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

    /**
     * Returns the address of the treasury contract.
     * @notice This address is likely to be the same address as the owner contract.
     */
    function treasury() public view virtual returns (address) {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
        return address($._treasury);
    }

    function setTreasury(address newTreasury) public virtual onlyOwner {
        _setTreasury(newTreasury);
    }

    function _setTreasury(address newTreasury) internal virtual {
        if (newTreasury == address(0)) revert InvalidTreasuryAddress(newTreasury);
        if (!IERC165(newTreasury).supportsInterface(type(ITreasury).interfaceId)) {
            revert TreasuryInterfaceNotSupported(newTreasury);
        }

        SharesManagerStorage storage $ = _getSharesManagerStorage();
        emit TreasuryChange(address($._treasury), newTreasury);
        $._treasury = ITreasury(newTreasury);
    }

    /**
     * @notice Returns the address of the base asset (or address(0) if the base asset is ETH)
     */
    function baseAsset() public view returns (address) {
        return address(_baseAsset);
    }

    /**
     * @notice Returns the numerator and the denominator of the token price.
     *
     * The {numerator} is the minimum amount of the base asset tokens required to mint {denominator} amount of votes.
     */
    function tokenPrice() public view returns (uint128, uint128) {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
        return ($._tokenPrice.numerator, $._tokenPrice.denominator);
    }

    /**
     * @notice Public function to update the token price. Only the executor can make an update to the token price.
     * @param newNumerator The new numerator value (the amount of base asset required for {denominator} amount of
     * shares). Set to zero to keep the numerator unchanged.
     * @param newDenominator The new denominator value (the amount of shares minted for every {numerator} amount of the
     * base asset). Set to zero to keep the denominator unchanged.
     */
    function setTokenPrice(uint256 newNumerator, uint256 newDenominator) public virtual onlyOwner {
        _setTokenPrice(newNumerator, newDenominator);
    }

    /**
     * @dev Private function to update the tokenPrice numerator and denominator. Skips update of zero values (unless the
     * current value is zero, in which case it throws an error).
     */
    function _setTokenPrice(uint256 newNumerator, uint256 newDenominator) private {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
        uint256 currentNumerator = $._tokenPrice.numerator;
        uint256 currentDenominator = $._tokenPrice.denominator;
        // Only update if the new value is not zero
        if (newNumerator > 0) {
            $._tokenPrice.numerator = SafeCast.toUint128(newNumerator);
        } else {
            // Don't allow keeping a zero value
            if (currentNumerator == 0) {
                revert TokenPriceCannotBeZero();
            }
        }
        if (newDenominator > 0) {
            $._tokenPrice.denominator = SafeCast.toUint128(newDenominator);
        } else {
            // Don't allow keeping a zero value
            if (currentDenominator == 0) {
                revert TokenPriceCannotBeZero();
            }
        }
        emit TokenPriceChange(currentNumerator, newNumerator, currentDenominator, newDenominator);
    }

    function valuePerToken() public view returns (uint256) {
        return _valuePerToken(1);
    }

    /**
     * @notice Allows exchanging the depositAmount of base asset for votes (if votes are available for purchase).
     * @param account The account address to deposit to.
     * @param depositAmount The amount of the base asset being deposited. Will mint tokenPrice.denominator votes for
     * every tokenPrice.numerator count of base asset tokens.
     * @dev This calls _depositFor, but should be overridden for any additional checks.
     * @return Amount of vote tokens minted.
     */
    function depositFor(address account, uint256 depositAmount) public payable virtual returns (uint256) {
        return _depositFor(account, depositAmount);
    }

    /**
     * @notice Calls {depositFor} with msg.sender as the account.
     * @param depositAmount The amount of the base asset being deposited. Will mint tokenPrice.denominator votes for
     * every tokenPrice.numerator count of base asset tokens.
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
    ) internal virtual treasuryIsReady returns (uint256) {
        SharesManagerStorage storage $ = _getSharesManagerStorage();

        ProvisionMode currentProvisionMode = $._provisionMode;
        if (currentProvisionMode == ProvisionMode.Governance) revert DepositsUnavailable();
        // Zero address is checked in the _mint function
        if (depositAmount == 0) revert InvalidDepositAmount();

        uint256 tokenPriceNumerator = $._tokenPrice.numerator;
        uint256 tokenPriceDenominator = $._tokenPrice.denominator;

        // The "depositAmount" must be a multiple of the token price numerator
        if (depositAmount % tokenPriceNumerator != 0) revert InvalidDepositAmountMultiple();

        // In founding mode, block.timestamp must be past the tokenSaleBeginsAt timestamp
        if (currentProvisionMode == ProvisionMode.Founding) {
            if (block.timestamp < tokenSaleBeginsAt) revert TokenSalesNotAvailableYet(tokenSaleBeginsAt);
        // The current price per token must not exceed the current value per token, or the treasury will be at risk
        // NOTE: We should bypass this check in founding mode to prevent an attack locking deposits
        } else {
            if (
                Math512.mul512Lt(tokenPriceNumerator, totalSupply(), tokenPriceDenominator, _treasuryBalance())
            ) revert TokenPriceTooLow();
        }
        uint256 mintAmount = depositAmount / tokenPriceNumerator * tokenPriceDenominator;
        _transferDepositToExecutor(depositAmount, currentProvisionMode);
        _mint(account, mintAmount);
        emit Deposit(account, depositAmount, mintAmount);
        return mintAmount;
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

    /**
     * @dev Internal function for returning the executor address wrapped as the Treasurer contract.
     */
    function _getTreasurer() internal view returns (ITreasury) {
        return ITreasury(payable(treasury()));
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
        return _getTreasurer().treasuryBalance();
    }

    /**
     * @dev Internal function that should be overridden with functionality to transfer the depositAmount of base asset
     * to the Executor from the msg.sender.
     */
    function _transferDepositToExecutor(
        uint256 depositAmount,
        ProvisionMode currentProvisionMode
    ) internal virtual;

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