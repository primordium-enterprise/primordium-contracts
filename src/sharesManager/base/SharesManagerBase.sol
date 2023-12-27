// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ITreasury} from "src/executor/interfaces/ITreasury.sol";
import {ISharesManager} from "../interfaces/ISharesManager.sol";
import {Ownable1Or2StepUpgradeable} from "src/utils/Ownable1Or2StepUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC165Verifier} from "src/libraries/ERC165Verifier.sol";
import {ERC20Utils} from "src/libraries/ERC20Utils.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {BatchArrayChecker} from "src/utils/BatchArrayChecker.sol";

abstract contract SharesManager is Ownable1Or2StepUpgradeable, ISharesManager {
    using SafeCast for *;
    using Math for uint256;
    using ERC165Verifier for address;

    bytes32 private immutable WITHDRAW_TO_TYPEHASH = keccak256(
        "WithdrawTo(address owner,address receiver,uint256 amount,address[] tokens,uint256 nonce,uint256 deadline)"
    );

    /// @custom:storage-location erc7201:SharesManager.Storage
    struct SharesManagerStorage {
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

    modifier onlyOwnerOrAdmin() {
        if (owner() != msg.sender) {
            (bool isAdmin,) = adminStatus(msg.sender);
            if (!isAdmin) {
                revert OwnableUnauthorizedAccount(msg.sender);
            }
        }
        _;
    }

    function __SharesManagerBase_init_unchained(bytes memory sharesManagerBaseInitParams)
        internal
        virtual
        onlyInitializing
    {
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

    /// @inheritdoc ISharesManager
    function treasury() public view virtual override returns (ITreasury _treasury) {
        _treasury = _getSharesManagerStorage()._treasury;
    }

    /// @inheritdoc ISharesManager
    function setTreasury(address newTreasury) external virtual override onlyOwner {
        _setTreasury(newTreasury);
    }

    function _setTreasury(address newTreasury) internal virtual {
        if (newTreasury == address(0) || newTreasury == address(this)) {
            revert ISharesManager.InvalidTreasuryAddress(newTreasury);
        }

        newTreasury.checkInterface(type(ITreasury).interfaceId);

        SharesManagerStorage storage $ = _getSharesManagerStorage();
        emit TreasuryChange(address($._treasury), newTreasury);
        $._treasury = ITreasury(newTreasury);
    }

    /// @inheritdoc ISharesManager
    function adminStatus(address account) public view virtual override returns (bool isAdmin, uint256 expiresAt) {
        expiresAt = _getSharesManagerStorage()._admins[account];
        isAdmin = block.timestamp > expiresAt;
    }

    /// @inheritdoc ISharesManager
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

        SharesManagerStorage storage $ = _getSharesManagerStorage();
        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[i];
            uint256 expiresAt = expiresAts[i];

            emit AdminStatusChange(account, $._admins[account], expiresAt);
            $._admins[account] = expiresAt;
        }
    }

    /// @inheritdoc ISharesManager
    function quoteAsset() public view virtual override returns (IERC20 _quoteAsset) {
        _quoteAsset = _getSharesManagerStorage()._quoteAsset;
    }

    /// @inheritdoc ISharesManager
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

        SharesManagerStorage storage $ = _getSharesManagerStorage();
        emit QuoteAssetChange(address($._quoteAsset), newQuoteAsset);
        $._quoteAsset = IERC20(newQuoteAsset);
    }

    /// @inheritdoc ISharesManager
    function isFundingActive() public view virtual override returns (bool fundingActive) {
        (fundingActive,) = _isFundingActive();
    }

    function _isFundingActive() internal view virtual returns (bool fundingActive, ITreasury _treasury) {
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

    /// @inheritdoc ISharesManager
    function fundingPeriods() public view virtual override returns (uint256 fundingBeginsAt, uint256 fundingEndsAt) {
        SharesManagerStorage storage $ = _getSharesManagerStorage();
        (fundingBeginsAt, fundingEndsAt) = ($._fundingBeginsAt, $._fundingEndsAt);
    }

    /// @inheritdoc ISharesManager
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

    /// @inheritdoc ISharesManager
    function pauseFunding() external virtual override onlyOwnerOrAdmin {
        // Using zero value leaves the fundingBeginsAt unchanged
        _setFundingPeriods(0, block.timestamp - 1);
        emit AdminPausedFunding(msg.sender);
    }

    /// @dev Internal method to set funding period timestamps. Passing value of zero leaves that timestamp unchanged.
    function _setFundingPeriods(uint256 newFundingBeginsAt, uint256 newFundingEndsAt) internal virtual {
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
        emit FundingPeriodChange(fundingBeginsAt, castedFundingBeginsAt, fundingEndsAt, castedFundingEndsAt);
    }

    /// @inheritdoc ISharesManager
    function sharePrice() public view virtual override returns (uint128 quoteAmount, uint128 mintAmount) {
        SharePrice storage _sharePrice = _getSharesManagerStorage()._sharePrice;
        quoteAmount = _sharePrice.quoteAmount;
        mintAmount = _sharePrice.mintAmount;
    }

    /// @inheritdoc ISharesManager
    function setSharePrice(uint256 newQuoteAmount, uint256 newMintAmount) external virtual override onlyOwner {
        _setSharePrice(newQuoteAmount, newMintAmount);
    }

    function _setSharePrice(uint256 newQuoteAmount, uint256 newMintAmount) internal virtual {
        // Casting checks for overflow
        uint128 castedQuoteAmount = newQuoteAmount.toUint128();
        uint128 castedMintAmount = newMintAmount.toUint128();

        SharesManagerStorage storage $ = _getSharesManagerStorage();
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

        // Register the deposit on the treasury (sending the funds there)
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
        totalSharesMinted = depositAmount / quoteAmount * mintAmount;

        // Mint the vote shares to the receiver AFTER sending funds to treasury to ensure no re-entrancy
        _mint(account, totalSharesMinted);

        // emit Deposit(account, depositAmount, totalSharesMinted, depositor);
        bytes32 _Deposit_eventSelector = Deposit.selector;
        assembly ("memory-safe") {
            let m := mload(0x40) // Cache free mem pointer
            // Store event un-indexed data and log
            mstore(0, depositAmount)
            mstore(0x20, totalSharesMinted)
            mstore(0x40, depositor)
            log2(_Deposit_eventSelector, account, 0, 0x60)
            mstore(0x40, m) // Restore free mem pointer
        }
    }

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
        public
        virtual
        override
        returns (uint256 totalSharesBurned)
    {
        totalSharesBurned = _withdraw(msg.sender, receiver, amount, tokens);
    }

    /**
     * @notice Same as the {withdrawTo} function, but uses the msg.sender as the receiver of all token withdrawals.
     */
    function withdraw(
        uint256 amount,
        IERC20[] calldata tokens
    )
        public
        virtual
        override
        returns (uint256 totalSharesBurned)
    {
        address account = msg.sender;
        totalSharesBurned = _withdraw(account, account, amount, tokens);
    }

    /**
     * @dev Allow withdrawal by EIP712 signature or EIP1271 for smart contracts.
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
        public
        virtual
        override
        returns (uint256 totalSharesBurned)
    {
        if (block.timestamp > deadline) {
            revert VotesExpiredSignature(deadline);
        }

        // Copy the tokens content to memory and hash
        bytes32 tokensContentHash;
        // @solidity memory-safe-assembly
        assembly {
            // Get free mem pointer
            let m := mload(0x40)
            let offset := tokens.offset
            // Store the total byte length of the array items (length * 32 bytes per item)
            let byteLength := mul(tokens.length, 0x20)
            // Allocate the memory
            mstore(m, add(m, byteLength))
            // Copy to memory for hashing
            calldatacopy(m, offset, byteLength)
            // Hash the packed items
            tokensContentHash := keccak256(m, byteLength)
        }

        bool valid = SignatureChecker.isValidSignatureNow(
            owner,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        WITHDRAW_TO_TYPEHASH, owner, receiver, amount, tokensContentHash, _useNonce(owner), deadline
                    )
                )
            ),
            signature
        );

        if (!valid) {
            revert VotesInvalidSignature();
        }

        totalSharesBurned = _withdraw(owner, receiver, amount, tokens);
    }

    /**
     * @dev Internal function for processing the withdrawal. Calls _transferWithdrawalToReciever, which must be
     * implemented in an inheriting contract.
     */
    function _withdraw(
        address account,
        address receiver,
        uint256 amount,
        IERC20[] calldata tokens
    )
        internal
        virtual
        returns (uint256 totalSharesBurned)
    {
        if (account == address(0)) {
            revert WithdrawFromZeroAddress();
        }

        if (receiver == address(0)) {
            revert WithdrawToZeroAddress();
        }

        if (amount == 0) {
            revert WithdrawAmountInvalid();
        }

        totalSharesBurned = amount;

        // Cache the total supply before burning
        uint256 totalSupply = totalSupply();

        // _burn checks for InsufficientBalance
        _burn(account, amount);

        // Transfer withdrawal funds AFTER burning tokens to ensure no re-entrancy
        treasury().processWithdrawal(account, receiver, amount, totalSupply, tokens);

        emit Withdrawal(account, receiver, totalSharesBurned, tokens);
    }
}
