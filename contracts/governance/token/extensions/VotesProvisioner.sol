// SPDX-License-Identifier: MIT
// Primordium Contracts


pragma solidity ^0.8.0;

import "../Votes.sol";
import "../../executor/extensions/ExecutorVoteProvisions.sol";
import "../../utils/ExecutorControlled.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

using SafeMath for uint256;
using Address for address;


/**
 * @dev Extension of {Votes} to support decentralized DAO formation.
 *
 * Complete with deposit/withraw functionality.
 *
 * Anyone can mint vote tokens in exchange for the DAO's base asset. Any member can withdraw pro rata.
 */
abstract contract VotesProvisioner is Votes, ExecutorControlled {

    enum ProvisionModes {
        Founding, // Initial mode for tokens, allows deposits/withdrawals at all times
        Governance, // No deposits allowed during Governance mode
        Funding // deposits/withdrawals are fully allowed during Funding mode
    }

    ProvisionModes private _provisionMode;

    struct TokenPrice {
        uint128 numerator; // Minimum amount of base asset tokens required to mint {denominator} amount of votes.
        uint128 denominator; // Number of votes that can be minted per {numerator} count of base asset.
    }
    TokenPrice private _tokenPrice = TokenPrice(1, 1); // Defaults to 1 to 1

    IERC20 internal immutable _baseAsset; // The address for the DAO's base asset (address(0) for ETH)

    /**
     * @dev Emitted when the _tokenPrice is updated.
     */
    event TokenPriceChanged(
        uint128 previousNumerator,
        uint128 newNumerator,
        uint128 previousDenominator,
        uint128 newDenominator
    );

    /**
     * @dev Emitted when a deposit is made and tokens are minted.
     */
    event NewDeposit(address indexed account, uint256 amountDeposited, uint256 amountMinted);

    constructor(
        ExecutorVoteProvisions executor_,
        TokenPrice memory initialTokenPrice,
        IERC20 baseAsset_
    ) ExecutorControlled(executor_) {
        require(address(baseAsset_) != address(this), "VotesProvisioner: cannot make itself the base asset.");
        if (address(baseAsset_) != address(0)) {
            require(address(baseAsset_).isContract(), "VotesProvisioner: base asset must be a deployed contract.");
        }
        _baseAsset = baseAsset_;
        _updateTokenPrice(initialTokenPrice.numerator, initialTokenPrice.denominator);
    }

    /**
     * @notice Returns the address of the base asset (or address(0) if the base asset is ETH)
     */
    function baseAsset() public view returns(address) {
        return address(_baseAsset);
    }

    /**
     * @notice Returns the numerator and the denominator of the token price.
     *
     * The {numerator} is the minimum amount of the base asset tokens required to mint {denominator} amount of votes.
     */
    function tokenPrice() public view returns(uint128, uint128) {
        return (_tokenPrice.numerator, _tokenPrice.denominator);
    }

    /**
     * @notice Public function to update the token price. Only the executor can make an update to the token price.
     */
    function updateTokenPrice(uint128 numerator, uint128 denominator) public virtual onlyExecutor {
        _updateTokenPrice(numerator, denominator);
    }

    /**
     * @notice Public function to update the token price numerator. Only executor can update.
     */
    function updateTokenPriceNumerator(uint128 numerator) public virtual onlyExecutor {
        _updateTokenPrice(numerator, 0);
    }

    /**
     * @notice Public function to update the token price. Only executor can update.
     */
    function updateTokenPriceDenominator(uint128 denominator) public virtual onlyExecutor {
        _updateTokenPrice(0, denominator);
    }

    /**
     * @dev Private function to update the tokenPrice numerator and denominator. Skips update of zero values (neither can
     * be set to zero).
     */
    function _updateTokenPrice(uint128 newNumerator, uint128 newDenominator) private {
        uint128 prevNumerator = _tokenPrice.numerator;
        uint128 prevDenominator = _tokenPrice.denominator;
        if (newNumerator != 0) {
            _tokenPrice.numerator = newNumerator;
        }
        if (newDenominator != 0) {
            _tokenPrice.denominator = newDenominator;
        }
        emit TokenPriceChanged(prevNumerator, newNumerator, prevDenominator, newDenominator);
    }

    // function valuePerToken() public view returns(uint256) {
    //     return _treasuryBalance() / ;
    // }

    // function _treasuryBalance() internal view virtual returns(uint256);

    /**
     * @notice Allows exchanging the amount of base asset for votes (if votes are available for purchase).
     * @param account The account address to deposit to.
     * @param amount The amount of the base asset being deposited. Will mint tokenPrice.denominator votes for every
     * tokenPrice.numerator count of base asset tokens.
     * @dev This is abstract, and should be overridden to provide functionality based on the _baseAsset (ETH vs ERC20)
     * @return Amount of vote tokens minted.
     */
    function depositFor(address account, uint256 amount) public payable virtual returns(uint256);

    /**
     * @notice Calls {depositFor} with msg.sender as the account.
     * @param amount The amount of the base asset being deposited. Will mint tokenPrice.denominator votes for every
     * tokenPrice.numerator count of base asset tokens.
     */
    function deposit(uint256 amount) public payable virtual returns(uint256) {
        return depositFor(_msgSender(), amount);
    }

    /**
     * @notice Internal function that should be overridden with functionality to transfer the deposit to the Executor.
     */
    function _transferDepositToExecutor(address account, uint256 amount) internal virtual;

    /**
     * @dev
     */
    function _depositFor(address account, uint256 amount) internal virtual returns(uint256) {
        require(_provisionMode != ProvisionModes.Governance, "VotesProvisioner: Deposits are not available.");
        require(account != address(0));
        require(amount >= 0, "VotesProvisioner: Amount of base asset must be greater than zero.");
        uint128 tokenPriceNumerator = _tokenPrice.numerator;
        require(
            amount % tokenPriceNumerator == 0,
            "VotesProvisioner: Amount of base asset must be a multiple of the token price numerator."
        );
        uint256 mintAmount = amount / tokenPriceNumerator * _tokenPrice.denominator;
        _transferDepositToExecutor(account, amount);
        _mint(account, mintAmount);
        emit NewDeposit(account, amount, mintAmount);
        return mintAmount;
    }

    function withrawTo(address account, uint256 amount) public payable {

    }

    function _getExecutorVoteProvisions() internal view returns(ExecutorVoteProvisions) {
        return ExecutorVoteProvisions(payable(address(_executor)));
    }

}