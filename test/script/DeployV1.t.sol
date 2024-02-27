// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PRBTest} from "@prb/test/PRBTest.sol";
import {console2} from "forge-std/console2.sol";
import {DeployV1} from "script/DeployV1.s.sol";
import {PrimordiumTokenV1} from "src/token/PrimordiumTokenV1.sol";
import {PrimordiumSharesOnboarderV1} from "src/onboarder/PrimordiumSharesOnboarderV1.sol";
import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {PrimordiumExecutorV1} from "src/executor/PrimordiumExecutorV1.sol";
import {DistributorV1} from "src/executor/extensions/DistributorV1.sol";

contract DeployV1Test is PRBTest {
    DeployV1 deployScript = new DeployV1();

    DeployV1.Implementations implementations;
    DeployV1.Proxies proxies;

    function setUp() public {
        (, implementations,, proxies) = deployScript.run();
    }

    function test_TestSetUp() public {
        DeployV1 tester = new DeployV1();
        tester.setImplementationSalt(keccak256("test"));
        tester.setProxySalt(keccak256("test"));
        tester.run();
    }

    /// @dev Gets the stored implementation address for the provided ERC1967Proxy address
    function _getProxyImplementation(address proxy) internal view returns (address impl) {
        impl = address(
            uint160(uint256(vm.load(proxy, 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)))
        );
    }

    function test_ProxyImplementations() public {
        assertEq(address(implementations.executorImpl), _getProxyImplementation(address(proxies.executor)));
        assertEq(address(implementations.tokenImpl), _getProxyImplementation(address(proxies.token)));
        assertEq(
            address(implementations.sharesOnboarderImpl), _getProxyImplementation(address(proxies.sharesOnboarder))
        );
        assertEq(address(implementations.governorImpl), _getProxyImplementation(address(proxies.governor)));
        assertEq(
            address(implementations.distributorImpl), _getProxyImplementation(address(proxies.executor.distributor()))
        );
    }

    function test_ContractReferences() public {
        // Token
        assertEq(address(proxies.executor), proxies.token.owner());
        assertEq(address(proxies.executor), address(proxies.token.treasury()));

        // SharesOnboarder
        assertEq(address(proxies.executor), proxies.sharesOnboarder.owner());
        assertEq(address(proxies.executor), address(proxies.sharesOnboarder.treasury()));

        // Governor
        assertEq(address(proxies.executor), address(proxies.governor.executor()));
        assertEq(address(proxies.token), address(proxies.governor.token()));

        // Executor
        assertEq(address(proxies.token), address(proxies.executor.token()));
        assertEq(address(proxies.sharesOnboarder), address(proxies.executor.sharesOnboarder()));
        assertEq(address(proxies.distributor), address(proxies.executor.distributor()));

        // Distributor
        assertEq(address(proxies.token), proxies.distributor.token());
        assertEq(address(proxies.executor), proxies.distributor.owner());

        // governor is only module on executor
        assertTrue(proxies.executor.isModuleEnabled(address(proxies.governor)));
        address[] memory expectedModules = new address[](1);
        expectedModules[0] = address(proxies.governor);
        (address[] memory actualModules,) = proxies.executor.getModulesPaginated(address(0x01), 100);
        assertEq(expectedModules, actualModules);
    }

    function test_DefaultProposers() public {
        PrimordiumGovernorV1.GovernorV1Init memory governorInit = deployScript._getGovernorV1InitParams();

        if (governorInit.governorBaseInit.grantRoles.length > 0) {
            (bytes32[] memory roles, address[] memory accounts, uint256[] memory expiresAts) =
                abi.decode(governorInit.governorBaseInit.grantRoles, (bytes32[], address[], uint256[]));

            for (uint256 i = 0; i < roles.length; i++) {
                assertEq(true, proxies.governor.hasRole(roles[i], accounts[i]));
                assertEq(expiresAts[i], proxies.governor.roleExpiresAt(roles[i], accounts[i]));
            }
        }
    }
}
