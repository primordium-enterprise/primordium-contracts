// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "contracts/executor/extensions/Treasurer.sol";
import "contracts/executor/extensions/treasurer/TreasurerBalanceShares.sol";
import "contracts/executor/extensions/treasurer/TreasurerDistributions.sol";
import "contracts/executor/extensions/treasurer/TreasurerETH.sol";
import "contracts/executor/extensions/treasurer/TreasurerERC20.sol";

abstract contract ExecutorBase is Test, Treasurer, TreasurerDistributions, TreasurerBalanceShares {

    constructor(
        uint256 minDelay_,
        address owner_,
        VotesProvisioner token_
    ) Executor(minDelay_, owner_) Treasurer(token_) {

    }

    function _governanceInitialized(
        uint256 baseAssetAmount
    ) internal virtual override(Treasurer, TreasurerBalanceShares) {
        super._governanceInitialized(baseAssetAmount);
    }

    function _registerDeposit(
        uint256 depositAmount,
        IVotesProvisioner.ProvisionMode currentProvisionMode
    ) internal virtual override(Treasurer, TreasurerBalanceShares) {
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