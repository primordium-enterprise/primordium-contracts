// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract SelfAuthorized is Initializable {
    /// @custom:storage-location erc7201:SelfAuthorized.Storage
    struct SelfAuthorizedStorage {
        address _authorizedOperator;
    }

    // keccak256(abi.encode(uint256(keccak256("SelfAuthorized.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant SELF_AUTHORIZED_STORAGE =
        0x4b2fd3e76f3db6be1ddf6915fab5beab18a597f23ff7042b1e3087eec7ce7100;

    function _getSelfAuthorizedStorage() private pure returns (SelfAuthorizedStorage storage $) {
        assembly {
            $.slot := SELF_AUTHORIZED_STORAGE
        }
    }

    address private constant DEFAULT_OPERATOR_ADDRESS = address(0x01);

    error OnlySelfAuthorized();

    /**
     * @dev Modifier to make a function callable only by this contract itself.
     */
    modifier onlySelf() {
        _onlySelf();
        _;
    }

    function _onlySelf() internal view {
        if (msg.sender != address(this)) {
            revert OnlySelfAuthorized();
        }
    }

    function __SelfAuthorized_init() internal onlyInitializing {
        _getSelfAuthorizedStorage()._authorizedOperator = DEFAULT_OPERATOR_ADDRESS;
    }

    /**
     * @dev Modifier that sets the provided operator address in storage for the duration of the function. This is useful
     * for a called contract to use {getAuthorizedOperator} to check the authorized operator. This modifier resets the
     * operator address back to address(0x01) after the modified function is called to avoid stagnant authorization and
     * to issue a gas refund.
     *
     * Example usage: a DAO executor (which can execute arbitrary transactions) owns a contract where an owner-only
     * function call should only occur in the context of a self-authorized function called by the executor on itself.
     * This modifier allows the owned contract to verify that it is the authorized operator on the owner contract,
     * restricting that function to ONLY be called through the executor's self-authorized function.
     */
    modifier authorizeOperator(address operator) {
        // TODO: Make this transient storage once it is available
        SelfAuthorizedStorage storage $ = _getSelfAuthorizedStorage();
        $._authorizedOperator = operator;
        _;
        $._authorizedOperator = DEFAULT_OPERATOR_ADDRESS;
    }

    /**
     * @dev Used with the {authorizeOperator} modifier, allows an external contract to check the authorized operator
     * for the current function context.
     */
    function getAuthorizedOperator() public view returns (address operator) {
        operator = _getSelfAuthorizedStorage()._authorizedOperator;
    }
}
