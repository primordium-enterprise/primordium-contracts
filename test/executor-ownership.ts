import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { deployBaseGovernance } from "./governance-fixtures";

describe("Executor", () => {

    it("Should show Governor as owner of Executor", async () => {
        const { governor, executor } = await loadFixture(deployBaseGovernance);
        expect(await executor.owner()).to.equal(governor.address);
    });

    it("Should show Executor as executor of Governor", async () => {
        const { governor, executor } = await loadFixture(deployBaseGovernance);
        expect (await governor.executor()).to.equal(executor.address);
    });

})