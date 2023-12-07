// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {SelfAuthorized} from "./SelfAuthorized.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/**
 * @title EIP1271MessageSigner
 * @author Ben Jett - @BCJdevelopment
 * @notice A utility contract for signing messages and exposing the EIP1271 "isValidSignature" function for validating
 * these signatures.
 * @dev Allows this contract to sign a message by setting an expiration for the provided message hash that is sometime
 * in the future. This message hash will be considered a valid signature as long as the block.timestamp is still behind
 * the expiration, and the provided signature is a 32 byte representation of the uint256 expiration in seconds.
 */
abstract contract EIP1271MessageSigner is SelfAuthorized, IERC1271 {

    /// @custom:storage-location erc7201:EIP1271MessageSigner.Storage
    struct EIP1271MessageSignerStorage {
        mapping(bytes32 messageHash => uint256 expiration) _messageHashExpirations;
    }

    bytes32 private immutable EIP1271_MESSAGE_SIGNER_STORAGE =
        keccak256(abi.encode(uint256(keccak256("EIP1271MessageSigner.Storage")) - 1)) & ~bytes32(uint256(0xff));

    function _getEIP1271MessageSignerStorage() private view returns (EIP1271MessageSignerStorage storage $) {
        bytes32 slot = EIP1271_MESSAGE_SIGNER_STORAGE;
        assembly {
            $.slot := slot
        }
    }

    event EIP1271MessageSigned(bytes32 indexed messageHash, uint256 signatureExpiration);
    event EIP1271MessageCanceled(bytes32 indexed messageHash);

    error SignatureExpirationMustBeInFuture(uint256 signatureExpiration);
    error SignatureDoesNotExist(bytes32 messageHash);

    /**
     * Allows other contracts to verify that this contract signed the provided message hash, according to EIP1271.
     * @param hash The message hash to verify.
     * @param signature This contract requires that the bytes length of the signature is zero (empty).
     */
    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external view virtual override returns (bytes4 magicValue) {
        // Default to failure
        magicValue = 0xffffffff;
        if (signature.length == 0) {
            uint256 signatureExpiration = _getEIP1271MessageSignerStorage()._messageHashExpirations[hash];
            if (block.timestamp < signatureExpiration) {
                magicValue = 0x1626ba7e;
            }
        }
    }

    /**
     * Returns the expiration timestamp in seconds for the provided message hash.
     * @param messageHash The message hash of the "signed" message.
     */
    function getSignatureExpiration(bytes32 messageHash) public view virtual returns (uint256 expiration) {
        expiration = _getEIP1271MessageSignerStorage()._messageHashExpirations[messageHash];
    }

    /**
     * Signs the provided message hash by setting the signature expiration for the message.
     * @notice This function is self-authorized, meaning this contract must call it on itself to sign a message.
     * @param messageHash The message hash to be "signed".
     * @param signatureExpiration The timestamp in seconds when the message signature should expire.
     */
    function signMessageHash(
        bytes32 messageHash,
        uint256 signatureExpiration
    ) external virtual onlySelf {
        if (signatureExpiration < block.timestamp) {
            revert SignatureExpirationMustBeInFuture(signatureExpiration);
        }

        _getEIP1271MessageSignerStorage()._messageHashExpirations[messageHash] = signatureExpiration;
        emit EIP1271MessageSigned(messageHash, signatureExpiration);
    }

    /**
     * Cancels a previously signed message hash by deleting the signature expiration for the message.
     * @notice This function is self-authorized, meaning this contract must call it on itself to cancel a message.
     * @param messageHash The signed message hash to cancel.
     */
    function cancelSignature(
        bytes32 messageHash
    ) external virtual onlySelf {
        EIP1271MessageSignerStorage storage $ = _getEIP1271MessageSignerStorage();
        uint256 expiration = $._messageHashExpirations[messageHash];
        if (expiration == 0) {
            revert SignatureDoesNotExist(messageHash);
        }

        delete _getEIP1271MessageSignerStorage()._messageHashExpirations[messageHash];
        emit EIP1271MessageCanceled(messageHash);
    }
}