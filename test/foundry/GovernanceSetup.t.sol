// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "contracts/GovernorV1.sol";
import "contracts/Mushi.sol";
import "contracts/PrimordiumExecutor.sol";

abstract contract GovernanceSetup is Test {

    Mushi token;

    PrimordiumExecutor executor;

    GovernorV1 governor;

    function setUp() public virtual {

        token = new Mushi(
            TreasurerOld(payable(address(0))),
            10 ether / 10,
            IVotesProvisioner.TokenPrice(10, 1)
        );

        executor = new PrimordiumExecutor(
            2 days,
            address(0),
            VotesProvisioner(address(token))
        );

        governor = new GovernorV1(
            Executor(payable(address(0))),
            VotesProvisioner(address(token)),
            1 ether / 10, // Governance threshold
            100, // 100 / 10_000 = 1% quorum initially,
            0, // Initial proposal threshold bps
            1 days / 12, // Voting delay - 1 day in blocks
            1 days / 12, // Voting period - 1 day in blocks,
            60 // 60% majority
        );

        token.initializeExecutor(Executor(payable(address(executor))));
        executor.transferOwnership(address(governor));
        governor.initialize(Executor(payable(address(executor))));

    }

}