// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IDistributor} from "src/executor/interfaces/IDistributor.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

contract TreasurerTest is BaseTest {
    using ERC165Checker for address;

    function setUp() public virtual override {
        super.setUp();
    }

    function test_DistributorCreate2Address() public {
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                distributorImpl, abi.encodeCall(IDistributor.setUp, (address(token), EXECUTOR.distributionClaimPeriod))
            )
        );

        assertEq(
            executor.distributor(),
            address(
                uint160(
                    uint256(keccak256(abi.encodePacked(hex"ff", address(executor), uint256(0), keccak256(bytecode))))
                )
            )
        );

        assertTrue(executor.distributor().supportsInterface(type(IDistributor).interfaceId));
    }
}
