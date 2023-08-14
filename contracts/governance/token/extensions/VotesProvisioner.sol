// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "../Votes.sol";
import "./IVotesProvisioner.sol";
import "../../executor/extensions/Treasurer.sol";
import "../../utils/ExecutorControlled.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../../utils/Math512.sol";

using SafeMath for uint256;
using Address for address;

uint256 constant COMPARE_FRACTIONS_MULTIPLIER = 1_000;

/**
 * @dev Extension of {Votes} to support decentralized DAO formation.
 *
 * Complete with deposit/withraw functionality.
 *
 * Anyone can mint vote tokens in exchange for the DAO's base asset. Any member can withdraw pro rata.
 */
abstract contract VotesProvisioner is Votes, IVotesProvisioner, ExecutorControlled {

    bytes32 private constant _WITHDRAW_TYPEHASH = keccak256(
        "Withdraw(address owner,address receiver,uint256 amount,uint256 nonce,uint256 expiry)"
    );

    uint256 private constant MAX_MAX_SUPPLY = type(uint224).max;

    ProvisionMode private _provisionMode;

    uint256 internal _maxSupply;

    /// @dev _tokenPrice updates should always go through {_updateTokenPrice} to avoid setting price to zero
    TokenPrice private _tokenPrice = TokenPrice(1, 1); // Defaults to 1 to 1

    IERC20 internal immutable _baseAsset; // The address for the DAO's base asset (address(0) for ETH)

    constructor(
        Treasurer executor_,
        uint256 maxSupply_,
        TokenPrice memory tokenPrice_,
        IERC20 baseAsset_
    ) ExecutorControlled(executor_) {
        require(address(baseAsset_) != address(this), "VotesProvisioner: cannot make self the base asset.");
        if (address(baseAsset_) != address(0)) {
            require(address(baseAsset_).isContract(), "VotesProvisioner: base asset must be a deployed contract.");
        }
        _baseAsset = baseAsset_;
        _updateMaxSupply(maxSupply_);
        require(
            tokenPrice_.numerator != 0 && tokenPrice_.denominator != 0,
            "VotesProvisioner: Cannot set token price to 0."
        );
        _updateTokenPrice(tokenPrice_.numerator, tokenPrice_.denominator);
    }

    /**
     * @notice Function to get the current provision mode of the token.
     */
    function provisionMode() public view virtual returns(ProvisionMode) {
        return _provisionMode;
    }

    /**
     * @notice Executor-only function to update the provision mode.
     */
    function setProvisionMode(ProvisionMode mode) public virtual onlyExecutor {
        _setProvisionMode(mode);
    }

    error ProvisionModeTooLow();
    /**
     * @dev Internal function to set the provision mode.
     */
    function _setProvisionMode(ProvisionMode mode) internal virtual {
        if (mode <= ProvisionMode.Founding) revert ProvisionModeTooLow();

        emit ProvisionModeChange(_provisionMode, mode);
        _provisionMode = mode;
    }

    /**
     * @notice Function to get the current max supply of vote tokens available for minting.
     * @dev Overrides to use the updateable _maxSupply
     */
    function maxSupply() public view virtual override(ERC20Checkpoints, IVotesProvisioner) returns (uint256) {
        return _maxSupply;
    }

    /**
     * @notice Executor-only function to update the max supply of vote tokens.
     * @param newMaxSupply The new max supply. Must be no greater than type(uint224).max.
     */
    function updateMaxSupply(uint256 newMaxSupply) external virtual onlyExecutor {
        _updateMaxSupply(newMaxSupply);
    }

    error MaxSupplyTooLarge(uint256 max);
    /**
     * @dev Internal function to update the max supply.
     * We DO allow the max supply to be set below the current totalSupply(), because this would allow a DAO to
     * remain in Funding mode, and continue to reject deposits ABOVE the max supply threshold of tokens minted.
     * May never be used, but preserves DAO optionality.
     */
    function _updateMaxSupply(uint256 newMaxSupply) internal virtual {
        if (newMaxSupply > MAX_MAX_SUPPLY) revert MaxSupplyTooLarge(MAX_MAX_SUPPLY);

        emit MaxSupplyChange(_maxSupply, newMaxSupply);
        _maxSupply = newMaxSupply;
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
        return (_tokenPrice.numerator, _tokenPrice.denominator);
    }

    error TokenPriceParametersMustBeGreaterThanZero();
    /**
     * @notice Public function to update the token price. Only the executor can make an update to the token price.
     * @param newNumerator The new numerator value (the amount of base asset required for {denominator} amount of votes).
     * Set to zero to keep the numerator the same.
     * @param newDenominator The new denominator value (the amount of votes minted for every {numerator} amount of the base
     * asset). Set to zero to keep the denominator the same.
     */
    function updateTokenPrice(uint256 newNumerator, uint256 newDenominator) public virtual onlyExecutor {
        if (newNumerator == 0 || newDenominator == 0) revert TokenPriceParametersMustBeGreaterThanZero();
        _updateTokenPrice(newNumerator, newDenominator);
    }

    /**
     * @notice Public function to update the token price numerator. Only executor can update.
     * @param newNumerator The new numerator value (the amount of base asset required for {denominator} amount of votes).
     */
    function updateTokenPriceNumerator(uint256 newNumerator) public virtual onlyExecutor {
        if (newNumerator == 0) revert TokenPriceParametersMustBeGreaterThanZero();
        _updateTokenPrice(newNumerator, 0);
    }

    /**
     * @notice Public function to update the token price. Only executor can update.
     * @param newDenominator The new denominator value (the amount of votes minted for every {numerator} amount of the base
     * asset).
     */
    function updateTokenPriceDenominator(uint256 newDenominator) public virtual onlyExecutor {
        if (newDenominator == 0) revert TokenPriceParametersMustBeGreaterThanZero();
        _updateTokenPrice(0, newDenominator);
    }

    /**
     * @dev Private function to update the tokenPrice numerator and denominator. Skips update of zero values (neither can
     * be set to zero).
     */
    function _updateTokenPrice(uint256 newNumerator, uint256 newDenominator) private {
        uint256 prevNumerator = _tokenPrice.numerator;
        uint256 prevDenominator = _tokenPrice.denominator;
        if (newNumerator > 0) {
            _tokenPrice.numerator = SafeCast.toUint128(newNumerator);
        }
        if (newDenominator > 0) {
            _tokenPrice.denominator = SafeCast.toUint128(newDenominator);
        }
        emit TokenPriceChange(prevNumerator, newNumerator, prevDenominator, newDenominator);
    }

    function valuePerToken() public view returns (uint256) {
        return _valuePerToken(1);
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
     * @notice Allows exchanging the depositAmount of base asset for votes (if votes are available for purchase).
     * @param account The account address to deposit to.
     * @param depositAmount The amount of the base asset being deposited. Will mint tokenPrice.denominator votes for
     * every tokenPrice.numerator count of base asset tokens.
     * @dev This is abstract, and should be overridden to provide functionality based on the _baseAsset (ETH vs ERC20)
     * @return Amount of vote tokens minted.
     */
    function depositFor(address account, uint256 depositAmount) public payable virtual returns (uint256);

    /**
     * @notice Calls {depositFor} with msg.sender as the account.
     * @param depositAmount The amount of the base asset being deposited. Will mint tokenPrice.denominator votes for every
     * tokenPrice.numerator count of base asset tokens.
     */
    function deposit(uint256 depositAmount) public payable virtual returns (uint256) {
        return depositFor(_msgSender(), depositAmount);
    }

    /**
     * @dev Internal function that should be overridden with functionality to transfer the deposit to the Executor.
     */
    function _transferDepositToExecutor(address account, uint256 depositAmount) internal virtual;

    /**
     * @dev Internal function that should be overridden with functionality to transfer the withdrawal to the recipient.
     */
    function _transferWithdrawalToReceiver(address receiver, uint256 withdrawAmount) internal virtual;

    error DepositsUnavailable();
    error InvalidDepositAmount();
    error InvalidDepositAmountMultiple();
    error TokenPriceTooLow();
    /**
     * @dev Internal function for processing the deposit. Calls _transferDepositToExecutor, which must be implemented in
     * an inheriting contract.
     */
    function _depositFor(
        address account,
        uint256 depositAmount
    ) internal virtual executorIsInitialized returns (uint256) {
        ProvisionMode currentProvisionMode = _provisionMode;
        if (currentProvisionMode == ProvisionMode.Governance) revert DepositsUnavailable();
        // Zero address is checked in the _mint function
        if (depositAmount == 0) revert InvalidDepositAmount();

        uint256 tokenPriceNumerator = _tokenPrice.numerator;
        uint256 tokenPriceDenominator = _tokenPrice.denominator;

        // The "depositAmount" must be a multiple of the token price numerator
        if (depositAmount % tokenPriceNumerator != 0) revert InvalidDepositAmountMultiple();

        // The current price per token must not exceed the current value per token, or the treasury will be at risk
        // NOTE: We should bypass this check in founding mode to prevent an attack locking deposits
        if (currentProvisionMode != ProvisionMode.Founding) {
            if (
                Math512.mul512_lt(tokenPriceNumerator, totalSupply(), tokenPriceDenominator, _treasuryBalance())
            ) revert TokenPriceTooLow();
        }
        uint256 mintAmount = depositAmount / tokenPriceNumerator * tokenPriceDenominator;
        _transferDepositToExecutor(account, depositAmount);
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
     * @notice Allows burning the provided amount of vote tokens and withdrawing the proportional share of the base asset
     * from the treasury. The tokens are burned for msg.sender, and the base asset is sent to msg.sender as well.
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
        if (block.timestamp > expiry) revert SignatureExpired();
        address signer = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(_WITHDRAW_TYPEHASH, owner, receiver, amount, _useNonce(owner), expiry)
                )
            ),
            v,
            r,
            s
        );
        if (owner != signer) revert SignatureInvalid();
        return _withdraw(signer, receiver, amount);
    }

    error WithdrawFromZeroAddress();
    error WithdrawToZeroAddress();
    error WithdrawAmountInvalid();
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
    function _getTreasurer() internal view returns (Treasurer) {
        return Treasurer(payable(address(_executor)));
    }

}