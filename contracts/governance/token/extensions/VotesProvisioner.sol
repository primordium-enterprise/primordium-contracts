// SPDX-License-Identifier: MIT
// Primordium Contracts


pragma solidity ^0.8.0;

import "../Votes.sol";
import "../../utils/ExecutorControlled.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

    IERC20 private immutable _baseAsset; // The address for the DAO's base ERC20 asset.

    uint256 private _tokenPrice; // The price of each base token, in the baseAsset units

    constructor(
        Executor executor_,
        IERC20 baseAsset_,
        uint256 initialTokenPrice
    ) ExecutorControlled(executor_) {
        _baseAsset = baseAsset_;
        _tokenPrice = initialTokenPrice;
    }

    function baseAsset() public view returns(address) {
        return address(_baseAsset);
    }

    function _preDeposit(uint256 amount) internal virtual {
        require(_provisionMode != ProvisionModes.Governance, "VotesProvisioner: Deposits are not available.");
        require(amount > 0, "VotesProvisioner: Amount of base asset must be greater than zero.");
    }

    function deposit() public payable virtual {
        require(address(_baseAsset) == address(0), "VotesProvisioner: Base asset is not set to ETH.");
        _preDeposit(msg.value);
    }

    function deposit(uint256 amount) public virtual {
        require(address(_baseAsset) != address(0), "VotesProvisioner: Base asset is set to ETH.");
        _preDeposit(amount);
    }

    function withraw() public payable {

    }

}