// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "contracts/executor/extensions/TreasurerOld.sol";
import "contracts/executor/extensions/treasurer/TreasurerBalanceShares.sol";
import "contracts/executor/extensions/treasurer/TreasurerDistributions.sol";
import "contracts/executor/extensions/treasurer/TreasurerETH.sol";
import "contracts/executor/extensions/treasurer/TreasurerERC20.sol";

abstract contract ExecutorBase is Test, TreasurerOld, TreasurerDistributions, TreasurerBalanceShares {

    constructor(
        uint256 minDelay_,
        address owner_,
        VotesProvisioner token_
    ) Executor(minDelay_, owner_) TreasurerOld(token_) {

    }

    function _treasuryBalance() internal view virtual override(TreasurerOld, TreasurerBalanceShares) returns (uint256) {
        return super._treasuryBalance();
    }

    function _governanceInitialized(
        uint256 baseAssetAmount
    ) internal virtual override(TreasurerOld, TreasurerBalanceShares) {
        super._governanceInitialized(baseAssetAmount);
    }

    function _registerDeposit(
        uint256 depositAmount,
        IVotesProvisioner.ProvisionMode currentProvisionMode
    ) internal virtual override(TreasurerOld, TreasurerBalanceShares) {
        super._registerDeposit(depositAmount, currentProvisionMode);
    }

}

abstract contract ExecutorHelper is Test {

    struct ExecutorConfig {
        uint256 minDelay;
        uint256 distributionClaimPeriod;
    }

    ExecutorBase executor;

}

contract ExecutorHelperETH is ExecutorHelper {

    // constructor(address token) {
    //     executor = new ExecutorETH(

    //     );
    // }
}