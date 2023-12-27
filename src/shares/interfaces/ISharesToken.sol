// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ISharesManager} from "src/sharesManager/interfaces/ISharesManager.sol";

interface ISharesToken {

    event SharesManagerUpdate(address oldSharesManager, address newSharesManager);

    error UnauthorizedForSharesTokenOperation(address sender);
    error MaxSupplyTooLarge(uint256 maxSupplyLimit);

    function sharesManager() external view returns (ISharesManager);

    function setSharesManager(address newSharesManager) external;

    /**
     * Mints vote shares to an account.
     * @notice Only the owner or the shares manager can mint shares.
     * @param account The address to receive the newly minted shares.
     * @param amount The amount of vote shares to mint.
     */
    function mint(address account, uint256 amount) external;

    /**
     * @notice Maximum token supply. Updateable by the owner.
     */
    function maxSupply() external view returns (uint256);

    /**
     * Updates the max supply of vote tokens available to be minted by deposits during active funding. Only the owner
     * can set the max supply.
     * @dev The max supply is allowed to be set below the total supply of tokens, but the max supply cannot be set to an
     * amount greater than the max supply of the parent ERC20 contract.
     * @param newMaxSupply The new max supply.
     */
    function setMaxSupply(uint256 newMaxSupply) external;

}