import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";
import { expect } from "chai";

export const deployBaseGovernance = async () => {

    // Contracts are deployed using the first signer/account by default
    const [deployer] = await ethers.getSigners();

    const twoDaysInSeconds = 2 * 24 * 60 * 60;
    const twoDaysInBlocks = twoDaysInSeconds / 12; // 12 sec/block
    const threeDaysInBlocks = twoDaysInBlocks * 1.5;

    // Deploy Executor first, use zero address to set owner as the deployer
    const executor = await ethers.deployContract("Executor", [twoDaysInSeconds, ethers.constants.AddressZero]);

    // Deploy Governor second, starting with zero address (to allow calling "initialize" on the Governor)
    const governor = await ethers.deployContract("GovernorV1", [
        ethers.constants.AddressZero, // Executor
        ethers.constants.AddressZero, // Token
        twoDaysInBlocks, // initialVotingDelay
        threeDaysInBlocks, // initialVotingPeriod
        0 // initialProposalThreshold
    ]);

    // Initiate ownership transfer to Governor
    await executor.transferOwnership(governor.address);

    // Accept ownership in Governor and set the executor address
    await governor.initialize(executor.address);

    return {
        deployer,
        executor,
        governor
    }

}

