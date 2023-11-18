// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {TimelockAvatar} from "./TimelockAvatar.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {Enum} from "contracts/common/Enum.sol";
import {SharesManager} from "contracts/shares/base/SharesManager.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract Treasurer is TimelockAvatar, ITreasury, IERC721Receiver, IERC1155Receiver {
    using SafeERC20 for IERC20;

    SharesManager internal immutable _token;

    // The total balance of the base asset that is allocated to Distributions, BalanceShares, etc.
    uint256 internal _stashedBalance;

    event DepositRegistered(IERC20 quoteAsset, uint256 depositAmount);
    event WithdrawalProcessed(address receiver, uint256 sharesBurned, uint256 totalSharesSupply, IERC20[] tokens);

    error OnlyToken();
    error ETHTransferFailed();
    error FailedToTransferBaseAsset(address to, uint256 amount);
    error InsufficientBaseAssetFunds(uint256 balanceTransferAmount, uint256 currentBalance);
    error InvalidBaseAssetOperation(address target, uint256 value, bytes data);
    error InvalidDepositAmount();

    modifier onlyToken() {
        _onlyToken();
        _;
    }

    function _onlyToken() private view {
        if (msg.sender != address(_token)) revert OnlyToken();
    }

    constructor(
        SharesManager token_
    ) {
        _token = token_;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, TimelockAvatar) returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(ITreasury).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Clock (as specified in EIP-6372) is set to match the token's clock. Fallback to block numbers if the token
     * does not implement EIP-6372.
     */
    function clock() public view virtual returns (uint48) {
        try _token.clock() returns (uint48 timepoint) {
            return timepoint;
        } catch {
            return Time.blockNumber();
        }
    }

    /**
     * @dev Machine-readable description of the clock as specified in EIP-6372.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual returns (string memory) {
        try _token.CLOCK_MODE() returns (string memory clockmode) {
            return clockmode;
        } catch {
            return "mode=blocknumber&from=default";
        }
    }

    function token() public view returns(address) {
        return address(_token);
    }

    /**
     * @notice Returns the current DAO balance of the base asset in the treasury.
     */
    function treasuryBalance() public view returns (uint256) {
        return _treasuryBalance();
    }

    function governanceInitialized(address asset, uint256 totalDeposits) external onlyToken {
        _governanceInitialized(asset, totalDeposits);
    }

    function _governanceInitialized(address asset, uint256 totalDeposits) internal virtual { }

    /**
     * @inheritdoc ITreasury
     * @notice Only callable by the shares token contract.
     */
    function registerDeposit(IERC20 quoteAsset, uint256 depositAmount) external payable virtual override onlyToken {
        _registerDeposit(quoteAsset, depositAmount);
    }

    /**
     * @dev Can override and call super._registerDeposit for additional checks/functionality
    */
    function _registerDeposit(IERC20 quoteAsset, uint256 depositAmount) internal virtual {
        if (depositAmount == 0) revert InvalidDepositAmount();
        if (address(quoteAsset) == address(0) && msg.value != depositAmount) revert InvalidDepositAmount();

        // TODO: Emit the DepositRegistered event
    }

    /**
     * @inheritdoc ITreasury
     * @notice Only callable by the shares token contract.
     */
    function processWithdrawal(
        address receiver,
        uint256 sharesBurned,
        uint256 sharesTotalSupply,
        IERC20[] calldata tokens
    ) external virtual override onlyToken {
        _processWithdrawal(receiver, sharesBurned, sharesTotalSupply, tokens);
    }

    /**
     * @dev Transfers proportional payouts for a withdrawal. Can override and call super._processWithdrawal for any
     * additional checks/functionality.
     */
    function _processWithdrawal(
        address receiver,
        uint256 sharesBurned,
        uint256 sharesTotalSupply,
        IERC20[] calldata tokens
    ) internal virtual {
        if (sharesTotalSupply > 0 && sharesBurned > 0) {
            // Iterate through the token addresses, sending proportional payouts (using address(0) for ETH)
            for (uint256 i = 0; i < tokens.length;) {
                uint256 tokenBalance;
                if (address(tokens[i]) == address(0)) {
                    tokenBalance = address(this).balance;
                } else {
                    tokenBalance = tokens[i].balanceOf(address(this));
                }

                uint256 payout = Math.mulDiv(tokenBalance, sharesBurned, sharesTotalSupply);

                if (payout > 0) {
                    if (address(tokens[i]) == address(0)) {
                        (bool success,) = receiver.call{value: payout}("");
                        if (!success) revert ETHTransferFailed();
                    } else {
                        tokens[i].safeTransfer(receiver, payout);
                    }
                }
                unchecked { ++i; }
            }
        }

        emit WithdrawalProcessed(receiver, sharesBurned, sharesTotalSupply, tokens);
    }

    /**
     * @dev An internal function to return the DAO treasury balance, minus any stashed funds.
     */
    function _treasuryBalance() internal view virtual returns (uint256) {
        return _baseAssetBalance() - _stashedBalance;
    }

    /**
     * @dev Before execution of any action on the Executor, confirm that base asset transfers do not exceed DAO balance,
     * and then update the balance to account for the transfer.
     */
    function _execute(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) internal virtual override {
        uint256 baseAssetTransferAmount = _checkExecutionBaseAssetTransfer(to, value, data);
        if (baseAssetTransferAmount > 0) {
            uint256 currentBalance = _treasuryBalance();
            // Revert if the attempted transfer amount is greater than the currentBalance
            if (baseAssetTransferAmount > currentBalance) {
                revert InsufficientBaseAssetFunds(baseAssetTransferAmount, currentBalance);
            }
            _processBaseAssetTransfer(baseAssetTransferAmount);
        }
        super._execute(to, value, data, operation);
    }

    /**
     * @dev Used in the _beforeExecute hook to check for base asset transfers. Needs to be overridden based on the base
     * asset type. This should return the amount being transferred from the Treasurer in the provided transaction so it
     * can be accounted for in the internal balance state.
     */
    function _checkExecutionBaseAssetTransfer(
        address target,
        uint256 value,
        bytes calldata data
    ) internal virtual returns (uint256 balanceBeingTransferred);

    /**
     * @dev An internal function that must be overridden to properly return the raw base asset balance.
     */
    function _baseAssetBalance() internal view virtual returns (uint256);

    /**
     * @dev Internal function to transfer an amount of the base asset to the specified address.
     */
    function _safeTransferBaseAsset(address to, uint256 amount) internal virtual;

    /**
     * @dev Used to process any internal accounting updates after transferring the base asset out of the treasury.
     */
    function _processBaseAssetTransfer(uint256 amount) internal virtual;

    /**
     * @dev Used to process any internal accounting updates after stashed funds are unstashed.
     */
    function _processReverseBaseAssetTransfer(uint256 amount) internal virtual;

    /**
     * @dev Internal function to transfer an amount of the base asset from the treasury balance.
     * NOTE: Calls "_processBaseAssetTransfer" for any internal accounting used.
     */
    function _transferBaseAsset(address to, uint256 amount) internal virtual {
        _processBaseAssetTransfer(amount);
        _safeTransferBaseAsset(to, amount);
    }

    function _stashBaseAsset(uint256 amount) internal virtual {
        _stashedBalance += amount;
    }

    function _unstashBaseAsset(uint256 amount) internal virtual {
        _stashedBalance -= amount;
    }

    function _transferBaseAssetToStash(uint256 amount) internal virtual {
        _stashBaseAsset(amount);
        _processBaseAssetTransfer(amount);
    }

    function _reclaimBaseAssetFromStash(uint256 amount) internal virtual {
        _unstashBaseAsset(amount);
        _processReverseBaseAssetTransfer(amount);
    }

    /**
     * @dev Internal function to transfer an amount of the base asset from the stashed balance.
     */
    function _transferStashedBaseAsset(address to, uint256 amount) internal virtual {
        _unstashBaseAsset(amount);
        _safeTransferBaseAsset(to, amount);
    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155Received}.
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155BatchReceived}.
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

}