// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/extensions/ERC20Permit.sol)

pragma solidity ^0.8.4;

import "../../VotesProvisioner.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @dev Implements the {permitWithdraw} method, which allows users to sign EIP712 messages to permit the withdrawal
 * of their vote tokens, burning the tokens and sending the proportional share of the base treasury to the designated
 * receiver.
 *
 * Functions similarly to the ERC20 Permit functionality
 */
abstract contract PermitWithdraw is VotesProvisioner {

    bytes32 private constant _PERMIT_WITHDRAW_TYPEHASH = keccak256(
        "PermitWithdraw(address owner,address receiver,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    /**
     * @dev Allows permitting a withdrawal according to EIP712
     */
    function permitWithdraw(
        address owner,
        address receiver,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > deadline) revert SignatureExpired();

        bytes32 structHash = keccak256(
            abi.encode(_PERMIT_WITHDRAW_TYPEHASH, owner, receiver, amount, _useNonce(owner), deadline)
        );

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != owner) revert SignatureInvalid();

        _withdraw(owner, receiver, amount);
    }

}