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

    uint256 private _tokenPrice; // The amount of base asset for 1 vote

    IERC20 internal immutable _baseAsset; // The address for the DAO's base asset (address(0) for ETH)

    /**
     * @dev Emitted when the _tokenPrice is updated.
     */
    event TokenPriceChanged(uint256 previousTokenPrice, uint256 newTokenPrice);

    constructor(
        ExecutorVoteProvisions executor_,
        uint256 initialTokenPrice,
        IERC20 baseAsset_
    ) ExecutorControlled(executor_) {
        require(address(baseAsset_) != address(this), "VotesProvisioner: cannot make itself the base asset.");
        if (address(baseAsset_) != address(0)) {
            require(address(baseAsset_).isContract(), "VotesProvisioner: base asset must be a deployed contract.");
        }
        _baseAsset = baseAsset_;
        _updateTokenPrice(initialTokenPrice);
    }

    /**
     * @notice Returns the address of the base asset (or address(0) if the base asset is ETH)
     */
    function baseAsset() public view returns(address) {
        return address(_baseAsset);
    }

    /**
     * @notice Returns the token price of each vote, quoted in the base asset.
     */
    function tokenPrice() public view returns(uint256) {
        return _tokenPrice;
    }

    /**
     * @notice Public function to update the token price. Only the executor can make an update to the token price.
     */
    function updateTokenPrice(uint256 newTokenPrice) public virtual onlyExecutor {
        _updateTokenPrice(newTokenPrice);
    }

    /**
     * @dev Private function to update the token price. Requires that the token price be greater than zero.
     */
    function _updateTokenPrice(uint256 newTokenPrice) private {
        require(newTokenPrice > uint256(0), "VotesProvisioner: Token price must be greater than zero.");
        emit TokenPriceChanged(_tokenPrice, newTokenPrice);
        _tokenPrice = newTokenPrice;
    }

    modifier depositRequirements(uint256 amount) virtual {
        require(_provisionMode != ProvisionModes.Governance, "VotesProvisioner: Deposits are not available.");
        require(amount >= _tokenPrice, "VotesProvisioner: Amount of base asset must be greater than zero.");
        require(
            amount % _tokenPrice == uint256(0),
            "VotesProvisioner: Amount of base asset must be a multiple of the token price."
        );
        _;
    }

    function depositFor(address account) public payable virtual depositRequirements(msg.value) {
        require(address(_baseAsset) == address(0), "VotesProvisioner: Base asset is not set to ETH.");
        uint256 mintAmount = _getDepositMintAmount(msg.value);
        executor().call{value: msg.value}("");
        _getExecutorVoteProvisions().deposit(msg.value);
        _mint(account, mintAmount);

    }

    function depositFor(address account, uint256 amount) public virtual depositRequirements(amount) {
        require(address(_baseAsset) != address(0), "VotesProvisioner: Base asset is set to ETH.");
    }

    function _getDepositMintAmount(uint256 amount) private view returns(uint256) {
        return amount / _tokenPrice;
    }

    function withraw() public payable {

    }

    function _getExecutorVoteProvisions() private view returns(ExecutorVoteProvisions) {
        return ExecutorVoteProvisions(payable(address(_executor)));
    }

}