import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { deployBaseGovernance } from "./governance-fixtures";
import { ethers } from "hardhat";

describe("Ownership", () => {

    it("Should show Governor as _owner of Executor", async () => {
        const { governor, executor } = await loadFixture(deployBaseGovernance);
        expect(await executor.owner()).to.equal(governor.address);
    });

    it("Should show Executor as _executor of Governor", async () => {
        const { governor, executor } = await loadFixture(deployBaseGovernance);
        expect(await governor.executor()).to.equal(executor.address);
    });

    it("Should show Votes as _votes of Execuotr", async () => {
        const { votes, executor } = await loadFixture(deployBaseGovernance);
        expect(await executor.votes()).to.equal(votes.address);
    })

    it("Should show Executor as _executor of Votes", async () => {
        const { votes, executor } = await loadFixture(deployBaseGovernance);
        expect(await votes.executor()).to.equal(executor.address);
    })

    it("Should NOT let you update the _executor address outside of a proposal", async () => {
        const { governor } = await loadFixture(deployBaseGovernance);
        await expect(governor.updateExecutor(ethers.constants.AddressZero))
            .to.be.revertedWith("Governor: onlyGovernance");
    });

})