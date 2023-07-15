// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/extensions/ERC20Permit.sol)

pragma solidity ^0.8.0;

import "../../VotesProvisioner.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @dev Implements the {permitWithdraw} method, which allows users to sign EIP712 messages to permit the withdrawal
 * of their vote tokens, burning the tokens and sending the proportional share of the base treasury to the designated
 * receiver.
 *
 * The current withdrawNonce for each account holder can be queried with the {withdrawNonces} method.
 *
 * Functions similarly to the ERC20 Permit functionality
 */
abstract contract PermitWithdraw is VotesProvisioner {
    using Counters for Counters.Counter;

    mapping (address => Counters.Counter) private _withdrawNonces;

    bytes32 private constant _PERMIT_WITHDRAW_TYPEHASH = keccak256(
        "PermitWithdraw(address owner,address receiver,uint256 amount,uint256 withdrawNonce,uint256 deadline)"
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
        require(block.timestamp <= deadline, "PermitWithdraw: expired deadline");

        bytes32 structHash = keccak256(
            abi.encode(_PERMIT_WITHDRAW_TYPEHASH, owner, receiver, amount, _useWithdrawNonce(owner), deadline)
        );

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        require(signer == owner, "PermitWithdraw: invalid signature");

        _withdraw(owner, receiver, amount);
    }

    /**
     * @dev See current withdrawal nonce for owner.
     */
    function withdrawNonces(address owner) public view virtual returns (uint256) {
        return _withdrawNonces[owner].current();
    }

    /**
     * @dev "Consume a withdraw nonce": return the current value and increment.
     */
    function _useWithdrawNonce(address owner) internal virtual returns (uint256 current) {
        Counters.Counter storage nonce = _withdrawNonces[owner];
        current = nonce.current();
        nonce.increment();
    }

}