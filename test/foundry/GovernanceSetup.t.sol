// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "contracts/GovernorV1.sol";
import "contracts/Mushi.sol";
import "contracts/PrimordiumExecutor.sol";

abstract contract GovernanceSetup is Test {

    Mushi votes = new Mushi(
        Treasurer(payable(address(0))),
        10 ether
    );

    PrimordiumExecutor executor = new PrimordiumExecutor(
        2 days,
        address(0),
        VotesProvisioner(address(votes))
    );

    GovernorV1 governor = new GovernorV1(
        Executor(payable(address(0))),
        Votes(address(votes)),
        2 days / 12, // Two days in blocks
        3 days / 12, // Three Days in blocks,
        0
    );

    constructor() {
        votes.initializeExecutor(Executor(payable(address(executor))));
        executor.transferOwnership(address(governor));
        governor.initialize(Executor(payable(address(executor))));
    }

}