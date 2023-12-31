// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {SharesOnboarderERC20Test} from "./SharesOnboarderERC20.t.sol";

contract SharesOnboarderWithBalanceSharesTest is SharesOnboarderERC20Test {
    function setUp() public virtual override {
        super.setUp();
        _setupDefaultBalanceShares();
    }
}