// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {TimelockAvatar} from "./TimelockAvatar.sol";
import {ISharesOnboarder} from "src/sharesOnboarder/interfaces/ISharesOnboarder.sol";
import {ISharesToken} from "src/shares/interfaces/ISharesToken.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {IDistributor} from "../interfaces/IDistributor.sol";
import {IBalanceShareAllocations} from "balance-shares-protocol/interfaces/IBalanceShareAllocations.sol";
import {BalanceShareIds} from "src/common/BalanceShareIds.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {ERC20Utils} from "src/libraries/ERC20Utils.sol";
import {ERC165Verifier} from "src/libraries/ERC165Verifier.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

abstract contract Treasurer is TimelockAvatar, ITreasury, BalanceShareIds {
    using ERC20Utils for IERC20;
    using ERC165Verifier for address;
    using Address for address;

    // using "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol" from release v5.0.0
    // keccak256(type(ERC1967Proxy).creationCode)
    bytes32 private constant ERC1967PROXY_CREATIONCODE_HASH =
        0xea794f7b1e3861daf44227baf5c04b78eed1d62282bb4edb0b71ad749dd25d53;

    struct BalanceShares {
        IBalanceShareAllocations _balanceSharesManager;
        bool _isEnabled;
    }

    /// @custom:storage-location erc7201:Treasurer.Storage
    struct TreasurerStorage {
        ISharesToken _token;
        ISharesOnboarder _sharesOnboarder;
        BalanceShares _balanceShares;
        IDistributor _distributor;
    }

    // keccak256(abi.encode(uint256(keccak256("Treasurer.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant TREASURER_STORAGE = 0xb7ebf66fda01b54c58bbaa55f43c4ef3c56b215b2c961fe59d12adfff8f8fb00;

    function _getTreasurerStorage() private pure returns (TreasurerStorage storage $) {
        assembly {
            $.slot := TREASURER_STORAGE
        }
    }

    event SharesOnboarderUpdate(address oldSharesOnboarder, address newSharesOnboarder);
    event BalanceSharesManagerUpdate(address oldBalanceSharesManager, address newBalanceSharesManager);
    event BalanceSharesInitialized(address balanceSharesManager, uint256 totalDeposits, uint256 depositsAllocated);

    event BalanceShareAllocated(
        IBalanceShareAllocations indexed balanceSharesManager,
        uint256 indexed balanceShareId,
        IERC20 indexed asset,
        uint256 amountAllocated
    );

    error InvalidERC165InterfaceSupport(address _contract);
    error DistributorCreationFailed();
    error InvalidERC1967ProxyCreationCode();
    error BalanceSharesInitializationCallFailed(uint256 index, bytes data);
    error OnlyToken();
    error OnlySharesOnboarder();
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
        if (msg.sender != token()) {
            revert OnlyToken();
        }
    }

    modifier onlySharesOnboarder() {
        if (msg.sender != address(sharesOnboarder())) {
            revert OnlySharesOnboarder();
        }
        _;
    }

    /**
     * @dev The erc1967CreationCode must use the OpenZeppelin ERC1967Proxy.sol contract creation code, from version
     * v5.0.0, or else this initialization will fail. (This is used to reduce deployment bytecode size).
     */
    function __Treasurer_init_unchained(bytes memory treasurerInitParams) internal onlyInitializing {
        (
            address token_,
            address sharesOnboarder_,
            address balanceSharesManager_,
            bytes[] memory balanceShareInitCalldatas,
            bytes memory erc1967CreationCode, // Passed as argument to reduce deployment size
            address distributorImplementation_,
            uint256 distributionClaimPeriod_
        ) = abi.decode(treasurerInitParams, (address, address, address, bytes[], bytes, address, uint256));

        TreasurerStorage storage $ = _getTreasurerStorage();

        // Token cannot be reset later, must be correct token on initialization
        token_.checkInterfaces([type(ISharesToken).interfaceId, type(IERC20).interfaceId]);
        $._token = ISharesToken(token_);

        // Set the shares onboarder
        _setSharesOnboarder(sharesOnboarder_);

        // Set the balance shares manager, and call any initialization functions
        _setBalanceSharesManager(balanceSharesManager_);
        if (balanceSharesManager_ != address(0) && balanceShareInitCalldatas.length > 0) {
            for (uint256 i = 0; i < balanceShareInitCalldatas.length;) {
                balanceSharesManager_.functionCall(balanceShareInitCalldatas[i]);
            }
        }

        // Validate that creation code is OpenZeppelin 5.0.0 ERC1967Proxy creation code
        if (keccak256(erc1967CreationCode) != ERC1967PROXY_CREATIONCODE_HASH) {
            revert InvalidERC1967ProxyCreationCode();
        }

        // Check distributor implementation interface
        authorizeDistributorImplementation(distributorImplementation_);

        // Pack the proxy deployment bytecode with the constructor arguments
        bytes memory proxyDeploymentBytecode = abi.encodePacked(
            erc1967CreationCode,
            uint256(uint160(distributorImplementation_)),
            abi.encodeCall(IDistributor.setUp, (token_, distributionClaimPeriod_))
        );
        // Use the implementation address as the salt
        bytes32 salt = bytes32(uint256(uint160(distributorImplementation_)));

        // Create the proxy for the distributor
        address distributorProxy;
        assembly ("memory-safe") {
            distributorProxy :=
                create2(0, mload(add(0x20, proxyDeploymentBytecode)), mload(proxyDeploymentBytecode), salt)
        }

        if (distributorProxy == address(0)) {
            revert DistributorCreationFailed();
        }

        // Set the storage reference to the proxy address
        $._distributor = IDistributor(distributorProxy);

        // TODO: Remove old unused code after testing
        // $._distributor = IDistributor(
        //     address(
        //         new ERC1967Proxy{salt: bytes32(uint256(uint160(distributorImplementation)))}(
        //             distributorImplementation, abi.encodeCall(IDistributor.setUp, (token_, distributionClaimPeriod))
        //         )
        //     )
        // );
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        // forgefmt: disable-next-item
        return
            interfaceId == type(ITreasury).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * Returns the address of the ERC20 token used for vote shares.
     */
    function token() public view virtual returns (address _token) {
        _token = address(_getTreasurerStorage()._token);
    }

    function sharesOnboarder() public view virtual returns (ISharesOnboarder _sharesOnboarder) {
        _sharesOnboarder = _getTreasurerStorage()._sharesOnboarder;
    }

    function setSharesOnboarder(address newSharesOnboarder) public virtual onlySelf {
        _setSharesOnboarder(newSharesOnboarder);
    }

    function _setSharesOnboarder(address newSharesOnboarder) internal virtual {
        TreasurerStorage storage $ = _getTreasurerStorage();
        emit SharesOnboarderUpdate(address($._sharesOnboarder), newSharesOnboarder);
        $._sharesOnboarder = ISharesOnboarder(newSharesOnboarder);
    }

    /**
     * Returns the address of the contract used for distributions.
     */
    function distributor() public view virtual returns (address _distributor) {
        return address(_getTreasurerStorage()._distributor);
    }

    /**
     * Creates a distribution on the distributor contract for the given amount. If there are existing balance share
     * accounts for distributions, the BPS share will be subtracted from the amount and allocated to the balance share
     * balanceSharesManager contract before initializing the distribution.
     */
    function createDistribution(IERC20 asset, uint256 amount) external virtual onlySelf {
        _createDistribution(_getTreasurerStorage()._distributor, asset, amount);
    }

    function _createDistribution(
        IDistributor _distributor,
        IERC20 asset,
        uint256 amount
    )
        internal
        virtual
        authorizeOperator(address(_distributor))
    {
        TreasurerStorage storage $ = _getTreasurerStorage();

        uint256 snapshotId = $._token.createSnapshot();

        // Allocate to the balance share
        amount -= _allocateBalanceShare($._balanceShares._balanceSharesManager, DISTRIBUTIONS_ID, asset, amount);

        uint256 msgValue = asset.approveForExternalCall(address(_distributor), amount);

        _distributor.createDistribution{value: msgValue}(snapshotId, asset, amount);
    }

    function authorizeDistributorImplementation(address newImplementation) public view virtual {
        newImplementation.checkInterface(type(IDistributor).interfaceId);
    }

    /**
     * Returns the address of the contract used for balance shares management, or address(0) if no balance shares are
     * currently being used.
     */
    function balanceSharesManager() public view returns (address _balanceSharesManager) {
        _balanceSharesManager = address(_getTreasurerStorage()._balanceShares._balanceSharesManager);
    }

    /**
     * Sets the address for the balance shares manager contract.
     * @notice Only callable by the Executor itself.
     * @param newBalanceSharesManager The address of the new balance shares manager contract, which must implement the
     * IBalanceShareAllocations interface.
     */
    function setBalanceSharesManager(address newBalanceSharesManager) external onlySelf {
        _setBalanceSharesManager(newBalanceSharesManager);
    }

    function _setBalanceSharesManager(address newBalanceSharesManager) internal {
        newBalanceSharesManager.checkInterface(type(IBalanceShareAllocations).interfaceId);

        BalanceShares storage $ = _getTreasurerStorage()._balanceShares;
        emit BalanceSharesManagerUpdate(address($._balanceSharesManager), newBalanceSharesManager);
        $._balanceSharesManager = IBalanceShareAllocations(newBalanceSharesManager);
    }

    /**
     * Returns true if balance shares are enabled for this contract.
     */
    function balanceSharesEnabled() external view returns (bool isBalanceSharesEnabled) {
        BalanceShares storage $ = _getTreasurerStorage()._balanceShares;
        address manager = address($._balanceSharesManager);
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
    function enableBalanceShares(bool applyDepositSharesRetroactively) external onlySelfOrDuringModuleExecution {
        _enableBalanceShares(applyDepositSharesRetroactively);
    }

    function _enableBalanceShares(bool applyDepositSharesRetroactively) internal virtual {
        TreasurerStorage storage $ = _getTreasurerStorage();

        IBalanceShareAllocations manager = $._balanceShares._balanceSharesManager;
        bool sharesEnabled = $._balanceShares._isEnabled;

        // Revert if balance shares are already initialized
        if (sharesEnabled) {
            revert DepositSharesAlreadyInitialized();
        }

        uint256 totalDeposits;
        uint256 depositsAllocated;

        if (applyDepositSharesRetroactively) {
            ISharesOnboarder _sharesOnboarder = $._sharesOnboarder;

            // Retrieve the deposit share amount
            uint256 totalSupply = $._token.totalSupply();
            (uint256 quoteAmount, uint256 mintAmount) = _sharesOnboarder.sharePrice();
            totalDeposits = Math.mulDiv(totalSupply, quoteAmount, mintAmount);

            // Allocate the deposit shares to the balance shares manager
            IERC20 quoteAsset = _sharesOnboarder.quoteAsset();
            depositsAllocated = _allocateBalanceShare(manager, DEPOSITS_ID, quoteAsset, totalDeposits);
        }

        // Enable balance shares going forward
        $._balanceShares._isEnabled = true;

        emit BalanceSharesInitialized(address(manager), totalDeposits, depositsAllocated);
    }

    /**
     * @inheritdoc ITreasury
     * @dev Only callable by the shares onboarder contract.
     */
    function registerDeposit(
        address account,
        IERC20 quoteAsset,
        uint256 depositAmount,
        uint256 mintAmount
    )
        external
        payable
        virtual
        override
        onlySharesOnboarder
    {
        _registerDeposit(account, quoteAsset, depositAmount, mintAmount);
    }

    function _registerDeposit(
        address account,
        IERC20 quoteAsset,
        uint256 depositAmount,
        uint256 mintAmount
    )
        internal
        virtual
    {
        if (depositAmount == 0) {
            revert InvalidDepositAmount();
        }

        if (address(quoteAsset) == address(0) && msg.value != depositAmount) {
            revert InvalidDepositAmount();
        }

        TreasurerStorage storage $ = _getTreasurerStorage();

        BalanceShares storage _balanceShares = $._balanceShares;
        IBalanceShareAllocations manager = _balanceShares._balanceSharesManager;
        bool sharesEnabled = _balanceShares._isEnabled;
        if (sharesEnabled) {
            _allocateBalanceShare(manager, DEPOSITS_ID, quoteAsset, depositAmount);
        }

        // Mint the shares to the account
        $._token.mint(account, mintAmount);

        emit DepositRegistered(account, quoteAsset, depositAmount, mintAmount);
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
    )
        external
        virtual
        override
        onlyToken
    {
        _processWithdrawal(account, receiver, sharesBurned, sharesTotalSupply, assets);
    }

    function _processWithdrawal(
        address account,
        address receiver,
        uint256 sharesBurned,
        uint256 sharesTotalSupply,
        IERC20[] calldata assets
    )
        internal
        virtual
    {
        TreasurerStorage storage $ = _getTreasurerStorage();
        IBalanceShareAllocations manager = $._balanceShares._balanceSharesManager;

        if (sharesTotalSupply > 0 && sharesBurned > 0) {
            // Iterate through the token addresses, sending proportional payouts (using address(0) for ETH)
            // TODO: Need to add the PROFT/DISTRIBUTIONS Balance share allocation to this function
            for (uint256 i = 0; i < assets.length;) {
                uint256 tokenBalance = assets[i].getBalanceOf(address(this));

                uint256 payout = Math.mulDiv(tokenBalance, sharesBurned, sharesTotalSupply);

                if (payout > 0) {
                    uint256 distributionShareAllocation =
                        _allocateBalanceShare(manager, DISTRIBUTIONS_ID, assets[i], payout);

                    payout -= distributionShareAllocation;

                    assets[i].transferTo(receiver, payout);

                    emit WithdrawalAssetProcessed(account, receiver, assets[i], payout, distributionShareAllocation);
                }

                unchecked {
                    ++i;
                }
            }
        }

        emit WithdrawalProcessed(account, sharesBurned, sharesTotalSupply, receiver, assets);
    }

    /**
     * @dev Internal helper for allocating an asset to the provided balance share manager and balanceShareId.
     */
    function _allocateBalanceShare(
        IBalanceShareAllocations manager,
        uint256 balanceShareId,
        IERC20 asset,
        uint256 balanceIncreasedBy
    )
        internal
        returns (uint256 amountAllocated)
    {
        if (address(manager) != address(0)) {
            bool remainderIncreased;

            // Get allocation amount
            // manager.getBalanceShareAllocationWithRemainder(balanceShareId, asset, balanceIncreasedBy)
            bytes32 dataStart;
            bytes4 selector = manager.getBalanceShareAllocationWithRemainder.selector;
            assembly ("memory-safe") {
                dataStart := mload(0x40) // Cache the data to be used in the following call as well
                mstore(0x40, add(dataStart, 0x64)) // Need 100 bytes for calldata
                mstore(dataStart, selector)
                mstore(add(dataStart, 0x04), balanceShareId)
                mstore(add(dataStart, 0x24), asset)
                mstore(add(dataStart, 0x44), balanceIncreasedBy)
                // First call also checks that returndatasize is not zero, indicating the contract has code
                if iszero(
                    and( // The arguments of `and` are evaluated from right to left.
                    gt(returndatasize(), 0), call(gas(), manager, 0, dataStart, 0x64, 0, 0x40))
                ) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
                amountAllocated := mload(0)
                remainderIncreased := mload(0x20)
            }
            // (amountAllocated, remainderIncreased) = manager.getBalanceShareAllocationWithRemainder(
            //     balanceShareId,
            //     address(asset),
            //     balanceIncreasedBy
            // );

            // Only need to continue if balance actually increased, meaning balance share total BPS > 0
            if (amountAllocated > 0 || remainderIncreased) {
                // Approve transfer amount
                uint256 msgValue = asset.approveForExternalCall(address(manager), amountAllocated);

                // Allocate to the balance share
                // manager.allocateToBalanceShareWithRemainder{value: msgValue}(balanceShareId, asset,
                // balanceIncreasedBy)
                selector = manager.allocateToBalanceShareWithRemainder.selector;
                assembly ("memory-safe") {
                    // Update the selector
                    let c := mload(dataStart)
                    mstore(dataStart, or(selector, and(c, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff)))
                    if iszero(call(gas(), manager, msgValue, dataStart, 0x64, 0, 0)) {
                        returndatacopy(0, 0, returndatasize())
                        revert(0, returndatasize())
                    }
                }
                // manager.allocateToBalanceShareWithRemainder{value: msgValue}(
                //     balanceShareId,
                //     address(asset),
                //     balanceIncreasedBy
                // );

                emit BalanceShareAllocated(manager, balanceShareId, asset, balanceIncreasedBy);
                // bytes32 _BalanceShareAllocated_eventSelector = BalanceShareAllocated.selector;
                // assembly ("memory-safe") {
                //     mstore(0, balanceIncreasedBy)
                //     log4(0, 0x20, _BalanceShareAllocated_eventSelector, manager, balanceShareId, balanceIncreasedBy)
                // }
            }
        }
    }
}
