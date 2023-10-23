// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

/**
 * @title Operation Status - A library to check on an operation status based on the op eta
 *
 * @author Ben Jett - @BCJdevelopment
 */
library OperationStatus {

    uint256 constant internal _DONE_TIMESTAMP = uint256(1);

    /// @dev Returns true if the opEta is greater than zero
    function isOp(uint256 opEta) internal pure returns (bool) {
        return opEta > 0;
    }

    /// @dev Returns true if the op is still pending (opEta > _DONE_TIMESTAMP)
    function isOpPending(uint256 opEta) internal pure returns (bool) {
        return opEta > _DONE_TIMESTAMP;
    }

    /// @dev Returns true if the op is executable (opEta <= block.timestamp and is not expired)
    function isOpReady(uint256 opEta, uint256 gracePeriod) internal view returns (bool) {
        return !isOpExpired(opEta, gracePeriod) && opEta <= block.timestamp;
    }

    /// @dev Returns true if the op is expired (opEta + gracePeriod <= block.timestamp)
    function isOpExpired(uint256 opEta, uint256 gracePeriod) internal view returns (bool) {
        return isOpPending(opEta) && opEta + gracePeriod <= block.timestamp;
    }

    /// @dev Returns true of the op is done (opEta == _DONE_TIMESTAMP)
    function isOpDone(uint256 opEta) internal pure returns (bool) {
        return opEta == _DONE_TIMESTAMP;
    }

}