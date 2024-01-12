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
    bytes32 deploySalt;

    constructor() {
        string memory deploySaltString = vm.envString("DEPLOY_SALT_STRING");
        deploySalt = keccak256(abi.encodePacked(deploySaltString));
    }

    modifier broadcast() {
        vm.startBroadcast();
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

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumTokenV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_TokenV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(PrimordiumTokenV1).creationCode));
    }

    function _deploy_implementation_TokenV1() internal {
        address deployed = address(new PrimordiumTokenV1{salt: deploySalt}());
        if (deployed != _address_implementation_TokenV1()) {
            revert("SharesToken: invalid deployment address");
        }
    }

    // function _initCode_proxy_TokenV1(
    //     address executor,
    //     SharesTokenSettings memory settings
    // )
    //     internal
    //     view
    //     returns (bytes memory initCode)
    // {
    //     address owner = executor;
    //     SharesTokenInit memory $ = settings.sharesTokenInit;
    //     bytes memory sharesTokenInit = abi.encode($.maxSupply, address(executor));
    //     return _getProxyInitCode(
    //         _address_implementation_TokenV1(),
    //         abi.encodeCall(
    //             PrimordiumTokenV1.setUp, (owner, settings.name, settings.symbol, sharesTokenInit)
    //         )
    //     );
    // }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumSharesOnboarderV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_SharesOnboarderV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(PrimordiumSharesOnboarderV1).creationCode));
    }

    function _deploy_implementation_SharesOnboarderV1() internal {
        address deployed = address(new PrimordiumSharesOnboarderV1{salt: deploySalt}());
        if (deployed != _address_implementation_SharesOnboarderV1()) {
            revert("SharesOnboarder: invalid deployment address");
        }
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumGovernorV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_GovernorV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(PrimordiumGovernorV1).creationCode));
    }

    function _deploy_implementation_GovernorV1() internal {
        address deployed = address(new PrimordiumGovernorV1{salt: deploySalt}());
        if (deployed != _address_implementation_GovernorV1()) {
            revert("Governor: invalid deployment address");
        }
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumExecutorV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_ExecutorV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(PrimordiumExecutorV1).creationCode));
    }

    function _deploy_implementation_ExecutorV1() internal {
        address deployed = address(new PrimordiumExecutorV1{salt: deploySalt}());
        if (deployed != _address_implementation_ExecutorV1()) {
            revert("Executor: invalid deployment address");
        }
    }

    /*/////////////////////////////////////////////////////////////////////////////
        DistributorV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_DistributorV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(DistributorV1).creationCode));
    }

    function _deploy_implementation_DistributorV1() internal {
        address deployed = address(new DistributorV1{salt: deploySalt}());
        if (deployed != _address_implementation_DistributorV1()) {
            revert("Distributor: invalid deployment address");
        }
    }
}
