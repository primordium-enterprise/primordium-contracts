// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {TimelockAvatar} from "./TimelockAvatar.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {IBalanceSharesManager} from "../interfaces/IBalanceSharesManager.sol";
import {Enum} from "contracts/common/Enum.sol";
import {ISharesManager} from "contracts/shares/interfaces/ISharesManager.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract Treasurer is TimelockAvatar, ITreasury, IERC6372 {
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:Treasurer.Storage
    struct TreasurerStorage {
        ISharesManager _token;
        IBalanceSharesManager _balanceSharesManager;
    }

    bytes32 private immutable TREASURER_STORAGE =
        keccak256(abi.encode(uint256(keccak256("Treasurer.Storage")) - 1)) & ~bytes32(uint256(0xff));

    function _getTreasurerStorage() private view returns (TreasurerStorage storage $) {
        bytes32 slot = TREASURER_STORAGE;
        assembly {
            $.slot := slot
        }
    }

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
        if (msg.sender != address(_getTreasurerStorage()._token)) {
            revert OnlyToken();
        }
    }

    function __Treasurer_init(
        ISharesManager token_
    ) internal onlyInitializing {
        TreasurerStorage storage $ = _getTreasurerStorage();
        $._token = token_;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(ITreasury).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Clock (as specified in EIP-6372) is set to match the token's clock. Fallback to block numbers if the token
     * does not implement EIP-6372.
     */
    function clock() public view virtual returns (uint48) {
        try _getTreasurerStorage()._token.clock() returns (uint48 timepoint) {
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
        try _getTreasurerStorage()._token.CLOCK_MODE() returns (string memory clockmode) {
            return clockmode;
        } catch {
            return "mode=blocknumber&from=default";
        }
    }

    function token() public view returns (address) {
        return address(_getTreasurerStorage()._token);
    }

    function initializeDeposits() external onlyDuringModuleExecution {
        _initializeDeposits();
    }


    function _initializeDeposits() internal virtual {
        // TODO: Ensure that deposits have not already been initialized
        // TODO: Retrieve the deposit share amount

        // uint256 totalSupply = _token.totalSupply();
        // (uint256 quoteAmount, uint256 mintAmount) = _token.sharePrice();
        // uint256 totalDeposits = Math.mulDiv(totalSupply, quoteAmount, mintAmount);

        // TODO: Need to transfer totalDeposits to the deposit share contract
        // TODO: Set state to show that deposits are now initialized
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

        emit DepositRegistered(quoteAsset, depositAmount);
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
}