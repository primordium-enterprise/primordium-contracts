// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)
// Based on OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable2Step.sol)

pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Ownable 1 or 2 step implementation. Owner can complete normal 2-step transfer, or force transfer in 1 step.
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract Ownable1Or2StepUpgradeable is Initializable {
    /// @custom:storage-location erc7201:Ownable1Or2Step.Storage
    struct Ownable1Or2StepStorage {
        address _owner;
        address _pendingOwner;
    }

    // keccak256(abi.encode(uint256(keccak256("Ownable1Or2Step.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant OWNABLE_STORAGE = 0xc0d8e577dffd500c91d0736494fcbe84a5c8c573ecb51bd61d6753653ce53500;

    function _getOwnableStorage() private pure returns (Ownable1Or2StepStorage storage $) {
        assembly {
            $.slot := OWNABLE_STORAGE
        }
    }

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    function __Ownable_init(address initialOwner) internal onlyInitializing {
        __Ownable_init_unchained(initialOwner);
    }

    function __Ownable_init_unchained(address initialOwner) internal onlyInitializing {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address _owner) {
        _owner = _getOwnableStorage()._owner;
    }

    /**
     * @dev Returns the address of the pending owner.
     */
    function pendingOwner() public view virtual returns (address _pendingOwner) {
        _pendingOwner = _getOwnableStorage()._pendingOwner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }

    /**
     * @dev Returns true if the msg.sender is the owner.
     */
    function _senderIsOwner() internal view virtual returns (bool isOwner) {
        isOwner = msg.sender == owner();
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is
     * one. Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        Ownable1Or2StepStorage storage $ = _getOwnableStorage();
        $._pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwnership() public virtual {
        address sender = msg.sender;
        if (pendingOwner() != sender) {
            revert OwnableUnauthorizedAccount(sender);
        }
        _transferOwnership(sender);
    }

    /**
     * @dev Force transfers ownership of the contract to a new account (`newOwner`). Can only be called by the current
     * owner.
     */
    function forceTransferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        Ownable1Or2StepStorage storage $ = _getOwnableStorage();
        address oldOwner = $._owner;
        $._owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}