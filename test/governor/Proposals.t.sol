// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {ProposalTestUtils} from "test/helpers/ProposalTestUtils.sol";
import {BalanceSharesTestUtils} from "test/helpers/BalanceSharesTestUtils.sol";

contract ProposalsTest is BaseTest, ProposalTestUtils, BalanceSharesTestUtils {
    function setUp() public virtual override {
        super.setUp();
        _setupDefaultBalanceShares();

    }

    function test_RevertWhen_InvalidProposerDescription() public {
        address target = address(0x01);
    }
}