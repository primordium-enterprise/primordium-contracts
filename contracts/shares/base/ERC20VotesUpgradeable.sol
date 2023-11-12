// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (governance/utils/Votes.sol)
pragma solidity ^0.8.20;

import {ERC20CheckpointsUpgradeable} from "./ERC20CheckpointsUpgradeable.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

/**
 * @title ERC20VotesUpgradeable
 *
 * @dev This module is based on the OpenZeppelin Votes implementation (with full vote delegation), but inherits directly
 * from the ERC20CheckpointsUpgradeable in this repository, which already implements a historical tracking of the ERC20
 * total supply.
 *
 * Accounts must delegate (to themselves or another account) in order for their votes to be counted.
 *
 * @author Ben Jett - @BCJdevelopment
 *
 */
abstract contract ERC20VotesUpgradeable is IERC5805, ERC20CheckpointsUpgradeable {
    using Checkpoints for Checkpoints.Trace208;

    bytes32 private constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @custom:storage-location erc7201:ERC20Votes.Storage
    struct ERC20VotesStorage {
        mapping(address account => address) _delegatee;

        mapping(address delegatee => Checkpoints.Trace208) _delegateCheckpoints;
    }

    // keccak256(abi.encode(uint256(keccak256("ERC20Votes.Storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20_VOTES_STORAGE = 0x109684a1287cc407d745bb820bf93a681ef38b14304190d1e8fea2ca0f881500;

    function _getVotesStorage() private pure returns (ERC20VotesStorage storage $) {
        assembly {
            $.slot := ERC20_VOTES_STORAGE
        }
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return
            interfaceId == type(IERC5805).interfaceId ||
            interfaceId == type(IVotes).interfaceId ||
            super.supportsInterface(interfaceId);
    }

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
     * @dev Delegates votes from signer to `delegatee`.
     */
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > expiry) {
            revert VotesExpiredSignature(expiry);
        }
        address signer = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry))),
            v,
            r,
            s
        );
        _useCheckedNonce(signer, nonce);
        _delegate(signer, delegatee);
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
     * @dev Transfers, mints, or burns voting units. To register a mint, `from` should be zero. To register a burn, `to`
     * should be zero. Total supply of voting units will be adjusted with mints and burns.
     */
    function _transferVotingUnits(address from, address to, uint256 amount) internal virtual {
        _moveDelegateVotes(delegates(from), delegates(to), amount);
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
    function _getVotingUnits(address) internal view virtual returns (uint256);
}
