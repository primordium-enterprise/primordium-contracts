// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (governance/utils/Votes.sol)
// Based on OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/ERC20Votes.sol)

pragma solidity ^0.8.20;

import {ERC20SnapshotsUpgradeable} from "./ERC20SnapshotsUpgradeable.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {SnapshotCheckpoints} from "src/libraries/SnapshotCheckpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

/**
 * @title ERC20VotesUpgradeable - ERC20 Votes implementation, using the ERC20SnapshotsUpgradeable as the base.
 * @author Ben Jett - @BCJdevelopment
 *
 * This module is essentially a merge of OpenZeppelin's {Votes} and {ERC20Votes} contracts, but this inherits directly
 * from the customized {ERC20SnapshotsUpgradeable} in this repository (which already implements historical
 * checkpoints for the ERC20 total supply).
 *
 * As in the OpenZeppelin modules (based on Compound), accounts MUST delegate (to themselves or another address) in
 * order for their votes to be counted.
 */
abstract contract ERC20VotesUpgradeable is IERC5805, ERC20SnapshotsUpgradeable {
    using SnapshotCheckpoints for SnapshotCheckpoints.Trace208;

    bytes32 private immutable DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @custom:storage-location erc7201:ERC20Votes.Storage
    struct ERC20VotesStorage {
        mapping(address account => address) _delegatee;
        mapping(address delegatee => SnapshotCheckpoints.Trace208) _delegateCheckpoints;
    }

    // keccak256(abi.encode(uint256(keccak256("ERC20Votes.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ERC20_VOTES_STORAGE = 0x109684a1287cc407d745bb820bf93a681ef38b14304190d1e8fea2ca0f881500;

    function _getERC20VotesStorage() private pure returns (ERC20VotesStorage storage $) {
        assembly {
            $.slot := ERC20_VOTES_STORAGE
        }
    }

    error VotesInvalidSignature();

    modifier noFutureLookup(uint256 timepoint) {
        uint256 currentClock = clock();
        if (timepoint >= currentClock) revert ERC20FutureLookup(currentClock);
        _;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        // forgefmt: disable-next-item
        return
            interfaceId == type(IVotes).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Get number of checkpoints for `account`.
     */
    function numVotesCheckpoints(address account) public view virtual returns (uint32) {
        return _numVotesCheckpoints(account);
    }

    /**
     * @dev Get number of checkpoints for `account`.
     */
    function _numVotesCheckpoints(address account) internal view virtual returns (uint32) {
        ERC20VotesStorage storage $ = _getERC20VotesStorage();
        return SafeCast.toUint32($._delegateCheckpoints[account].length());
    }

    /**
     * @dev Get the `pos`-th checkpoint for `account`.
     */
    function votesCheckpoints(
        address account,
        uint32 pos
    )
        public
        view
        virtual
        returns (SnapshotCheckpoints.Checkpoint208 memory)
    {
        return _getERC20VotesStorage()._delegateCheckpoints[account].at(pos);
    }

    /// @inheritdoc IVotes
    function getPastTotalSupply(uint256 timepoint)
        public
        view
        virtual
        override
        noFutureLookup(timepoint)
        returns (uint256)
    {
        ERC20SnapshotsStorage storage _snapshotsStorage = _getERC20SnapshotsStorage();
        return _snapshotsStorage._totalSupplyCheckpoints.upperLookupRecent(uint48(timepoint));
    }

    /**
     * @dev Returns the current amount of votes that `account` has.
     */
    function getVotes(address account) public view virtual returns (uint256) {
        ERC20VotesStorage storage $ = _getERC20VotesStorage();
        return $._delegateCheckpoints[account].latest();
    }

    /**
     * @dev Returns the amount of votes that `account` had at a specific moment in the past. If the `clock()` is
     * configured to use block numbers, this will return the value at the end of the corresponding block.
     *
     * Requirements:
     *
     * - `timepoint` must be in the past. If operating using block numbers, the block must be already mined.
     */
    function getPastVotes(
        address account,
        uint256 timepoint
    )
        public
        view
        virtual
        noFutureLookup(timepoint)
        returns (uint256)
    {
        ERC20VotesStorage storage $ = _getERC20VotesStorage();
        return $._delegateCheckpoints[account].upperLookupRecent(uint48(timepoint));
    }

    /**
     * @dev Returns the delegate that `account` has chosen.
     */
    function delegates(address account) public view virtual returns (address) {
        ERC20VotesStorage storage $ = _getERC20VotesStorage();
        return $._delegatee[account];
    }

    /**
     * @dev Delegates votes from the sender to `delegatee`.
     */
    function delegate(address delegatee) public virtual {
        address account = _msgSender();
        _delegate(account, delegatee);
    }

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        virtual
        override
    {
        if (block.timestamp > expiry) {
            revert VotesExpiredSignature(expiry);
        }
        address signer = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry))), v, r, s
        );
        _useCheckedNonce(signer, nonce);
        _delegate(signer, delegatee);
    }

    /**
     * @dev Delegates votes from `delegator` to `delegatee`. Supports ECDSA or EIP1271 signatures.
     *
     * @param signature The signature is a packed bytes encoding of the ECDSA r, s, and v signature values.
     */
    function delegateBySig(address delegatee, address signer, uint256 expiry, bytes memory signature) public virtual {
        if (block.timestamp > expiry) {
            revert VotesExpiredSignature(expiry);
        }

        bool valid = SignatureChecker.isValidSignatureNow(
            signer,
            _hashTypedDataV4(keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, _useNonce(signer), expiry))),
            signature
        );

        if (!valid) {
            revert VotesInvalidSignature();
        }

        _delegate(signer, delegatee);
    }

    /**
     * @dev Moves the delegation when tokens are transferred.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);
        _moveDelegateVotes(delegates(from), delegates(to), value);
    }

    /**
     * @dev Delegate all of `account`'s voting units to `delegatee`.
     *
     * Emits events {IVotes-DelegateChanged} and {IVotes-DelegateVotesChanged}.
     */
    function _delegate(address account, address delegatee) internal virtual {
        ERC20VotesStorage storage $ = _getERC20VotesStorage();
        address oldDelegate = delegates(account);
        $._delegatee[account] = delegatee;

        emit DelegateChanged(account, oldDelegate, delegatee);
        _moveDelegateVotes(oldDelegate, delegatee, _getVotingUnits(account));
    }

    /**
     * @dev Must return the voting units held by an account.
     */
    function _getVotingUnits(address account) internal view virtual returns (uint256) {
        return balanceOf(account);
    }

    /**
     * @dev Moves delegated votes from one delegate to another.
     */
    function _moveDelegateVotes(address from, address to, uint256 amount) private {
        ERC20VotesStorage storage $ = _getERC20VotesStorage();
        uint48 currentClock = clock();

        if (from != to && amount > 0) {
            // Modifications can be unchecked, because votes never exceed the checked balances
            if (from != address(0)) {
                // No snapshot used here
                (uint256 oldWeight, uint256 newWeight) =
                    $._delegateCheckpoints[from].push(currentClock, _subtractUnchecked, amount);
                emit DelegateVotesChanged(from, oldWeight, newWeight);
            }
            if (to != address(0)) {
                (uint256 oldWeight, uint256 newWeight) =
                    $._delegateCheckpoints[to].push(currentClock, _addUnchecked, amount);
                emit DelegateVotesChanged(to, oldWeight, newWeight);
            }
        }
    }
}
