// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ITreasury} from "src/executor/interfaces/ITreasury.sol";
import {ISharesOnboarder} from "../interfaces/ISharesOnboarder.sol";
import {ISharesToken} from "src/token/interfaces/ISharesToken.sol";
import {OwnableUpgradeable} from "src/utils/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC165Verifier} from "src/libraries/ERC165Verifier.sol";
import {ERC20Utils} from "src/libraries/ERC20Utils.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {BatchArrayChecker} from "src/utils/BatchArrayChecker.sol";

/**
 * @title SharesOnboarder
 * @author Ben Jett - @BCJdevelopment
 * @notice Manages funding parameters and deposit flows for permissionless onboarding to the DAO.
 */
abstract contract SharesOnboarder is OwnableUpgradeable, ISharesOnboarder {
    using SafeCast for *;
    using Math for uint256;
    using ERC165Verifier for address;

    /// @custom:storage-location erc7201:SharesOnboarder.Storage
    struct SharesOnboarderStorage {
        // Funding parameters
        ITreasury _treasury;
        uint48 _fundingBeginsAt;
        uint48 _fundingEndsAt;
        SharePrice _sharePrice;
        IERC20 _quoteAsset; // (address(0) for ETH)
        // Admins for pausing funding
        mapping(address admin => uint256 expiresAt) _admins;
    }

    // keccak256(abi.encode(uint256(keccak256("SharesOnboarder.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant SHARES_ONBOARDER_STORAGE =
        0xed8a854f633e6f341abfcf74ec385c7984ad70669f707fb05ac008e3eb7a8000;

    function _getSharesOnboarderStorage() private pure returns (SharesOnboarderStorage storage $) {
        assembly {
            $.slot := SHARES_ONBOARDER_STORAGE
        }
    }

    modifier onlyOwnerOrAdmin() {
        if (owner() != msg.sender) {
            (bool isAdmin,) = adminStatus(msg.sender);
            if (!isAdmin) {
                revert OwnableUnauthorizedAccount(msg.sender);
            }
        }
        _;
    }

    function __SharesOnboarder_init_unchained(bytes memory sharesOnboarderInitParams)
        internal
        virtual
        onlyInitializing
    {
        (
            address treasury_,
            address quoteAsset_,
            bool checkQuoteAssetInterfaceSupport_,
            SharePrice memory sharePrice_,
            uint256 fundingBeginsAt_,
            uint256 fundingEndsAt_
        ) = abi.decode(sharesOnboarderInitParams, (address, address, bool, SharePrice, uint256, uint256));

        _setTreasury(treasury_);
        _setQuoteAsset(quoteAsset_, checkQuoteAssetInterfaceSupport_);
        _setSharePrice(sharePrice_.quoteAmount, sharePrice_.mintAmount);
        _setFundingPeriods(fundingBeginsAt_, fundingEndsAt_);
    }

    /// @inheritdoc ISharesOnboarder
    function treasury() public view virtual override returns (ITreasury _treasury) {
        _treasury = _getSharesOnboarderStorage()._treasury;
    }

    /// @inheritdoc ISharesOnboarder
    function setTreasury(address newTreasury) external virtual override onlyOwner {
        _setTreasury(newTreasury);
    }

    function _setTreasury(address newTreasury) internal virtual {
        if (newTreasury == address(0) || newTreasury == address(this)) {
            revert InvalidTreasuryAddress(newTreasury);
        }

        newTreasury.checkInterface(type(ITreasury).interfaceId);

        SharesOnboarderStorage storage $ = _getSharesOnboarderStorage();
        emit TreasuryChange(address($._treasury), newTreasury);
        $._treasury = ITreasury(newTreasury);
    }

    /// @inheritdoc ISharesOnboarder
    function adminStatus(address account) public view virtual override returns (bool isAdmin, uint256 expiresAt) {
        expiresAt = _getSharesOnboarderStorage()._admins[account];
        isAdmin = block.timestamp > expiresAt;
    }

    /// @inheritdoc ISharesOnboarder
    function setAdminExpirations(
        address[] memory accounts,
        uint256[] memory expiresAts
    )
        external
        virtual
        override
        onlyOwner
    {
        BatchArrayChecker.checkArrayLengths(accounts.length, expiresAts.length);

        SharesOnboarderStorage storage $ = _getSharesOnboarderStorage();
        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[i];
            uint256 expiresAt = expiresAts[i];

            emit AdminStatusChange(account, $._admins[account], expiresAt);
            $._admins[account] = expiresAt;
        }
    }

    /// @inheritdoc ISharesOnboarder
    function quoteAsset() public view virtual override returns (IERC20 _quoteAsset) {
        _quoteAsset = _getSharesOnboarderStorage()._quoteAsset;
    }

    /// @inheritdoc ISharesOnboarder
    function setQuoteAsset(address newQuoteAsset, bool checkInterfaceSupport) external virtual override onlyOwner {
        _setQuoteAsset(newQuoteAsset, checkInterfaceSupport);
    }

    function _setQuoteAsset(address newQuoteAsset, bool checkInterfaceSupport) internal virtual {
        if (newQuoteAsset == address(this)) {
            revert CannotSetQuoteAssetToSelf();
        }
        if (newQuoteAsset != address(0) && checkInterfaceSupport) {
            newQuoteAsset.checkInterface(type(IERC20).interfaceId);
        }

        SharesOnboarderStorage storage $ = _getSharesOnboarderStorage();
        emit QuoteAssetChange(address($._quoteAsset), newQuoteAsset);
        $._quoteAsset = IERC20(newQuoteAsset);
    }

    /// @inheritdoc ISharesOnboarder
    function isFundingActive() public view virtual override returns (bool fundingActive) {
        (fundingActive,) = _isFundingActive();
    }

    function _isFundingActive() internal view virtual returns (bool fundingActive, ITreasury _treasury) {
        SharesOnboarderStorage storage $ = _getSharesOnboarderStorage();
        _treasury = $._treasury;
        uint256 fundingBeginsAt_ = $._fundingBeginsAt;
        uint256 fundingEndsAt_ = $._fundingEndsAt;

        // forgefmt: disable-next-item
        fundingActive =
            address(_treasury) != address(0) &&
            block.timestamp >= fundingBeginsAt_ &&
            block.timestamp < fundingEndsAt_;
    }

    /// @inheritdoc ISharesOnboarder
    function fundingPeriods() public view virtual override returns (uint256 fundingBeginsAt, uint256 fundingEndsAt) {
        SharesOnboarderStorage storage $ = _getSharesOnboarderStorage();
        (fundingBeginsAt, fundingEndsAt) = ($._fundingBeginsAt, $._fundingEndsAt);
    }

    /// @inheritdoc ISharesOnboarder
    function setFundingPeriods(
        uint256 newFundingBeginsAt,
        uint256 newFundingEndsAt
    )
        external
        virtual
        override
        onlyOwner
    {
        _setFundingPeriods(newFundingBeginsAt, newFundingEndsAt);
    }

    /// @inheritdoc ISharesOnboarder
    function pauseFunding() external virtual override onlyOwnerOrAdmin {
        // Using zero value leaves the fundingBeginsAt unchanged
        _setFundingPeriods(0, block.timestamp - 1);
        emit AdminPausedFunding(msg.sender);
    }

    /// @dev Internal method to set funding period timestamps. Passing value of zero leaves that timestamp unchanged.
    function _setFundingPeriods(uint256 newFundingBeginsAt, uint256 newFundingEndsAt) internal virtual {
        SharesOnboarderStorage storage $ = _getSharesOnboarderStorage();
        uint256 fundingBeginsAt = $._fundingBeginsAt;
        uint256 fundingEndsAt = $._fundingEndsAt;

        // Zero value signals to leave the current value unchanged.
        uint48 castedFundingBeginsAt =
            newFundingBeginsAt > 0 ? uint48(Math.min(newFundingBeginsAt, type(uint48).max)) : uint48(fundingBeginsAt);
        uint48 castedFundingEndsAt =
            newFundingEndsAt > 0 ? uint48(Math.min(newFundingEndsAt, type(uint48).max)) : uint48(fundingEndsAt);

        // Update in storage
        $._fundingBeginsAt = castedFundingBeginsAt;
        $._fundingEndsAt = castedFundingEndsAt;
        emit FundingPeriodChange(fundingBeginsAt, castedFundingBeginsAt, fundingEndsAt, castedFundingEndsAt);
    }

    /// @inheritdoc ISharesOnboarder
    function sharePrice() public view virtual override returns (uint128 quoteAmount, uint128 mintAmount) {
        SharePrice storage _sharePrice = _getSharesOnboarderStorage()._sharePrice;
        quoteAmount = _sharePrice.quoteAmount;
        mintAmount = _sharePrice.mintAmount;
    }

    /// @inheritdoc ISharesOnboarder
    function setSharePrice(uint256 newQuoteAmount, uint256 newMintAmount) external virtual override onlyOwner {
        _setSharePrice(newQuoteAmount, newMintAmount);
    }

    function _setSharePrice(uint256 newQuoteAmount, uint256 newMintAmount) internal virtual {
        // Casting checks for overflow
        uint128 castedQuoteAmount = newQuoteAmount.toUint128();
        uint128 castedMintAmount = newMintAmount.toUint128();

        SharesOnboarderStorage storage $ = _getSharesOnboarderStorage();
        emit SharePriceChange($._sharePrice.quoteAmount, newQuoteAmount, $._sharePrice.mintAmount, newMintAmount);
        $._sharePrice.quoteAmount = castedQuoteAmount;
        $._sharePrice.mintAmount = castedMintAmount;
    }

    /**
     * @notice Allows exchanging the depositAmount of quote asset for vote shares (if shares are currently available).
     * @param account The recipient account address to receive the newly minted share tokens.
     * @param depositAmount The amount of the quote asset being deposited by the msg.sender. Will mint
     * {sharePrice.mintAmount} votes for every {sharePrice.quoteAmount} amount of quote asset tokens. The depositAmount
     * must be an exact multiple of the {sharePrice.quoteAmount}. The  depositAmount also must match the msg.value if
     * the current quoteAsset is the native chain currency (address(0)).
     * @return totalSharesMinted The amount of vote share tokens minted to the account.
     */
    function depositFor(
        address account,
        uint256 depositAmount
    )
        public
        payable
        virtual
        returns (uint256 totalSharesMinted)
    {
        totalSharesMinted = _depositFor(account, depositAmount, msg.sender);
    }

    /**
     * @notice Same as the {depositFor} function, but uses the msg.sender as the recipient account of the newly minted
     * shares.
     */
    function deposit(uint256 depositAmount) public payable virtual returns (uint256 totalSharesMinted) {
        totalSharesMinted = _depositFor(msg.sender, depositAmount, msg.sender);
    }

    /**
     * @notice Additional function helper to use permit on the quote asset contract to approve and deposit in a single
     * transaction (if supported by the ERC20 quote asset).
     */
    function depositWithPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        virtual
        returns (uint256 totalSharesMinted)
    {
        if (spender != address(this)) {
            revert InvalidPermitSpender(spender, address(this));
        }
        IERC20Permit(address(quoteAsset())).permit(owner, spender, value, deadline, v, r, s);
        // The "owner" should be the receiver and the depositor
        totalSharesMinted = _depositFor(owner, value, owner);
    }

    /**
     * @dev Internal function for processing the deposit. Runs several checks before transferring the deposit to the
     * treasury and minting shares to the provided account address. Main checks:
     * - Funding is active (treasury is not zero address, and block.timestamp is in funding window)
     * - depositAmount cannot be zero, and must be an exact multiple of the quoteAmount
     * - msg.value is proper based on the current quoteAsset
     */
    function _depositFor(
        address account,
        uint256 depositAmount,
        address depositor
    )
        internal
        virtual
        returns (uint256 totalSharesMinted)
    {
        (bool fundingActive, ITreasury _treasury) = _isFundingActive();
        if (!fundingActive) {
            revert FundingIsNotActive();
        }

        // NOTE: The {_mint} function already checks to ensure the account address != address(0)
        if (depositAmount == 0) {
            revert InvalidDepositAmount();
        }

        // Share price must not be zero
        (uint256 quoteAmount, uint256 mintAmount) = sharePrice();
        if (quoteAmount == 0 || mintAmount == 0) {
            revert FundingIsNotActive();
        }

        // The "depositAmount" must be a multiple of the share price quoteAmount
        if (depositAmount % quoteAmount != 0) {
            revert InvalidDepositAmountMultiple();
        }

        // Transfer the deposit to the treasury
        IERC20 _quoteAsset = quoteAsset();
        uint256 msgValue;

        // For ETH, just transfer via the treasury "registerDeposit" function, so set the msg.value
        if (address(_quoteAsset) == address(0)) {
            if (depositAmount != msg.value) {
                revert ERC20Utils.InvalidMsgValue(depositAmount, msg.value);
            }
            msgValue = msg.value;
            // For ERC20, safe transfer from the depositor to the treasury
        } else {
            if (msg.value > 0) {
                revert ERC20Utils.InvalidMsgValue(0, msg.value);
            }
            SafeTransferLib.safeTransferFrom(_quoteAsset, depositor, address(_treasury), depositAmount);
        }

        // Set the total shares for the base contract to mint
        totalSharesMinted = depositAmount / quoteAmount * mintAmount;

        // Register the deposit on the treasury (sends funds to treasury, and treasury mints shares)
        _treasury.registerDeposit(account, _quoteAsset, depositAmount, totalSharesMinted);
        // assembly ("memory-safe") {
        //     // Call `registerDeposit{value: msgValue}(_quoteAsset, depositAmount)`
        //     mstore(0x14, _quoteAsset)
        //     mstore(0x34, depositAmount)
        //     // `registerDeposit(address,uint256)`
        //     mstore(0x00, 0x219dabeb000000000000000000000000)
        //     let result := call(gas(), _treasury, msgValue, 0x10, 0x44, 0, 0x40)
        //     // Restore free mem overwrite
        //     mstore(0x34, 0)
        //     if iszero(result) {
        //         let m := mload(0x40)
        //         returndatacopy(m, 0, returndatasize())
        //         revert(m, returndatasize())
        //     }
        // }

        // Mint the vote shares to the receiver AFTER sending funds to treasury to ensure no re-entrancy
        // token().mint(account, totalSharesMinted);

        emit Deposit(account, depositAmount, totalSharesMinted, depositor);
        // bytes32 _Deposit_eventSelector = Deposit.selector;
        // assembly ("memory-safe") {
        //     let m := mload(0x40) // Cache free mem pointer
        //     // Store event un-indexed data and log
        //     mstore(0, depositAmount)
        //     mstore(0x20, totalSharesMinted)
        //     mstore(0x40, depositor)
        //     log2(0, 0x60, _Deposit_eventSelector, account)
        //     mstore(0x40, m) // Restore free mem pointer
        // }
    }
}
