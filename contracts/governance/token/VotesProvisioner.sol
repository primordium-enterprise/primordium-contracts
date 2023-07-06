// SPDX-License-Identifier: MIT
// Primordium Contracts


pragma solidity ^0.8.0;

import "./Votes.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev Extension of {Votes} to support the deposit/withraw functionality for new votes.
 *
 * Anyone can mint vote tokens in exchange for the DAO's base asset
 */
abstract contract VotesMint is Votes {

    IERC20 private immutable _baseAsset; // The address for the DAO's base ERC20 asset.

    uint256 private _tokenPrice; // The price of each base token, in the baseAsset units

    constructor(
        IERC20 baseAsset_,
        uint256 initialTokenPrice
    ) {
        _baseAsset = baseAsset_;
        _tokenPrice = initialTokenPrice;
    }

    function baseAsset() public view returns(IERC20) {
        return _baseAsset;
    }

    function deposit() public payable {

    }

    function withraw() public payable {

    }

}