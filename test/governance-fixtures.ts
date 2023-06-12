import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";

export const deployBaseGovernance = async () => {

    // Contracts are deployed using the first signer/account by default
    const [deployer] = await ethers.getSigners();

    const twoDaysInSeconds = 2 * 24 * 60 * 60;

    const executor = await ethers.deployContract("Executor", [twoDaysInSeconds, ethers.constants.AddressZero]);
    const governor = await ethers.deployContract("Governor", [executor.address]);

    return {
        deployer,
        executor,
        governor
    }

}

