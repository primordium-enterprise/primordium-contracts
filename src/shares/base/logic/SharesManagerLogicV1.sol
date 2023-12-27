// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ITreasury} from "src/executor/interfaces/ITreasury.sol";
import {ISharesManager} from "../../interfaces/ISharesManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC165Verifier} from "src/libraries/ERC165Verifier.sol";
import {ERC20Utils} from "src/libraries/ERC20Utils.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {BatchArrayChecker} from "src/utils/BatchArrayChecker.sol";

/**
 * @title SharesManagerLogicV1
 * @author Ben Jett - @BCJdevelopment
 * @notice Externalizes some of the logic for {SharesManager} to reduce code size.
 */
library SharesManagerLogicV1 {
    using SafeCast for *;
    using Math for uint256;
    using ERC165Verifier for address;

    /// @custom:storage-location erc7201:SharesManager.Storage
    struct SharesManagerStorage {
        uint256 _maxSupply;
        // Funding parameters
        ITreasury _treasury;
        uint48 _fundingBeginsAt;
        uint48 _fundingEndsAt;
        /// @dev _sharePrice updates should always go through {_setSharesPrice} to avoid setting price to zero
        ISharesManager.SharePrice _sharePrice;
        IERC20 _quoteAsset; // (address(0) for ETH)
        mapping(address admin => uint256 expiresAt) _admins;
    }

    // keccak256(abi.encode(uint256(keccak256("SharesManager.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant SHARES_MANAGER_STORAGE = 0x215673db40ee2d172c8a31c3afde8d42c5c2dd6c697826d8d8447d186545ea00;

    function _getSharesManagerStorage() private pure returns (SharesManagerStorage storage $) {
        assembly {
            $.slot := SHARES_MANAGER_STORAGE
        }
    }

    /// @dev Optimizes initialization functions to avoid multiple DELEGATECALL's
    function setUp(bytes memory sharesManagerInitParams) public {
        (
            address treasury_,
            uint256 maxSupply_,
            address quoteAsset_,
            bool checkQuoteAssetInterfaceSupport_,
            ISharesManager.SharePrice memory sharePrice_,
            uint256 fundingBeginsAt_,
            uint256 fundingEndsAt_
        ) = abi.decode(
            sharesManagerInitParams, (address, uint256, address, bool, ISharesManager.SharePrice, uint256, uint256)
        );

        setTreasury(treasury_);
        setMaxSupply(maxSupply_);
        setQuoteAsset(quoteAsset_, checkQuoteAssetInterfaceSupport_);
        setSharePrice(sharePrice_.quoteAmount, sharePrice_.mintAmount);
        setFundingPeriods(fundingBeginsAt_, fundingEndsAt_);
    }

    function _treasury() internal view returns (ITreasury treasury_) {
        treasury_ = _getSharesManagerStorage()._treasury;
    }

    function setTreasury(address newTreasury) public {
        if (newTreasury == address(0) || newTreasury == address(this)) {
            revert ISharesManager.InvalidTreasuryAddress(newTreasury);
        }

        newTreasury.checkInterface(type(ITreasury).interfaceId);

        SharesManagerStorage storage $ = _getSharesManagerStorage();
        emit ISharesManager.TreasuryChange(address($._treasury), newTreasury);
        $._treasury = ITreasury(newTreasury);
    }

    function _maxSupply() internal view returns (uint256 maxSupply_) {
        maxSupply_ = _getSharesManagerStorage()._maxSupply;
    }

    function setMaxSupply(uint256 newMaxSupply) public {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
        emit ISharesManager.MaxSupplyChange($._maxSupply, newMaxSupply);
        $._maxSupply = newMaxSupply;
    }

    function _adminStatus(address account) internal view returns (bool isAdmin, uint256 expiresAt) {
        expiresAt = _getSharesManagerStorage()._admins[account];
        isAdmin = block.timestamp > expiresAt;
    }

    function setAdminExpirations(address[] memory accounts, uint256[] memory expiresAts) public {
        BatchArrayChecker.checkArrayLengths(accounts.length, expiresAts.length);

        SharesManagerStorage storage $ = _getSharesManagerStorage();
        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[i];
            uint256 expiresAt = expiresAts[i];

            emit ISharesManager.AdminStatusChange(accounts[i], $._admins[account], expiresAt);
            $._admins[account] = expiresAt;
        }
    }

    function _quoteAsset() internal view returns (IERC20 quoteAsset_) {
        quoteAsset_ = _getSharesManagerStorage()._quoteAsset;
    }

    function setQuoteAsset(address newQuoteAsset, bool checkInterfaceSupport) public {
        if (newQuoteAsset == address(this)) {
            revert ISharesManager.CannotSetQuoteAssetToSelf();
        }
        if (newQuoteAsset != address(0) && checkInterfaceSupport) {
            newQuoteAsset.checkInterface(type(IERC20).interfaceId);
        }

        SharesManagerStorage storage $ = _getSharesManagerStorage();
        emit ISharesManager.QuoteAssetChange(address($._quoteAsset), newQuoteAsset);
        $._quoteAsset = IERC20(newQuoteAsset);
    }

    function _isFundingActive() internal view returns (bool fundingActive, ITreasury treasury_) {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
        treasury_ = $._treasury;
        uint256 fundingBeginsAt_ = $._fundingBeginsAt;
        uint256 fundingEndsAt_ = $._fundingEndsAt;

        // forgefmt: disable-next-item
        fundingActive =
            address(treasury_) != address(0) &&
            block.timestamp >= fundingBeginsAt_ &&
            block.timestamp < fundingEndsAt_;
    }

    function _fundingPeriods() internal view returns (uint256 fundingBeginsAt, uint256 fundingEndsAt) {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
        (fundingBeginsAt, fundingEndsAt) = ($._fundingBeginsAt, $._fundingEndsAt);
    }

    function setFundingPeriods(uint256 newFundingBeginsAt, uint256 newFundingEndsAt) public {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
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
        emit ISharesManager.FundingPeriodChange(
            fundingBeginsAt, castedFundingBeginsAt, fundingEndsAt, castedFundingEndsAt
        );
    }

    function _sharePrice() internal view returns (uint128 quoteAmount, uint128 mintAmount) {
        ISharesManager.SharePrice storage _sp = _getSharesManagerStorage()._sharePrice;
        quoteAmount = _sp.quoteAmount;
        mintAmount = _sp.mintAmount;
    }

    function setSharePrice(uint256 newQuoteAmount, uint256 newMintAmount) public {
        // Casting checks for overflow
        uint128 castedQuoteAmount = newQuoteAmount.toUint128();
        uint128 castedMintAmount = newMintAmount.toUint128();

        SharesManagerStorage storage $ = _getSharesManagerStorage();
        emit ISharesManager.SharePriceChange(
            $._sharePrice.quoteAmount, newQuoteAmount, $._sharePrice.mintAmount, newMintAmount
        );
        $._sharePrice.quoteAmount = castedQuoteAmount;
        $._sharePrice.mintAmount = castedMintAmount;
    }

    /**
     * @dev Processes a given deposit amount (sending deposit to the treasury), and returns the amount to mint. Runs
     * several checks before transferring the deposit to the treasury. Main checks:
     * - Funding is active (treasury is not zero address, and block.timestamp is in funding window)
     * - depositAmount cannot be zero, and must be an exact multiple of the quoteAmount
     * - msg.value is proper based on the current quoteAsset
     */
    function processDepositAmount(
        uint256 depositAmount,
        address depositor
    )
        public
        returns (uint256 totalSharesToMint)
    {
        (bool fundingActive, ITreasury treasury_) = SharesManagerLogicV1._isFundingActive();
        if (!fundingActive) {
            revert ISharesManager.FundingIsNotActive();
        }

        // NOTE: The {_mint} function already checks to ensure the account address != address(0)
        if (depositAmount == 0) {
            revert ISharesManager.InvalidDepositAmount();
        }

        // Share price must not be zero
        (uint256 quoteAmount, uint256 mintAmount) = _sharePrice();
        if (quoteAmount == 0 || mintAmount == 0) {
            revert ISharesManager.FundingIsNotActive();
        }

        // The "depositAmount" must be a multiple of the share price quoteAmount
        if (depositAmount % quoteAmount != 0) {
            revert ISharesManager.InvalidDepositAmountMultiple();
        }

        // Transfer the deposit to the treasury
        IERC20 quoteAsset_ = _quoteAsset();
        uint256 msgValue;

        // For ETH, just transfer via the treasury "registerDeposit" function, so set the msg.value
        if (address(quoteAsset_) == address(0)) {
            if (depositAmount != msg.value) {
                revert ERC20Utils.InvalidMsgValue(depositAmount, msg.value);
            }
            msgValue = msg.value;
            // For ERC20, safe transfer from the depositor to the treasury
        } else {
            if (msg.value > 0) {
                revert ERC20Utils.InvalidMsgValue(0, msg.value);
            }
            SafeTransferLib.safeTransferFrom(quoteAsset_, depositor, address(treasury_), depositAmount);
        }

        // Register the deposit on the treasury
        assembly ("memory-safe") {
            // Call `registerDeposit{value: msgValue}(quoteAsset_, depositAmount)`
            mstore(0x14, quoteAsset_)
            mstore(0x34, depositAmount)
            // `registerDeposit(address,uint256)`
            mstore(0x00, 0x219dabeb000000000000000000000000)
            let result := call(gas(), treasury_, msgValue, 0x10, 0x44, 0, 0x40)
            // Restore free mem overwrite
            mstore(0x34, 0)
            if iszero(result) {
                let m := mload(0x40)
                returndatacopy(m, 0, returndatasize())
                revert(m, returndatasize())
            }
        }

        // Set the total shares for the base contract to mint
        totalSharesToMint = depositAmount / quoteAmount * mintAmount;
    }
}
