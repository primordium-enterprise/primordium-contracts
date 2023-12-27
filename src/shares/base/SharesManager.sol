// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {SharesManagerLogicV1} from "./logic/SharesManagerLogicV1.sol";
import {ERC20SnapshotsUpgradeable} from "./ERC20SnapshotsUpgradeable.sol";
import {ERC20VotesUpgradeable} from "./ERC20VotesUpgradeable.sol";
import {ISharesManager} from "../interfaces/ISharesManager.sol";
import {IERC20Snapshots} from "../interfaces/IERC20Snapshots.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {ITreasury} from "src/executor/interfaces/ITreasury.sol";
import {OwnableUpgradeable} from "src/utils/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ERC20Utils} from "src/libraries/ERC20Utils.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC165Verifier} from "src/libraries/ERC165Verifier.sol";
import {BatchArrayChecker} from "src/utils/BatchArrayChecker.sol";

/**
 * @title SharesManager - Contract responsible for managing permissionless deposits and withdrawals (rage quit).
 *
 * @dev Extends the ERC20Votes to access the internal _mint and _burn functionalities. Deposits and withdrawals are
 * processed through the specified "treasury" address (usually a DAO executor contract).
 *
 * The owner (also likely the DAO executor contract) can update the funding period, set the treasury address for where
 * to send the deposits and process the withdrawals from. The owner can also update the share price and the quote asset
 * (an ERC20 address or address(0) for native ETH) for the permissionless funding.
 *
 * Anyone can mint vote tokens in exchange for the DAO's quote asset as long as funding is active. Any member can
 * withdraw (rage quit) pro rata at any time.
 *
 * ERC2771 Context is not used in the deposit/withdrawal functions of this contract. The initial assumption is that each
 * depositor or withdrawer should pay their own gas fees, or optionally they can use the signed operations.
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract SharesManager is OwnableUpgradeable, ERC20VotesUpgradeable, ISharesManager {
    using Math for uint256;
    using SafeCast for *;
    using ERC165Verifier for address;

    bytes32 private immutable WITHDRAW_TO_TYPEHASH = keccak256(
        "WithdrawTo(address owner,address receiver,uint256 amount,address[] tokens,uint256 nonce,uint256 deadline)"
    );

    modifier onlyOwnerOrAdmin() {
        if (owner() != msg.sender) {
            (bool isAdmin,) = adminStatus(msg.sender);
            if (!isAdmin) {
                revert OwnableUnauthorizedAccount(msg.sender);
            }
        }
        _;
    }

    function __SharesManager_init_unchained(bytes memory sharesManagerInitParams) internal virtual onlyInitializing {
        SharesManagerLogicV1.setUp(sharesManagerInitParams);
    }

    /// @inheritdoc IERC20Snapshots
    function createSnapshot() external virtual override onlyOwner returns (uint256 newSnapshotId) {
        newSnapshotId = _createSnapshot();
    }

    /// @inheritdoc ISharesManager
    function mint(address account, uint256 amount) external virtual override onlyOwner {
        _mint(account, amount);
    }

    /// @inheritdoc ISharesManager
    function treasury() public view virtual override returns (ITreasury _treasury) {
        _treasury = SharesManagerLogicV1._treasury();
    }

    /// @inheritdoc ISharesManager
    function setTreasury(address newTreasury) external virtual override onlyOwner {
        _setTreasury(newTreasury);
    }

    function _setTreasury(address newTreasury) internal virtual {
        SharesManagerLogicV1.setTreasury(newTreasury);
    }

    /// @inheritdoc ISharesManager
    /// @dev Overridden to return the updateable _maxSupply
    function maxSupply()
        public
        view
        virtual
        override(ISharesManager, ERC20SnapshotsUpgradeable)
        returns (uint256 _maxSupply)
    {
        _maxSupply = SharesManagerLogicV1._maxSupply();
    }

    /// @inheritdoc ISharesManager
    function setMaxSupply(uint256 newMaxSupply) external virtual onlyOwner {
        _setMaxSupply(newMaxSupply);
    }

    /**
     * @dev Internal function to update the max supply.
     * We DO allow the max supply to be set below the current totalSupply(), because this would allow a DAO to keep
     * funding active but continue to reject deposits ABOVE the max supply threshold of tokens minted.
     */
    function _setMaxSupply(uint256 newMaxSupply) internal virtual {
        // Max supply is limited by ERC20Snapshots
        uint256 maxSupplyLimit = super.maxSupply();
        if (newMaxSupply > maxSupplyLimit) {
            revert MaxSupplyTooLarge(maxSupplyLimit);
        }

        SharesManagerLogicV1.setMaxSupply(newMaxSupply);
    }

    /// @inheritdoc ISharesManager
    function adminStatus(address account) public view virtual override returns (bool isAdmin, uint256 expiresAt) {
        (isAdmin, expiresAt) = SharesManagerLogicV1._adminStatus(account);
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
        SharesManagerLogicV1.setAdminExpirations(accounts, expiresAts);
    }

    /// @inheritdoc ISharesManager
    function quoteAsset() public view virtual override returns (IERC20 _quoteAsset) {
        _quoteAsset = SharesManagerLogicV1._quoteAsset();
    }

    /// @inheritdoc ISharesManager
    function setQuoteAsset(address newQuoteAsset, bool checkInterfaceSupport) external virtual override onlyOwner {
        _setQuoteAsset(newQuoteAsset, checkInterfaceSupport);
    }

    function _setQuoteAsset(address newQuoteAsset, bool checkInterfaceSupport) internal virtual {
        SharesManagerLogicV1.setQuoteAsset(newQuoteAsset, checkInterfaceSupport);
    }

    /// @inheritdoc ISharesManager
    function isFundingActive() public view virtual override returns (bool fundingActive) {
        (fundingActive,) = SharesManagerLogicV1._isFundingActive();
    }

    /// @inheritdoc ISharesManager
    function fundingPeriods() public view virtual override returns (uint256 fundingBeginsAt, uint256 fundingEndsAt) {
        (fundingBeginsAt, fundingEndsAt) = SharesManagerLogicV1._fundingPeriods();
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
        SharesManagerLogicV1.setFundingPeriods(newFundingBeginsAt, newFundingEndsAt);
    }

    /// @inheritdoc ISharesManager
    function sharePrice() public view virtual override returns (uint128 quoteAmount, uint128 mintAmount) {
        (quoteAmount, mintAmount) = SharesManagerLogicV1._sharePrice();
    }

    /// @inheritdoc ISharesManager
    function setSharePrice(uint256 newQuoteAmount, uint256 newMintAmount) external virtual override onlyOwner {
        _setSharePrice(newQuoteAmount, newMintAmount);
    }

    function _setSharePrice(uint256 newQuoteAmount, uint256 newMintAmount) internal virtual {
        SharesManagerLogicV1.setSharePrice(newQuoteAmount, newMintAmount);
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
        totalSharesMinted = SharesManagerLogicV1.processDepositAmount(depositAmount, depositor);
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
