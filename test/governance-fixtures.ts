import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";
import { expect } from "chai";

export const deployBaseGovernance = async () => {

    // Contracts are deployed using the first signer/account by default
    const [deployer] = await ethers.getSigners();

    const twoDaysInSeconds = 2 * 24 * 60 * 60;
    const twoDaysInBlocks = twoDaysInSeconds / 12; // 12 sec/block
    const threeDaysInBlocks = twoDaysInBlocks * 1.5;

    // Deploy Votes first, using zero address for executor
    const votes = await ethers.deployContract("Mushi", [
        ethers.constants.AddressZero,
        ethers.utils.parseEther((10_000).toString())
    ]);

    // Deploy Executor, use zero address to set owner as the deployer
    const executor = await ethers.deployContract("PrimordiumExecutor", [
        twoDaysInSeconds,
        ethers.constants.AddressZero,
        votes.address
    ]);

    // Deploy Governor second, starting with zero address (to allow calling "initialize" on the Governor)
    const governor = await ethers.deployContract("GovernorV1", [
        ethers.constants.AddressZero, // Executor
        ethers.constants.AddressZero, // Token
        twoDaysInBlocks, // initialVotingDelay
        threeDaysInBlocks, // initialVotingPeriod
        0 // initialProposalThreshold
    ]);

    // Initialize the executor for the votes
    await votes.initializeExecutor(executor.address);

    // Initiate ownership transfer to Governor
    await executor.transferOwnership(governor.address);

    // Accept ownership in Governor and set the executor address
    await governor.initialize(executor.address);

    return {
        deployer,
        votes,
        executor,
        governor
    }

}

