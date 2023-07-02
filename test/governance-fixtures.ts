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
        executor.address, // Executor
        ethers.constants.AddressZero, // Token
        twoDaysInBlocks, // initialVotingDelay
        threeDaysInBlocks, // initialVotingPeriod
        0 // initialProposalThreshold
    ]);

    await executor.transferOwnership(governor.address);

    const acceptOwnershipParameters = [
        governor.address,
        0,
        (await governor.populateTransaction.relay(
            executor.address,
            0,
            (await executor.populateTransaction.acceptOwnership()).data
        )).data,
        ethers.constants.HashZero,
        ethers.utils.keccak256(ethers.utils.arrayify(deployer.address)),
    ];

    await executor.schedule(...[...acceptOwnershipParameters, twoDaysInSeconds]);

    await time.increase(twoDaysInSeconds + 24);

    await executor.execute(...acceptOwnershipParameters);

    return {
        deployer,
        executor,
        governor
    }

}

