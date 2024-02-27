// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

abstract contract BaseScriptV1 is Script {
    string constant IMPLEMENTATION_SALT_STRING = "IMPLEMENTATION_SALT_STRING";
    string constant PROXY_SALT_STRING = "PROXY_SALT_STRING";

    /// @dev The create2 salt used for implementation deployments, hashed using the env $IMPLEMENTATION_SALT_STRING
    bytes32 deploySaltImplementation;

    /// @dev The create2 salt used for proxy deployments, hashed using the env $PROXY_SALT_STRING
    bytes32 deploySaltProxy;

    /// @dev Used as default if no $MNEMONIC env variable is defined
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    /// @dev The address of the transaction broadcaster
    address internal broadcaster;

    /// @dev Used to derive the broadcaster's address if $BROADCASTER is not defined
    string internal mnemonic;

    /**
     * @dev Initializes the salt strings for create2 deployments, and the address of the `broadcaster`.
     *
     * The salt strings default to bytes32(0) if there is no corresponding env variable.
     *
     * Sets the `broadcaster` equal to the $BROADCASTER env variable, or if that doesn't exist, the address of the
     * $MNEMONIC env variable (which will default to the test mnemonic).
     */
    constructor() {
        string memory implementationSaltString = vm.envOr(IMPLEMENTATION_SALT_STRING, string(""));
        if (bytes(implementationSaltString).length > 0) {
            deploySaltImplementation = keccak256(abi.encodePacked(implementationSaltString));
        }

        string memory proxySaltString = vm.envOr(PROXY_SALT_STRING, string(""));
        if (bytes(proxySaltString).length > 0) {
            deploySaltProxy = keccak256(abi.encodePacked(proxySaltString));
        }

        address envBroadcaster = vm.envOr("BROADCASTER", address(0));
        if (envBroadcaster != address(0)) {
            broadcaster = envBroadcaster;
        } else {
            mnemonic = vm.envOr("MNEMONIC", TEST_MNEMONIC);
            (broadcaster,) = deriveRememberKey({mnemonic: mnemonic, index: 0});
        }
    }

    modifier broadcast() {
        vm.startBroadcast(broadcaster);
        _;
        vm.stopBroadcast();
    }

    function setImplementationSalt(bytes32 salt) public {
        deploySaltImplementation = salt;
    }

    function setProxySalt(bytes32 salt) public {
        deploySaltProxy = salt;
    }

    function _checkContractAlreadyExists(address addr) internal view returns (bool exists) {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(addr)
        }

        if (codeSize > 0) {
            return true;
        }
    }

    function _getProxyInitCode(address implementation, bytes memory _data) internal view returns (bytes memory) {
        require(implementation.code.length > 0, "Implementation code does not exist!");
        return abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, _data));
    }

    function _deployProxy(bytes memory initCode) internal returns (address deployed) {
        assembly {
            deployed := create2(0, add(initCode, 0x20), mload(initCode), sload(deploySaltProxy.slot))
        }
    }
}
