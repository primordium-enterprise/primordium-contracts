// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {SharesTokenTest} from "./SharesToken.t.sol";

contract SharesTokenWithBalanceSharesTest is SharesTokenTest {
    function setUp() public virtual override {
        super.setUp();
        _setupDefaultBalanceShares();
    }
}