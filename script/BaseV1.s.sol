// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PrimordiumSharesTokenV1} from "src/token/PrimordiumSharesTokenV1.sol";
import {PrimordiumSharesOnboarderV1} from "src/onboarder/PrimordiumSharesOnboarderV1.sol";
import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {PrimordiumExecutorV1} from "src/executor/PrimordiumExecutorV1.sol";
import {DistributorV1} from "src/executor/extensions/DistributorV1.sol";

abstract contract BaseV1Script is Script {

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

    /******************************************************************************
        PrimordiumSharesTokenV1
    ******************************************************************************/

    function _address_implementation_SharesTokenV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(PrimordiumSharesTokenV1).creationCode));
    }

    function _deploy_implementation_SharesTokenV1() internal {
        address deployed = address(new PrimordiumSharesTokenV1{salt: deploySalt}());
        if (deployed != _address_implementation_SharesTokenV1()) {
            revert("SharesToken: invalid deployment address");
        }
    }

    /******************************************************************************
        PrimordiumSharesOnboarderV1
    ******************************************************************************/

    function _address_implementation_SharesOnboarderV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(PrimordiumSharesOnboarderV1).creationCode));
    }

    function _deploy_implementation_SharesOnboarderV1() internal {
        address deployed = address(new PrimordiumSharesOnboarderV1{salt: deploySalt}());
        if (deployed != _address_implementation_SharesOnboarderV1()) {
            revert("SharesOnboarder: invalid deployment address");
        }
    }

    /******************************************************************************
        PrimordiumGovernorV1
    ******************************************************************************/

    function _address_implementation_GovernorV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(PrimordiumGovernorV1).creationCode));
    }

    function _deploy_implementation_GovernorV1() internal {
        address deployed = address(new PrimordiumGovernorV1{salt: deploySalt}());
        if (deployed != _address_implementation_GovernorV1()) {
            revert("Governor: invalid deployment address");
        }
    }

    /******************************************************************************
        PrimordiumExecutorV1
    ******************************************************************************/

    function _address_implementation_ExecutorV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(type(PrimordiumExecutorV1).creationCode));
    }

    function _deploy_implementation_ExecutorV1() internal {
        address deployed = address(new PrimordiumExecutorV1{salt: deploySalt}());
        if (deployed != _address_implementation_ExecutorV1()) {
            revert("Executor: invalid deployment address");
        }
    }

    /******************************************************************************
        DistributorV1
    ******************************************************************************/

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