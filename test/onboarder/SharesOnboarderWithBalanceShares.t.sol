// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {SharesOnboarderTest} from "./SharesOnboarder.t.sol";

contract SharesOnboarderWithBalanceSharesTest is SharesOnboarderTest {
    function setUp() public virtual override {
        super.setUp();
        _setupDefaultBalanceShares();
    }
}