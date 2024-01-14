// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PrimordiumTokenV1} from "src/token/PrimordiumTokenV1.sol";
import {PrimordiumSharesOnboarderV1} from "src/onboarder/PrimordiumSharesOnboarderV1.sol";
import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {PrimordiumExecutorV1} from "src/executor/PrimordiumExecutorV1.sol";
import {DistributorV1} from "src/executor/extensions/DistributorV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

abstract contract BaseScriptV1 is Script {
    /// @dev The create2 salt used for deployments, hashed using the $DEPLOY_SALT_STRING env variable
    bytes32 deploySalt;

    /// @dev Used as default if no $MNEMONIC env variable is defined
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    /// @dev The address of the transaction broadcaster
    address internal broadcaster;

    /// @dev Used to derive the broadcaster's address if $BROADCASTER is not defined
    string internal mnemonic;

    /**
     * @dev Initializes the `deploySaltString` for create2 deployments, and the address of the `broadcaster`.
     *
     * The `deploySaltString` defaults to bytes32(0) if there is no $DEPLOY_SALT_STRING env variable.
     *
     * Sets the `broadcaster` equal to the $BROADCASTER env variable, or if that doesn't exist, the address of the
     * $MNEMONIC env variable (which defaults to the test mnemonic).
     */
    constructor() {
        string memory deploySaltString = vm.envOr("DEPLOY_SALT_STRING", string(""));
        if (bytes(deploySaltString).length > 0) {
            deploySalt = keccak256(abi.encodePacked(deploySaltString));
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

    function _checkContractAlreadyExists(address addr) internal view returns (bool exists) {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(addr)
        }

        if (codeSize > 0) {
            return true;
        }
    }

    function _getProxyInitCode(address implementation, bytes memory _data) internal pure returns (bytes memory) {
        return abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, _data));
    }

    function _deployProxy(bytes memory initCode) internal returns (address deployed) {
        assembly {
            deployed := create2(0, add(initCode, 0x20), mload(initCode), sload(deploySalt.slot))
        }
    }

    function _deployAllImplementations()
        internal
        returns (
            PrimordiumExecutorV1 executorImpl,
            PrimordiumTokenV1 tokenImpl,
            PrimordiumSharesOnboarderV1 sharesOnboarderImpl,
            PrimordiumGovernorV1 governorImpl,
            DistributorV1 distributorImpl
        )
    {
        return (
            _deploy_implementation_ExecutorV1(),
            _deploy_implementation_TokenV1(),
            _deploy_implementation_SharesOnboarderV1(),
            _deploy_implementation_GovernorV1(),
            _deploy_implementation_DistributorV1()
        );
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumExecutorV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_ExecutorV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(PrimordiumExecutorV1).creationCode));
    }

    function _deploy_implementation_ExecutorV1() internal returns (PrimordiumExecutorV1 deployed) {
        deployed = new PrimordiumExecutorV1{salt: deploySalt}();
        require(address(deployed) == _address_implementation_ExecutorV1(), "Executor: invalid implementation deployment address");
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumTokenV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_TokenV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(PrimordiumTokenV1).creationCode));
    }

    function _deploy_implementation_TokenV1() internal returns (PrimordiumTokenV1 deployed) {
        deployed = new PrimordiumTokenV1{salt: deploySalt}();
        if (address(deployed) != _address_implementation_TokenV1()) {
            revert("SharesToken: invalid implementation deployment address");
        }
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumSharesOnboarderV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_SharesOnboarderV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(PrimordiumSharesOnboarderV1).creationCode));
    }

    function _deploy_implementation_SharesOnboarderV1() internal returns (PrimordiumSharesOnboarderV1 deployed) {
        deployed = new PrimordiumSharesOnboarderV1{salt: deploySalt}();
        if (address(deployed) != _address_implementation_SharesOnboarderV1()) {
            revert("SharesOnboarder: invalid implementation deployment address");
        }
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumGovernorV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_GovernorV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(PrimordiumGovernorV1).creationCode));
    }

    function _deploy_implementation_GovernorV1() internal returns (PrimordiumGovernorV1 deployed) {
        deployed = new PrimordiumGovernorV1{salt: deploySalt}();
        if (address(deployed) != _address_implementation_GovernorV1()) {
            revert("Governor: invalid implementation deployment address");
        }
    }

    /*/////////////////////////////////////////////////////////////////////////////
        DistributorV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_DistributorV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(DistributorV1).creationCode));
    }

    function _deploy_implementation_DistributorV1() internal returns (DistributorV1 deployed) {
        deployed = new DistributorV1{salt: deploySalt}();
        if (address(deployed) != _address_implementation_DistributorV1()) {
            revert("Distributor: invalid implementation deployment address");
        }
    }
}
