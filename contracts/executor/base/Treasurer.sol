// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {TimelockAvatar} from "./TimelockAvatar.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {IBalanceSharesManager} from "../interfaces/IBalanceSharesManager.sol";
import {BalanceShareIds} from "contracts/common/BalanceShareIds.sol";
import {SharesManager} from "contracts/shares/base/SharesManager.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

abstract contract Treasurer is TimelockAvatar, ITreasury, IERC6372, BalanceShareIds {
    using SafeERC20 for IERC20;
    using ERC165Checker for address;
    using Address for address;

    struct BalanceShares {
        IBalanceSharesManager _manager;
        bool _isEnabled;
    }

    /// @custom:storage-location erc7201:Treasurer.Storage
    struct TreasurerStorage {
        SharesManager _token;
        BalanceShares _balanceShares;
    }

    bytes32 private immutable TREASURER_STORAGE =
        keccak256(abi.encode(uint256(keccak256("Treasurer.Storage")) - 1)) & ~bytes32(uint256(0xff));

    function _getTreasurerStorage() private view returns (TreasurerStorage storage $) {
        bytes32 slot = TREASURER_STORAGE;
        assembly {
            $.slot := slot
        }
    }

    event BalanceSharesManagerUpdate(address oldBalanceSharesManager, address newBalanceSharesManager);
    event BalanceSharesInitialized(address balanceSharesManager, uint256 totalDeposits, uint256 depositsAllocated);
    event DepositRegistered(IERC20 quoteAsset, uint256 depositAmount);
    event WithdrawalProcessed(address receiver, uint256 sharesBurned, uint256 totalSharesSupply, IERC20[] tokens);

    error BalanceSharesInitializationCallFailed(uint256 index, bytes data);
    error OnlyToken();
    error DepositSharesAlreadyInitialized();
    error BalanceSharesManagerInterfaceNotSupported(address balanceSharesManager);
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
        address token_,
        address balanceSharesManager_,
        bytes[] memory balanceShareInitCalldatas
    ) internal onlyInitializing {
        TreasurerStorage storage $ = _getTreasurerStorage();
        // Token cannot be reset later, must be correct token on initialization
        $._token = SharesManager(token_);

        _setBalanceSharesManager(balanceSharesManager_);
        if (balanceSharesManager_ != address(0)) {
            for (uint256 i = 0; i < balanceShareInitCalldatas.length;) {
                balanceSharesManager_.functionCall(balanceShareInitCalldatas[i]);
            }
        }
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

    /**
     * Returns the address of the ERC20 token used for vote shares.
     */
    function token() public view returns (address _token) {
        _token = address(_getTreasurerStorage()._token);
    }

    /**
     * Returns the address of the contract used for balance shares management, or address(0) if no balance shares are
     * currently being used.
     */
    function balanceSharesManager() public view returns (address _balanceSharesManager) {
        _balanceSharesManager = address(_getTreasurerStorage()._balanceShares._manager);
    }

    /**
     * Sets the address for the balance shares manager contract.
     * @notice Only callable by the Executor itself.
     * @param newBalanceSharesManager The address of the new balance shares manager contract, which must implement the
     * IBalanceSharesManager interface.
     */
    function setBalanceSharesManager(address newBalanceSharesManager) external onlySelf {
        _setBalanceSharesManager(newBalanceSharesManager);
    }

    function _setBalanceSharesManager(address newBalanceSharesManager) internal {
        if (!newBalanceSharesManager.supportsInterface(type(IBalanceSharesManager).interfaceId)) {
            revert BalanceSharesManagerInterfaceNotSupported(newBalanceSharesManager);
        }

        BalanceShares storage $ = _getTreasurerStorage()._balanceShares;
        emit BalanceSharesManagerUpdate(address($._manager), newBalanceSharesManager);
        $._manager = IBalanceSharesManager(newBalanceSharesManager);
    }

    /**
     * Returns true if balance shares are enabled for this contract.
     */
    function balanceSharesEnabled() external view returns (bool isBalanceSharesEnabled) {
        BalanceShares storage $ = _getTreasurerStorage()._balanceShares;
        address manager = address($._manager);
        bool isEnabled = $._isEnabled;
        isBalanceSharesEnabled = isEnabled && manager != address(0);
    }

    /**
     * Enables the accounting for balance shares. Once enabled, it cannot be disabled except by setting the balance
     * shares manager address to address(0).
     * @notice This function is only callable by the Executor itself, or by an enabled module during that module's
     * execution of an Executor operation.
     * @param applyDepositSharesRetroactively If set to true, this will retroactively apply deposit share accounting to
     * the total amount of deposits registered so far.
     */
    function enableBalanceShares(
        bool applyDepositSharesRetroactively
    ) external onlySelfOrDuringModuleExecution {
        _enableBalanceShares(applyDepositSharesRetroactively);
    }

    function _enableBalanceShares(bool applyDepositSharesRetroactively) internal virtual {
        TreasurerStorage storage $ = _getTreasurerStorage();

        IBalanceSharesManager manager = $._balanceShares._manager;
        bool sharesEnabled = $._balanceShares._isEnabled;

        // Revert if balance shares are already initialized
        if (sharesEnabled) {
            revert DepositSharesAlreadyInitialized();
        }

        uint256 totalDeposits;
        uint256 depositsAllocated;

        if (applyDepositSharesRetroactively) {
            SharesManager _token = $._token;

            // Retrieve the deposit share amount
            uint256 totalSupply = _token.totalSupply();
            (uint256 quoteAmount, uint256 mintAmount) = _token.sharePrice();
            totalDeposits = Math.mulDiv(totalSupply, quoteAmount, mintAmount);

            // Allocate the deposit shares to the balance shares manager
            IERC20 quoteAsset = _token.quoteAsset();
            depositsAllocated = _allocateBalanceShare(
                manager,
                DEPOSITS_ID,
                quoteAsset,
                totalDeposits
            );
        }

        // Enable balance shares going forward
        $._balanceShares._isEnabled = true;

        emit BalanceSharesInitialized(address(manager), totalDeposits, depositsAllocated);
    }

    /**
     * @inheritdoc ITreasury
     * @notice Only callable by the shares token contract.
     */
    function registerDeposit(IERC20 quoteAsset, uint256 depositAmount) external payable virtual override onlyToken {
        _registerDeposit(quoteAsset, depositAmount);
    }

    function _registerDeposit(IERC20 quoteAsset, uint256 depositAmount) internal virtual {
        if (depositAmount == 0) revert InvalidDepositAmount();
        if (address(quoteAsset) == address(0) && msg.value != depositAmount) revert InvalidDepositAmount();

        BalanceShares storage $ = _getTreasurerStorage()._balanceShares;
        IBalanceSharesManager manager = $._manager;
        bool sharesEnabled = $._isEnabled;
        if (sharesEnabled) {
            _allocateBalanceShare(manager, DEPOSITS_ID, quoteAsset, depositAmount);
        }

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

    function _processWithdrawal(
        address receiver,
        uint256 sharesBurned,
        uint256 sharesTotalSupply,
        IERC20[] calldata tokens
    ) internal virtual {
        if (sharesTotalSupply > 0 && sharesBurned > 0) {
            // Iterate through the token addresses, sending proportional payouts (using address(0) for ETH)
            // TODO: Need to add the PROFT/DISTRIBUTIONS Balance share allocation to this function
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
     * @dev Internal helper for allocating an asset to the provided balance share manager and balanceShareId.
     */
    function _allocateBalanceShare(
        IBalanceSharesManager manager,
        uint256 balanceShareId,
        IERC20 asset,
        uint256 balanceIncreasedBy
    ) internal returns (uint256 amountToAllocate) {
        if (address(manager) != address(0)) {
            // Get allocation amount
            amountToAllocate = manager.getBalanceShareAllocationWithRemainder(
                balanceShareId,
                address(asset),
                balanceIncreasedBy
            );

            // Approve transfer amount
            asset.forceApprove(address(manager), amountToAllocate);

            // Allocate to the balance share
            manager.allocateToBalanceShareWithRemainder(
                balanceShareId,
                address(asset),
                balanceIncreasedBy
            );
        }
    }
}