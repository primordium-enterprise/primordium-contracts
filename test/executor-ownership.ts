import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { deployBaseGovernance } from "./governance-fixtures";

describe("Executor", () => {

    it("Should show deployer as owner", async () => {

        const { deployer, executor } = await loadFixture(deployBaseGovernance);

        expect(await executor.owner()).to.equal(deployer.address);

    })
})