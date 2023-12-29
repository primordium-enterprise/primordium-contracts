// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {ISharesToken} from "src/token/interfaces/ISharesToken.sol";

contract SharesTokenTest is BaseTest {
    uint256 gwartShares = 200;
    uint256 bobShares = 300;
    uint256 aliceShares = 500;
    function setUp() public virtual override {
        super.setUp();
        // Mint shares to gwart, bob, and alice
        vm.startPrank(token.owner());
        token.mint(users.gwart, gwartShares);
        token.mint(users.bob, bobShares);
        token.mint(users.alice, aliceShares);
        vm.stopPrank();
    }

    function test_TotalSupply() public {
        assertEq(token.totalSupply(), gwartShares + bobShares + aliceShares);
    }

    function test_SetMaxSupply() public {
        uint256 newMaxSupply = uint256(type(uint208).max) + 1;
        vm.startPrank(token.owner());
        vm.expectRevert(abi.encodeWithSelector(ISharesToken.MaxSupplyTooLarge.selector, type(uint208).max));
        token.setMaxSupply(newMaxSupply);

        newMaxSupply = type(uint208).max;
        vm.expectEmit(false, false, false, true, address(token));
        emit ISharesToken.MaxSupplyChange(token.maxSupply(), newMaxSupply);
        token.setMaxSupply(newMaxSupply);
        vm.stopPrank();
    }
}