// SPDX-License-Identifier: MIT
// Primordium Contracts


pragma solidity ^0.8.0;

import "../Votes.sol";
import "./IVotesProvisioner.sol";
import "../../executor/extensions/Treasurer.sol";
import "../../utils/ExecutorControlled.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

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

    ProvisionModes private _provisionMode;

    uint256 internal _maxSupply;

    TokenPrice private _tokenPrice = TokenPrice(1, 1); // Defaults to 1 to 1

    IERC20 internal immutable _baseAsset; // The address for the DAO's base asset (address(0) for ETH)

    constructor(
        Treasurer executor_,
        uint256 initialMaxSupply,
        TokenPrice memory initialTokenPrice,
        IERC20 baseAsset_
    ) ExecutorControlled(executor_) {
        require(address(baseAsset_) != address(this), "VotesProvisioner: cannot make itself the base asset.");
        if (address(baseAsset_) != address(0)) {
            require(address(baseAsset_).isContract(), "VotesProvisioner: base asset must be a deployed contract.");
        }
        _baseAsset = baseAsset_;
        _updateMaxSupply(initialMaxSupply);
        _updateTokenPrice(initialTokenPrice.numerator, initialTokenPrice.denominator);
    }

    /**
     * @notice Function to get the current provision mode of the token.
     */
    function provisionMode() public view virtual returns(ProvisionModes) {
        return _provisionMode;
    }

    /**
     * @notice Executor-only function to update the provision mode.
     */
    function setProvisionMode(ProvisionModes mode) public virtual onlyExecutor {
        _setProvisionMode(mode);
    }

    /**
     * @dev Internal function to set the provision mode.
     */
    function _setProvisionMode(ProvisionModes mode) internal virtual {
        require(mode > ProvisionModes.Founding, "VotesProvisioner: cannot set the provision mode to founding mode");
        ProvisionModes currentMode = _provisionMode;
        require(mode != currentMode, "VotesProvisioner: provision mode is already equal to the provided mode");
        emit ProvisionModeChange(currentMode, mode);
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

    /**
     * @dev Internal function to update the max supply.
     * We DO allow the max supply to be set below the current totalSupply(), because this would allow a DAO to
     * remain in Funding mode, and continue to reject deposits ABOVE the max supply threshold of tokens minted.
     * May never be used, but preserves DAO optionality.
     */
    function _updateMaxSupply(uint256 newMaxSupply) internal virtual {
        require(newMaxSupply <= type(uint224).max, "VotesProvisioner: max supply risks overflowing votes.");
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

    /**
     * @notice Public function to update the token price. Only the executor can make an update to the token price.
     */
    function updateTokenPrice(uint256 numerator, uint256 denominator) public virtual onlyExecutor {
        _updateTokenPrice(numerator, denominator);
    }

    /**
     * @notice Public function to update the token price numerator. Only executor can update.
     */
    function updateTokenPriceNumerator(uint256 numerator) public virtual onlyExecutor {
        _updateTokenPrice(numerator, 0);
    }

    /**
     * @notice Public function to update the token price. Only executor can update.
     */
    function updateTokenPriceDenominator(uint256 denominator) public virtual onlyExecutor {
        _updateTokenPrice(0, denominator);
    }

    /**
     * @dev Private function to update the tokenPrice numerator and denominator. Skips update of zero values (neither can
     * be set to zero).
     */
    function _updateTokenPrice(uint256 newNumerator, uint256 newDenominator) private {
        require(newNumerator <= 10e8, "VotesProvisioner: Numerator must be no greater than 10e8");
        require(newDenominator <= 10e3, "VotesProvisioner: Denominator must be no greater than 10e3");
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
        return supply > 0 ? _treasuryBalance() * multiplier / supply : 0;
    }

    function _valueAndRemainderPerToken(uint256 multiplier) internal view returns (uint256, uint256) {
        uint256 supply = totalSupply();
        uint256 balance = _treasuryBalance();
        return supply > 0 ?
            (
                balance * multiplier / supply,
                balance * multiplier % supply
            ) :
            (0, 0);
    }

    /**
     * @dev Internal function that measures the balance of the base asset in the Executor (needs to be overridden to
     * measure the chosen base asset properly)
     */
    function _treasuryBalance() internal view virtual returns (uint256);

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

    /**
     * @dev Internal function for processing the deposit. Calls _transferDepositToExecutor, which must be implemented in
     * an inheriting contract.
     */
    function _depositFor(address account, uint256 depositAmount) internal virtual returns (uint256) {
        require(_provisionMode != ProvisionModes.Governance, "VotesProvisioner: Deposits are not available.");
        require(account != address(0));
        require(depositAmount >= 0, "VotesProvisioner: Amount of base asset must be greater than zero.");
        uint256 tokenPriceNumerator = _tokenPrice.numerator;
        uint256 tokenPriceDenominator = _tokenPrice.denominator;
        // The "depositAmount" must be a multiple of the token price numerator
        require(
            depositAmount % tokenPriceNumerator == 0,
            "VotesProvisioner: Amount of base asset must be a multiple of the token price numerator."
        );
        // The current price per token must not exceed the current value per token, or the treasury will be at risk
        // NOTE: We can bypass this check in founding mode because no funds can leave the treasury yet through governance
        if (_provisionMode != ProvisionModes.Founding) {
            (uint256 vpt, uint256 remainder) = _valueAndRemainderPerToken(tokenPriceDenominator);
            require(
                ( vpt < tokenPriceNumerator ) ||
                ( vpt == tokenPriceNumerator && remainder == 0),
                "VotesProvisioner: Token price is too low."
            );
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
     * @dev Internal function for processing the withdrawal. Calls _transferWithdrawalToReciever, which must be
     * implemented in an inheriting contract.
     */
    function _withdraw(address account, address receiver, uint256 amount) internal virtual returns(uint256) {
        require(account != address(0), "VotesProvisioner: zero address cannot initiate withdrawal.");
        require(receiver != address(0), "VotesProvisioner: Cannot withdraw to zero address.");
        require(amount > 0, "VotesProvisioner: Amount of tokens withdrawing must be greater than zero.");

        uint256 withdrawAmount = _valuePerToken(amount); // [ (amount/supply) * treasuryBalance ]
        _burn(account, amount);
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