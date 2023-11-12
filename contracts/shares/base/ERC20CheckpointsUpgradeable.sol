// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.20;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC20Checkpoints} from "../interfaces/IERC20Checkpoints.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title ERC20CheckpointsUpgradeable
 *
 * @dev Implementation of the OpenZeppelin ERC20 interface with ERC20Permit and ERC-6372 clock mode, but uses
 * the OpenZeppelin "Checkpoints" library for tracking historical account balance checkpoints and historical total
 * supply checkpoints.
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract ERC20CheckpointsUpgradeable is
    ContextUpgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    IERC20Checkpoints,
    IERC165
{

    using Checkpoints for Checkpoints.Trace208;

    /// @custom:storage-location erc7201:ERC20Checkpoints.Storage
    struct ERC20CheckpointsStorage {
        mapping(address => Checkpoints.Trace208) _balanceCheckpoints;
        Checkpoints.Trace208 _totalSupplyCheckpoints;
    }

    // keccak256(abi.encode(uint256(keccak256("ERC20Checkpoints.Storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20_CHECKPOINTS_STORAGE = 0x37e2fc2784a6c5c6527f4c99f641faf0991baadc13e8e00865f61f0881e35600;

    function _getERC20CheckpointsStorage() private pure returns (ERC20CheckpointsStorage storage $) {
        assembly {
            $.slot := ERC20_CHECKPOINTS_STORAGE
        }
    }

    /**
     * @dev The clock was incorrectly modified.
     */
    error ERC6372InconsistentClock();

    modifier noFutureLookup(uint256 timepoint) {
        uint256 currentClock = clock();
        if (timepoint >= currentClock) revert ERC20CheckpointsFutureLookup(currentClock);
        _;
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC20Metadata).interfaceId ||
            interfaceId == type(IERC20Permit).interfaceId ||
            interfaceId == type(IERC20Checkpoints).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @dev Clock used for flagging checkpoints. Can be overridden to implement timestamp based checkpoints.
     */
    function clock() public view virtual override returns (uint48) {
        return SafeCast.toUint48(block.number);
    }

    /**
     * @dev Description of the clock
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        // Check that the clock was not modified
        // solhint-disable-next-line reason-string, custom-errors
        if (clock() != block.number) revert ERC6372InconsistentClock();
        return "mode=blocknumber&from=default";
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override(ERC20Upgradeable, IERC20) returns (uint256) {
        ERC20CheckpointsStorage storage $ = _getERC20CheckpointsStorage();
        return $._totalSupplyCheckpoints.latest();
    }

     /**
     * @inheritdoc IERC20Checkpoints
     */
    function getPastTotalSupply(uint256 timepoint) public view virtual noFutureLookup(timepoint) returns (uint256) {
        ERC20CheckpointsStorage storage $ = _getERC20CheckpointsStorage();
        return $._totalSupplyCheckpoints.upperLookupRecent(SafeCast.toUint32(timepoint));
    }

    /**
     * @inheritdoc IERC20Checkpoints
     */
    function maxSupply() public view virtual override returns (uint256) {
        return type(uint208).max;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override(ERC20Upgradeable, IERC20) returns (uint256) {
        ERC20CheckpointsStorage storage $ = _getERC20CheckpointsStorage();
        return uint256($._balanceCheckpoints[account].latest());
    }

    /**
     * @inheritdoc IERC20Checkpoints
     */
    function getPastBalanceOf(
        address account,
        uint256 timepoint
    ) public view virtual noFutureLookup(timepoint) returns (uint256) {
        ERC20CheckpointsStorage storage $ = _getERC20CheckpointsStorage();
        return $._balanceCheckpoints[account].upperLookupRecent(SafeCast.toUint32(timepoint));
    }

    /**
     * @inheritdoc ERC20Upgradeable
     * @dev This function is modified to follow the exact same logic as the _update function in the original
     * ERC20Upgradeable contract, but using checkpoints for balances and total supply.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        ERC20CheckpointsStorage storage $ = _getERC20CheckpointsStorage();
        if (from == address(0)) {
            // Increase the total supply, but not past the maxSupply
            (,uint256 newTotalSupply) = _writeCheckpoint($._totalSupplyCheckpoints, _add, value);
            uint256 currentMaxSupply = maxSupply();
            if (newTotalSupply > currentMaxSupply) {
                revert ERC20CheckpointsMaxSupplyOverflow(currentMaxSupply, newTotalSupply);
            }
        } else {
            uint256 fromBalance = uint256($._balanceCheckpoints[from].latest());
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply <= maxSupply
                _writeCheckpoint($._balanceCheckpoints[from], _subtract, value);
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply
                _writeCheckpoint($._totalSupplyCheckpoints, _subtract, value);
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply
                _writeCheckpoint($._balanceCheckpoints[to], _add, value);
            }
        }

        emit Transfer(from, to, value);
    }

    function _writeCheckpoint(
        Checkpoints.Trace208 storage store,
        function(uint256, uint256) view returns (uint256) op,
        uint256 delta
    ) internal returns (uint256 oldWeight, uint256 newWeight) {
        return store.push(clock(), SafeCast.toUint208(op(store.latest(), delta)));
    }

    function _add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function _subtract(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

}