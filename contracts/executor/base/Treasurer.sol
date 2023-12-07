// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {TimelockAvatar} from "./TimelockAvatar.sol";
import {ISharesManager} from "contracts/shares/interfaces/ISharesManager.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {IDistributor} from "../interfaces/IDistributor.sol";
import {IBalanceSharesManager} from "../interfaces/IBalanceSharesManager.sol";
import {BalanceShareIds} from "contracts/common/BalanceShareIds.sol";
import {SharesManager} from "contracts/shares/base/SharesManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC165Verifier} from "contracts/libraries/ERC165Verifier.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

abstract contract Treasurer is TimelockAvatar, ITreasury, BalanceShareIds {
    using SafeERC20 for IERC20;
    using ERC165Verifier for address;
    using Address for address;

    struct BalanceShares {
        IBalanceSharesManager _manager;
        bool _isEnabled;
    }

    /// @custom:storage-location erc7201:Treasurer.Storage
    struct TreasurerStorage {
        SharesManager _token;
        BalanceShares _balanceShares;
        IDistributor _distributor;
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
    event Withdrawal(
        address indexed account,
        address receiver,
        IERC20 asset,
        uint256 payout,
        uint256 distributionShareAllocation
    );
    event WithdrawalProcessed(
        address indexed account,
        uint256 sharesBurned,
        uint256 totalSharesSupply,
        address receiver,
        IERC20[] assets
    );
    event BalanceShareAllocated(
        IBalanceSharesManager indexed manager,
        uint256 indexed balanceShareId,
        IERC20 indexed asset,
        uint256 amountAllocated
    );

    error InvalidERC165InterfaceSupport(address _contract);
    error BalanceSharesInitializationCallFailed(uint256 index, bytes data);
    error OnlyToken();
    error DepositSharesAlreadyInitialized();
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
        bytes[] memory balanceShareInitCalldatas,
        address distributorImplementation,
        uint256 distributionClaimPeriod
    ) internal onlyInitializing {
        TreasurerStorage storage $ = _getTreasurerStorage();

        // Token cannot be reset later, must be correct token on initialization
        token_.checkInterfaces([
            type(ISharesManager).interfaceId,
            type(IERC20).interfaceId
        ]);
        $._token = SharesManager(token_);

        // Set the balance shares manager, and call any initialization functions
        _setBalanceSharesManager(balanceSharesManager_);
        if (balanceSharesManager_ != address(0) && balanceShareInitCalldatas.length > 0) {
            for (uint256 i = 0; i < balanceShareInitCalldatas.length;) {
                balanceSharesManager_.functionCall(balanceShareInitCalldatas[i]);
            }
        }

        // Check distributor interface
        authorizeDistributorImplementation(distributorImplementation);
        $._distributor = IDistributor(
            address(
                new ERC1967Proxy{salt: bytes32(uint256(uint160(distributorImplementation)))}(
                    distributorImplementation,
                    abi.encodeCall(IDistributor.initialize, (token_, distributionClaimPeriod))
                )
            )
        );

    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(ITreasury).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * Returns the address of the ERC20 token used for vote shares.
     */
    function token() public view returns (address _token) {
        _token = address(_getTreasurerStorage()._token);
    }

    /**
     * Returns the address of the contract used for distributions.
     */
    function distributor() public view returns (address _distributor) {
        return address(_getTreasurerStorage()._distributor);
    }

    /**
     * Creates a distribution on the distributor contract for the given amount. If there are existing balance share
     * accounts for distributions, the BPS share will be subtracted from the amount and allocated to the balance share
     * manager contract before initializing the distribution.
     */
    function createDistribution(
        uint256 clockStartTime,
        IERC20 asset,
        uint256 amount
    ) external virtual onlySelf {
        IDistributor _distributor = _getTreasurerStorage()._distributor;
        _createDistribution(_distributor, clockStartTime, asset, amount);
    }

    function _createDistribution(
        IDistributor _distributor,
        uint256 clockStartTime,
        IERC20 asset,
        uint256 amount
    ) internal virtual authorizeOperator(address(_distributor)) {
        // Allocate to the balance share
        amount -= _allocateBalanceShare(
            _getTreasurerStorage()._balanceShares._manager,
            DISTRIBUTIONS_ID,
            asset,
            amount
        );

        uint256 value = 0;
        if (address(asset) == address(0)) {
            value = amount;
        } else {
            asset.forceApprove(address(_distributor), amount);
        }

        _distributor.createDistribution(clockStartTime, address(asset), amount);
    }

    function authorizeDistributorImplementation(address newImplementation) public view virtual {
        newImplementation.checkInterface(type(IDistributor).interfaceId);
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
        newBalanceSharesManager.checkInterface(type(IBalanceSharesManager).interfaceId);

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
        address account,
        address receiver,
        uint256 sharesBurned,
        uint256 sharesTotalSupply,
        IERC20[] calldata assets
    ) external virtual override onlyToken {
        _processWithdrawal(account, receiver, sharesBurned, sharesTotalSupply, assets);
    }

    function _processWithdrawal(
        address account,
        address receiver,
        uint256 sharesBurned,
        uint256 sharesTotalSupply,
        IERC20[] calldata assets
    ) internal virtual {
        TreasurerStorage storage $ = _getTreasurerStorage();
        IBalanceSharesManager manager = $._balanceShares._manager;

        if (sharesTotalSupply > 0 && sharesBurned > 0) {
            // Iterate through the token addresses, sending proportional payouts (using address(0) for ETH)
            // TODO: Need to add the PROFT/DISTRIBUTIONS Balance share allocation to this function
            for (uint256 i = 0; i < assets.length;) {
                uint256 tokenBalance;
                if (address(assets[i]) == address(0)) {
                    tokenBalance = address(this).balance;
                } else {
                    tokenBalance = assets[i].balanceOf(address(this));
                }

                uint256 payout = Math.mulDiv(tokenBalance, sharesBurned, sharesTotalSupply);

                if (payout > 0) {
                    uint256 distributionShareAllocation = _allocateBalanceShare(
                        manager,
                        DISTRIBUTIONS_ID,
                        assets[i],
                        payout
                    );

                    payout -= distributionShareAllocation;

                    if (address(assets[i]) == address(0)) {
                        (bool success,) = receiver.call{value: payout}("");
                        if (!success) revert ETHTransferFailed();
                    } else {
                        assets[i].safeTransfer(receiver, payout);
                    }

                    emit Withdrawal(account, receiver, assets[i], payout, distributionShareAllocation);
                }

                unchecked { ++i; }
            }
        }

        emit WithdrawalProcessed(account, sharesBurned, sharesTotalSupply, receiver, assets);
    }

    /**
     * @dev Internal helper for allocating an asset to the provided balance share manager and balanceShareId.
     */
    function _allocateBalanceShare(
        IBalanceSharesManager manager,
        uint256 balanceShareId,
        IERC20 asset,
        uint256 balanceIncreasedBy
    ) internal returns (uint256 amountAllocated) {
        if (address(manager) != address(0)) {
            uint256 value;
            bool remainderIncreased;
            // Get allocation amount
            (amountAllocated, remainderIncreased) = manager.getBalanceShareAllocationWithRemainder(
                balanceShareId,
                address(asset),
                balanceIncreasedBy
            );

            // Only need to continue if balance actually increased, meaning balance share total BPS > 0
            if (amountAllocated > 0 || remainderIncreased) {

                // Approve transfer amount
                if (amountAllocated > 0 && address(asset) != address(0)) {
                    asset.forceApprove(address(manager), amountAllocated);
                }

                if (address(asset) == address(0)) {
                    value = amountAllocated;
                }

                // Allocate to the balance share
                manager.allocateToBalanceShareWithRemainder{value: value}(
                    balanceShareId,
                    address(asset),
                    balanceIncreasedBy
                );

                emit BalanceShareAllocated(manager, balanceShareId, asset, balanceIncreasedBy);

            }
        }
    }
}