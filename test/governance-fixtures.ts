import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";
import { expect } from "chai";

export const deployBaseGovernance = async () => {

    // Contracts are deployed using the first signer/account by default
    const [deployer] = await ethers.getSigners();

    const twoDaysInSeconds = 2 * 24 * 60 * 60;
    const twoDaysInBlocks = twoDaysInSeconds / 12; // 12 sec/block
    const threeDaysInBlocks = twoDaysInBlocks * 1.5;

    const executor = await ethers.deployContract("Executor", [twoDaysInSeconds, ethers.constants.AddressZero]);
    const governor = await ethers.deployContract("GovernorV1", [
        ethers.constants.AddressZero, // Executor
        ethers.constants.AddressZero, // Token
        twoDaysInBlocks, // initialVotingDelay
        threeDaysInBlocks, // initialVotingPeriod
        0 // initialProposalThreshold
    ]);

    await executor.transferOwnership(governor.address);

    console.log("Governor address:", governor.address);

    await governor.initialize(executor.address);

    return {
        deployer,
        executor,
        governor
    }

}

