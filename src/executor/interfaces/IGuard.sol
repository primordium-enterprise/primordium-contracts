// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {Enum} from "src/common/Enum.sol";

/**
 * @title Guard interface to be used with a guarded Avatar, based on the EIP-5005 Zodiac Modular Accounts
 */
interface IGuard {
    function checkTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        address module,
        uint256 opNonce
    )
        external
        returns (bytes32 guardHash);

    function checkAfterExecution(bytes32 txHash, bool success) external;
}
