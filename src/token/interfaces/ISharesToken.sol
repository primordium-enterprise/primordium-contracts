// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ITreasury} from "src/executor/interfaces/ITreasury.sol";
import {ISharesOnboarder} from "src/onboarder/interfaces/ISharesOnboarder.sol";
import {IERC20Snapshots} from "./IERC20Snapshots.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISharesToken is IERC20Snapshots {
    /**
     * @notice Emitted when the address of the shares onboarder is updated.
     */
    event SharesOnboarderUpdate(address oldSharesOnboarder, address newSharesOnboarder);

    /**
     * @notice Emitted when the max supply of votes is updated.
     * @param oldMaxSupply The previous max supply.
     * @param newMaxSupply The new max supply.
     */
    event MaxSupplyChange(uint256 oldMaxSupply, uint256 newMaxSupply);

    /**
     * @notice Emitted when a withdrawal is made and tokens are burned.
     * @param account The account address that votes were burned for.
     * @param receiver The receiver address that the withdrawal was sent to.
     * @param totalSharesBurned The amount of vote tokens burned from the account.
     * @param assets The ERC20 tokens withdrawn.
     */
    event Withdrawal(address indexed account, address receiver, uint256 totalSharesBurned, IERC20[] assets);

    event TreasuryChange(address oldTreasury, address newTreasury);

    error InvalidTreasuryAddress(address treasury);
    error TreasuryInterfaceNotSupported(address treasury);
    error WithdrawFromZeroAddress();
    error WithdrawToZeroAddress();
    error WithdrawAmountInvalid();
    error UnauthorizedForSharesTokenOperation(address sender);
    error MaxSupplyTooLarge(uint256 maxSupplyLimit);
    error SharesTokenExpiredSignature(uint256 deadline);
    error SharesTokenInvalidSignature();

    /// @inheritdoc IERC20Snapshots
    function createSnapshot() external returns (uint256 newSnapshotId);

    /**
     * Returns the address for the treasury that processes deposits and withdrawals (most-likely the DAO executor
     * contract).
     */
    function treasury() external view returns (ITreasury);

    /**
     * Sets the address of the treasury to register deposits and process withdrawals.
     * @notice Only the owner can update the treasury address.
     */
    function setTreasury(address newTreasury) external;

    /**
     * Mints vote shares to an account.
     * @notice Only the owner or the shares onboarder can mint shares.
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

    /**
     * @notice Allows burning the provided amount of vote tokens owned by the msg.sender and withdrawing the
     * proportional share of the provided tokens in the treasury. Assets are sent to the msg.sender.
     * @param amount The amount of vote shares to be burned.
     * @param tokens A list of token addresses to withdraw from the treasury. Use address(0) for the native currency,
     * such as ETH.
     * @return totalSharesBurned The amount of shares burned.
     */
    function withdraw(uint256 amount, IERC20[] calldata tokens) external returns (uint256 totalSharesBurned);

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
    )
        external
        returns (uint256 totalSharesBurned);

    /**
     * Withdraw to the receiver by EIP712 or EIP1271 signature.
     *
     * @param signature The signature is a packed bytes encoding of the ECDSA r, s, and v signature values.
     */
    function withdrawToBySig(
        address owner,
        address receiver,
        uint256 amount,
        IERC20[] calldata tokens,
        uint256 deadline,
        bytes memory signature
    )
        external
        returns (uint256 totalSharesBurned);
}
