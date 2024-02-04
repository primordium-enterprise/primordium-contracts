// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {BaseScriptV1} from "./BaseV1.s.sol";
import {PrimordiumTokenV1} from "src/token/PrimordiumTokenV1.sol";
import {PrimordiumSharesOnboarderV1} from "src/onboarder/PrimordiumSharesOnboarderV1.sol";
import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {PrimordiumExecutorV1} from "src/executor/PrimordiumExecutorV1.sol";
import {DistributorV1} from "src/executor/extensions/DistributorV1.sol";

abstract contract ImplementationsV1 is BaseScriptV1 {

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
        return computeCreate2Address(deploySaltImplementation, keccak256(type(PrimordiumExecutorV1).creationCode));
    }

    function _deploy_implementation_ExecutorV1() internal returns (PrimordiumExecutorV1 deployed) {
        deployed = new PrimordiumExecutorV1{salt: deploySaltImplementation}();
        require(
            address(deployed) == _address_implementation_ExecutorV1(),
            "Executor: invalid implementation deployment address"
        );
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumTokenV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_TokenV1() internal view returns (address) {
        return computeCreate2Address(deploySaltImplementation, keccak256(type(PrimordiumTokenV1).creationCode));
    }

    function _deploy_implementation_TokenV1() internal returns (PrimordiumTokenV1 deployed) {
        deployed = new PrimordiumTokenV1{salt: deploySaltImplementation}();
        if (address(deployed) != _address_implementation_TokenV1()) {
            revert("SharesToken: invalid implementation deployment address");
        }
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumSharesOnboarderV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_SharesOnboarderV1() internal view returns (address) {
        return
            computeCreate2Address(deploySaltImplementation, keccak256(type(PrimordiumSharesOnboarderV1).creationCode));
    }

    function _deploy_implementation_SharesOnboarderV1() internal returns (PrimordiumSharesOnboarderV1 deployed) {
        deployed = new PrimordiumSharesOnboarderV1{salt: deploySaltImplementation}();
        if (address(deployed) != _address_implementation_SharesOnboarderV1()) {
            revert("SharesOnboarder: invalid implementation deployment address");
        }
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumGovernorV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_GovernorV1() internal view returns (address) {
        return computeCreate2Address(deploySaltImplementation, keccak256(type(PrimordiumGovernorV1).creationCode));
    }

    function _deploy_implementation_GovernorV1() internal returns (PrimordiumGovernorV1 deployed) {
        deployed = new PrimordiumGovernorV1{salt: deploySaltImplementation}();
        if (address(deployed) != _address_implementation_GovernorV1()) {
            revert("Governor: invalid implementation deployment address");
        }
    }

    /*/////////////////////////////////////////////////////////////////////////////
        DistributorV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _address_implementation_DistributorV1() internal view returns (address) {
        return computeCreate2Address(deploySaltImplementation, keccak256(type(DistributorV1).creationCode));
    }

    function _deploy_implementation_DistributorV1() internal returns (DistributorV1 deployed) {
        deployed = new DistributorV1{salt: deploySaltImplementation}();
        if (address(deployed) != _address_implementation_DistributorV1()) {
            revert("Distributor: invalid implementation deployment address");
        }
    }
}