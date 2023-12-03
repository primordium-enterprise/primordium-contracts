// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (governance/utils/Votes.sol)
// Based on OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/ERC20Votes.sol)

pragma solidity ^0.8.20;

import {ERC20CheckpointsUpgradeable} from "./ERC20CheckpointsUpgradeable.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
// import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

/**
 * @title ERC20VotesUpgradeable - ERC20 Votes implementation, using the ERC20CheckpointsUpgradeable as the base.
 *
 * This module is essentially a merge of OpenZeppelin's {Votes} and {ERC20Votes} contracts, but this inherits directly
 * from the customized {ERC20CheckpointsUpgradeable} in this repository (which already implements historical
 * checkpoints for the ERC20 total supply).
 *
 * As in the OpenZeppelin modules (based on Compound), accounts MUST delegate (to themselves or another address) in
 * order for their votes to be counted.
 *
 * @author Ben Jett - @BCJdevelopment
 *
 */
abstract contract ERC20VotesUpgradeable is IERC5805, ERC20CheckpointsUpgradeable {
    using Checkpoints for Checkpoints.Trace208;

    bytes32 public immutable DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegator,address delegatee,uint256 nonce,uint256 deadline)");

    /// @custom:storage-location erc7201:ERC20Votes.Storage
    struct ERC20VotesStorage {
        mapping(address account => address) _delegatee;

        mapping(address delegatee => Checkpoints.Trace208) _delegateCheckpoints;
    }

    bytes32 private immutable ERC20_VOTES_STORAGE =
        keccak256(abi.encode(uint256(keccak256("ERC20Votes.Storage")) - 1)) & ~bytes32(uint256(0xff));

    function _getVotesStorage() private view returns (ERC20VotesStorage storage $) {
        bytes32 erc20VotesStorageSlot = ERC20_VOTES_STORAGE;
        assembly {
            $.slot := erc20VotesStorageSlot
        }
    }

    error VotesInvalidSignature();

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC5805).interfaceId ||
            interfaceId == type(IVotes).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Get number of checkpoints for `account`.
     */
    function numCheckpoints(address account) public view virtual returns (uint32) {
        return _numCheckpoints(account);
    }

    /**
     * @dev Get the `pos`-th checkpoint for `account`.
     */
    function checkpoints(address account, uint32 pos) public view virtual returns (Checkpoints.Checkpoint208 memory) {
        return _checkpoints(account, pos);
    }

    /**
     * @inheritdoc ERC20CheckpointsUpgradeable
     */
    function getPastTotalSupply(uint256 timepoint) public view virtual override(
        IVotes,
        ERC20CheckpointsUpgradeable
    ) returns (uint256) {
        return ERC20CheckpointsUpgradeable.getPastTotalSupply(timepoint);
    }

    /**
     * @dev Returns the current amount of votes that `account` has.
     */
    function getVotes(address account) public view virtual returns (uint256) {
        ERC20VotesStorage storage $ = _getVotesStorage();
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
    function getPastVotes(address account, uint256 timepoint) public view virtual noFutureLookup(timepoint) returns (uint256) {
        ERC20VotesStorage storage $ = _getVotesStorage();
        return $._delegateCheckpoints[account].upperLookupRecent(uint48(timepoint));
    }

    /**
     * @dev Returns the delegate that `account` has chosen.
     */
    function delegates(address account) public view virtual returns (address) {
        ERC20VotesStorage storage $ = _getVotesStorage();
        return $._delegatee[account];
    }

    /**
     * @dev Delegates votes from the sender to `delegatee`.
     */
    function delegate(address delegatee) public virtual {
        address account = _msgSender();
        _delegate(account, delegatee);
    }

    /**
     * @dev Delegates votes from `delegator` to `delegatee`. Supports ECDSA or EIP1271 signatures.
     *
     * @param signature The signature is a packed bytes encoding of the ECDSA r, s, and v signature values.
     */
    function delegateBySig(
        address delegator,
        address delegatee,
        uint256 deadline,
        bytes memory signature
    ) public virtual {
        if (block.timestamp > deadline) {
            revert VotesExpiredSignature(deadline);
        }

        bool valid = SignatureChecker.isValidSignatureNow(
            delegator,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(DELEGATION_TYPEHASH, delegator, delegatee, _useNonce(delegator), deadline)
                )
            ),
            signature
        );

        if (!valid) {
            revert VotesInvalidSignature();
        }

        _delegate(delegator, delegatee);
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
        ERC20VotesStorage storage $ = _getVotesStorage();
        address oldDelegate = delegates(account);
        $._delegatee[account] = delegatee;

        emit DelegateChanged(account, oldDelegate, delegatee);
        _moveDelegateVotes(oldDelegate, delegatee, _getVotingUnits(account));
    }

    /**
     * @dev Moves delegated votes from one delegate to another.
     */
    function _moveDelegateVotes(address from, address to, uint256 amount) private {
        ERC20VotesStorage storage $ = _getVotesStorage();
        if (from != to && amount > 0) {
            if (from != address(0)) {
                (uint256 oldValue, uint256 newValue) = _writeCheckpoint(
                    $._delegateCheckpoints[from],
                    _subtract,
                    SafeCast.toUint208(amount)
                );
                emit DelegateVotesChanged(from, oldValue, newValue);
            }
            if (to != address(0)) {
                (uint256 oldValue, uint256 newValue) = _writeCheckpoint(
                    $._delegateCheckpoints[to],
                    _add,
                    SafeCast.toUint208(amount)
                );
                emit DelegateVotesChanged(to, oldValue, newValue);
            }
        }
    }

    /**
     * @dev Get number of checkpoints for `account`.
     */
    function _numCheckpoints(address account) internal view virtual returns (uint32) {
        ERC20VotesStorage storage $ = _getVotesStorage();
        return SafeCast.toUint32($._delegateCheckpoints[account].length());
    }

    /**
     * @dev Get the `pos`-th checkpoint for `account`.
     */
    function _checkpoints(
        address account,
        uint32 pos
    ) internal view virtual returns (Checkpoints.Checkpoint208 memory) {
        ERC20VotesStorage storage $ = _getVotesStorage();
        return $._delegateCheckpoints[account].at(pos);
    }

    /**
     * @dev Must return the voting units held by an account.
     */
    function _getVotingUnits(address account) internal view virtual returns (uint256) {
        return balanceOf(account);
    }
}
