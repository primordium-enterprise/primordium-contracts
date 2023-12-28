// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ERC20SnapshotsUpgradeable} from "./ERC20SnapshotsUpgradeable.sol";
import {ERC20VotesUpgradeable} from "./ERC20VotesUpgradeable.sol";
import {Ownable1Or2StepUpgradeable} from "src/utils/Ownable1Or2StepUpgradeable.sol";
import {ISharesToken} from "../interfaces/ISharesToken.sol";
import {IERC20Snapshots} from "../interfaces/IERC20Snapshots.sol";
import {ISharesOnboarder} from "src/sharesOnboarder/interfaces/ISharesOnboarder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ITreasury} from "src/executor/interfaces/ITreasury.sol";
import {ERC165Verifier} from "src/libraries/ERC165Verifier.sol";

abstract contract SharesToken is Ownable1Or2StepUpgradeable, ERC20VotesUpgradeable, ISharesToken {
    using ERC165Verifier for address;

    bytes32 private immutable WITHDRAW_TO_TYPEHASH = keccak256(
        "WithdrawTo(address owner,address receiver,uint256 amount,address[] tokens,uint256 nonce,uint256 deadline)"
    );

    /// @custom:storage-location erc7201:SharesToken.Storage
    struct SharesTokenStorage {
        uint256 _maxSupply;
        ITreasury _treasury;
    }

    // keccak256(abi.encode(uint256(keccak256("SharesToken.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant SHARES_TOKEN_STORAGE = 0x2bfe2ff30f11b7563932d40077aad82efd0d579cb39b513d651b54e229f07300;

    function _getSharesTokenStorage() private pure returns (SharesTokenStorage storage $) {
        assembly {
            $.slot := SHARES_TOKEN_STORAGE
        }
    }

    function __SharesToken_init_unchained(bytes memory sharesTokenInitParams) internal virtual onlyInitializing {
        (uint256 maxSupply_, address treasury_) = abi.decode(sharesTokenInitParams, (uint256, address));

        _setMaxSupply(maxSupply_);
        _setTreasury(treasury_);
    }

    /// @inheritdoc IERC20Snapshots
    function createSnapshot()
        external
        virtual
        override(IERC20Snapshots, ISharesToken)
        onlyOwner
        returns (uint256 newSnapshotId)
    {
        newSnapshotId = _createSnapshot();
    }

    /// @inheritdoc ISharesToken
    function treasury() public view returns (ITreasury _treasury) {
        _treasury = _getSharesTokenStorage()._treasury;
    }

    /// @inheritdoc ISharesToken
    function setTreasury(address newTreasury) external virtual override onlyOwner {
        _setTreasury(newTreasury);
    }

    function _setTreasury(address newTreasury) internal virtual {
        if (newTreasury == address(0) || newTreasury == address(this)) {
            revert InvalidTreasuryAddress(newTreasury);
        }

        newTreasury.checkInterface(type(ITreasury).interfaceId);

        SharesTokenStorage storage $ = _getSharesTokenStorage();
        emit TreasuryChange(address($._treasury), newTreasury);
        $._treasury = ITreasury(newTreasury);
    }

    /// @inheritdoc ISharesToken
    function mint(address account, uint256 amount) external virtual override onlyOwner {
        _mint(account, amount);
    }

    /// @inheritdoc ISharesToken
    function maxSupply()
        public
        view
        virtual
        override(ERC20SnapshotsUpgradeable, ISharesToken)
        returns (uint256 _maxSupply)
    {
        _maxSupply = _getSharesTokenStorage()._maxSupply;
    }

    /// @inheritdoc ISharesToken
    function setMaxSupply(uint256 newMaxSupply) external virtual onlyOwner {
        _setMaxSupply(newMaxSupply);
    }

    /**
     * @dev Internal function to update the max supply. We DO allow the max supply to be set below the current
     * totalSupply(), because this would allow a DAO to keep funding active but continue to reject deposits ABOVE the
     * max supply threshold of tokens minted.
     */
    function _setMaxSupply(uint256 newMaxSupply) internal virtual {
        // Max supply is limited by ERC20Snapshots
        uint256 maxSupplyLimit = super.maxSupply();
        if (newMaxSupply > maxSupplyLimit) {
            revert MaxSupplyTooLarge(maxSupplyLimit);
        }

        SharesTokenStorage storage $ = _getSharesTokenStorage();
        emit MaxSupplyChange($._maxSupply, newMaxSupply);
        $._maxSupply = newMaxSupply;
    }

    /// @inheritdoc ISharesToken
    function withdraw(uint256 amount, IERC20[] calldata tokens) public virtual returns (uint256 totalSharesBurned) {
        address account = msg.sender;
        totalSharesBurned = _withdraw(account, account, amount, tokens);
    }

    /// @inheritdoc ISharesToken
    function withdrawTo(
        address receiver,
        uint256 amount,
        IERC20[] calldata tokens
    )
        public
        virtual
        returns (uint256 totalSharesBurned)
    {
        totalSharesBurned = _withdraw(msg.sender, receiver, amount, tokens);
    }

    /// @inheritdoc ISharesToken
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
