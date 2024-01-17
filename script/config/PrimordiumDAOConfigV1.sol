// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {BaseScriptV1, console2} from "../BaseV1.s.sol";
import {PrimordiumTokenV1} from "src/token/PrimordiumTokenV1.sol";
import {PrimordiumSharesOnboarderV1} from "src/onboarder/PrimordiumSharesOnboarderV1.sol";
import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {PrimordiumExecutorV1} from "src/executor/PrimordiumExecutorV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {ITreasurer} from "src/executor/interfaces/ITreasurer.sol";
import {AuthorizedInitializer} from "src/utils/AuthorizedInitializer.sol";
import {ISharesToken} from "src/token/interfaces/ISharesToken.sol";
import {ISharesOnboarder} from "src/onboarder/interfaces/ISharesOnboarder.sol";
import {IGovernorBase} from "src/governor/interfaces/IGovernorBase.sol";
import {IProposalVoting} from "src/governor/interfaces/IProposalVoting.sol";

abstract contract PrimordiumDAOConfigV1 is BaseScriptV1 {
    function _deployAndSetupAllProxies()
        internal
        returns (
            PrimordiumExecutorV1 executor,
            PrimordiumTokenV1 token,
            PrimordiumSharesOnboarderV1 sharesOnboarder,
            PrimordiumGovernorV1 governor
        )
    {
        executor = _deploy_ExecutorV1();
        console2.log("Executor:", address(executor));

        token = _deploy_TokenV1();
        console2.log("Token:", address(token));

        sharesOnboarder = _deploy_SharesOnboarderV1();
        console2.log("Shares Onboarder:", address(sharesOnboarder));

        governor = _deploy_GovernorV1();
        console2.log("Governor:", address(governor));

        // Still need to setup the executor
        PrimordiumExecutorV1(payable(executor)).setUp(_getExecutorV1InitParams());
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumExecutorV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _getExecutorV1InitParams() internal view returns (PrimordiumExecutorV1.ExecutorV1Init memory) {
        address token = _address_TokenV1();
        address sharesOnboarder = _address_SharesOnboarderV1();
        address governor = _address_GovernorV1();
        address distributorImpl = _address_implementation_DistributorV1();

        address[] memory modules = new address[](1);
        modules[0] = governor;

        return PrimordiumExecutorV1.ExecutorV1Init({
            timelockAvatarInit: ITimelockAvatar.TimelockAvatarInit({minDelay: 3 days, modules: modules}),
            treasurerInit: ITreasurer.TreasurerInit({
                token: token,
                sharesOnboarder: sharesOnboarder,
                balanceSharesManager: address(0),
                balanceSharesManagerCalldatas: new bytes[](0),
                erc1967CreationCode: type(ERC1967Proxy).creationCode,
                distributorImplementation: distributorImpl,
                distributionClaimPeriod: 60 days
            })
        });
    }

    function _getExecutorV1InitCode() internal view returns (bytes memory) {
        return _getProxyInitCode(
            _address_implementation_ExecutorV1(),
            abi.encodeCall(AuthorizedInitializer.setAuthorizedInitializer, (broadcaster))
        );
    }

    function _address_ExecutorV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(_getExecutorV1InitCode()));
    }

    /**
     * @dev The executor is deployed first, with the deployer as the authorized initializer (all subsequent create2
     * addresses are built on this as a starting point).
     */
    function _deploy_ExecutorV1() internal returns (PrimordiumExecutorV1 deployed) {
        deployed = PrimordiumExecutorV1(payable(_deployProxy(_getExecutorV1InitCode())));
        require(address(deployed) == _address_ExecutorV1(), "Executor: invalid proxy deployment address");
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumTokenV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _getTokenV1InitParams() internal view returns (PrimordiumTokenV1.TokenV1Init memory) {
        address executor = _address_ExecutorV1();
        return PrimordiumTokenV1.TokenV1Init({
            owner: executor,
            name: "Primordium",
            symbol: "MUSHI",
            sharesTokenInit: ISharesToken.SharesTokenInit({treasury: executor, maxSupply: 100_000})
        });
    }

    function _getTokenV1InitCode() internal view returns (bytes memory) {
        return _getProxyInitCode(
            _address_implementation_TokenV1(), abi.encodeCall(PrimordiumTokenV1.setUp, (_getTokenV1InitParams()))
        );
    }

    function _address_TokenV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(_getTokenV1InitCode()));
    }

    function _deploy_TokenV1() internal returns (PrimordiumTokenV1 deployed) {
        deployed = PrimordiumTokenV1(_deployProxy(_getTokenV1InitCode()));
        require(address(deployed) == _address_TokenV1(), "Token: invalid proxy deployment address");
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumSharesOnboarderV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _getSharesOnboarderV1InitParams()
        internal
        view
        returns (PrimordiumSharesOnboarderV1.SharesOnboarderV1Init memory)
    {
        address executor = _address_ExecutorV1();
        return PrimordiumSharesOnboarderV1.SharesOnboarderV1Init({
            owner: executor,
            sharesOnboarderInit: ISharesOnboarder.SharesOnboarderInit({
                treasury: executor,
                quoteAsset: address(0), // ETH
                quoteAmount: 10 gwei,
                mintAmount: 1 gwei,
                fundingBeginsAt: 1_705_708_800, // Janu 20th, 2024
                fundingEndsAt: type(uint256).max
            })
        });
    }

    function _getSharesOnboarderV1InitCode() internal view returns (bytes memory) {
        return _getProxyInitCode(
            _address_implementation_SharesOnboarderV1(),
            abi.encodeCall(PrimordiumSharesOnboarderV1.setUp, (_getSharesOnboarderV1InitParams()))
        );
    }

    function _address_SharesOnboarderV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(_getSharesOnboarderV1InitCode()));
    }

    function _deploy_SharesOnboarderV1() internal returns (PrimordiumSharesOnboarderV1 deployed) {
        deployed = PrimordiumSharesOnboarderV1(_deployProxy(_getSharesOnboarderV1InitCode()));
        require(address(deployed) == _address_SharesOnboarderV1(), "Shares Onboarder: invalid proxy deployment address");
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumGovernorV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _getGovernorV1InitParams() internal view returns (PrimordiumGovernorV1.GovernorV1Init memory) {
        address executor = _address_ExecutorV1();
        address token = _address_TokenV1();
        return PrimordiumGovernorV1.GovernorV1Init({
            name: "Primordium Governor",
            governorBaseInit: IGovernorBase.GovernorBaseInit({
                executor: executor,
                token: token,
                governanceCanBeginAt: 1_706_745_600, // Feb 1, 2024
                governanceThresholdBps: 500, // 5 %
                proposalThresholdBps: 50, // 0.5%
                votingDelay: 2 days / 12,
                votingPeriod: 3 days / 12,
                gracePeriod: 3 weeks / 12,
                grantRoles: ""
            }),
            proposalVotingInit: IProposalVoting.ProposalVotingInit({
                percentMajority: 50,
                quorumBps: 100, // 1%
                maxDeadlineExtension: 7 days / 12,
                baseDeadlineExtension: 2 days / 12,
                decayPeriod: 4 hours / 12,
                percentDecay: 4 // base extension decays by 4% every decay period past original deadline
            })
        });
    }

    function _getGovernorV1InitCode() internal view returns (bytes memory) {
        return _getProxyInitCode(
            _address_implementation_GovernorV1(),
            abi.encodeCall(PrimordiumGovernorV1.setUp, (_getGovernorV1InitParams()))
        );
    }

    function _address_GovernorV1() internal view returns (address) {
        return computeCreate2Address(deploySalt, keccak256(_getGovernorV1InitCode()));
    }

    function _deploy_GovernorV1() internal returns (PrimordiumGovernorV1 deployed) {
        deployed = PrimordiumGovernorV1(_deployProxy(_getGovernorV1InitCode()));
        require(address(deployed) == _address_GovernorV1(), "Governor: invalid proxy deployment address");
    }
}
