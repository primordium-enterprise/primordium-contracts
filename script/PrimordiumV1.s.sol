// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {BaseScriptV1, console2} from "./BaseV1.s.sol";
import {ImplementationsV1} from "./ImplementationsV1.s.sol";
import {PrimordiumTokenV1} from "src/token/PrimordiumTokenV1.sol";
import {PrimordiumSharesOnboarderV1} from "src/onboarder/PrimordiumSharesOnboarderV1.sol";
import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {DistributorV1} from "src/executor/extensions/DistributorV1.sol";
import {IDistributor} from "src/executor/extensions/interfaces/IDistributor.sol";
import {PrimordiumExecutorV1} from "src/executor/PrimordiumExecutorV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {ITreasurer} from "src/executor/interfaces/ITreasurer.sol";
import {AuthorizedInitializer} from "src/utils/AuthorizedInitializer.sol";
import {ISharesToken} from "src/token/interfaces/ISharesToken.sol";
import {ISharesOnboarder} from "src/onboarder/interfaces/ISharesOnboarder.sol";
import {IGovernorBase} from "src/governor/interfaces/IGovernorBase.sol";
import {IProposalVoting} from "src/governor/interfaces/IProposalVoting.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {stdJson} from "forge-std/StdJson.sol";

abstract contract PrimordiumV1 is BaseScriptV1, ImplementationsV1 {
    using stdJson for string;
    using SafeCast for uint256;

    // JSON configuration, loaded in from the `JSON_CONFIG_PATH` environment variable
    // Path should be formatted as "path/to/file.json", which is relative to project root
    string internal config;

    constructor() {
        string memory root = vm.projectRoot();
        string memory relativePath = vm.envString("JSON_CONFIG_PATH");
        string memory path = string.concat(root, "/", relativePath);
        config = vm.readFile(path);
    }

    function _deployAndSetupAllProxies()
        internal
        returns (
            PrimordiumExecutorV1 executor,
            PrimordiumTokenV1 token,
            PrimordiumSharesOnboarderV1 sharesOnboarder,
            PrimordiumGovernorV1 governor,
            DistributorV1 distributor
        )
    {
        executor = _deploy_ExecutorV1();
        token = _deploy_TokenV1();
        sharesOnboarder = _deploy_SharesOnboarderV1();
        governor = _deploy_GovernorV1();
        distributor = _deploy_DistributorV1();

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
        address distributor = _address_DistributorV1();

        address[] memory modules = new address[](1);
        modules[0] = governor;

        return PrimordiumExecutorV1.ExecutorV1Init({
            timelockAvatarInit: ITimelockAvatar.TimelockAvatarInit({
                minDelay: config.readUint(".executor.minDelay"),
                modules: modules
            }),
            treasurerInit: ITreasurer.TreasurerInit({
                token: token,
                sharesOnboarder: sharesOnboarder,
                balanceSharesManager: config.readAddress(".executor.balanceSharesManager"),
                balanceSharesManagerCalldatas: config.readBytesArray(".executor.balanceSharesManagerCalldatas"),
                distributor: distributor,
                distributionClaimPeriod: config.readUint(".executor.distributionClaimPeriod")
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
        return computeCreate2Address(deploySaltProxy, keccak256(_getExecutorV1InitCode()));
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
            name: config.readString(".token.name"),
            symbol: config.readString(".token.symbol"),
            sharesTokenInit: ISharesToken.SharesTokenInit({
                treasury: executor,
                maxSupply: config.readUint(".token.maxSupply")
            })
        });
    }

    function _getTokenV1InitCode() internal view returns (bytes memory) {
        return _getProxyInitCode(
            _address_implementation_TokenV1(), abi.encodeCall(PrimordiumTokenV1.setUp, (_getTokenV1InitParams()))
        );
    }

    function _address_TokenV1() internal view returns (address) {
        return computeCreate2Address(deploySaltProxy, keccak256(_getTokenV1InitCode()));
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
                quoteAsset: config.readAddress(".onboarder.quoteAsset"),
                quoteAmount: config.readUint(".onboarder.quoteAmount").toUint128(),
                mintAmount: config.readUint(".onboarder.mintAmount").toUint128(),
                fundingBeginsAt: config.readUint(".onboarder.fundingBeginsAt"),
                fundingEndsAt: config.readUint(".onboarder.fundingEndsAt")
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
        return computeCreate2Address(deploySaltProxy, keccak256(_getSharesOnboarderV1InitCode()));
    }

    function _deploy_SharesOnboarderV1() internal returns (PrimordiumSharesOnboarderV1 deployed) {
        deployed = PrimordiumSharesOnboarderV1(_deployProxy(_getSharesOnboarderV1InitCode()));
        require(address(deployed) == _address_SharesOnboarderV1(), "Shares Onboarder: invalid proxy deployment address");
    }

    /*/////////////////////////////////////////////////////////////////////////////
        PrimordiumGovernorV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _getGovernorV1InitParams() public view returns (PrimordiumGovernorV1.GovernorV1Init memory) {
        address executor = _address_ExecutorV1();
        address token = _address_TokenV1();

        // Setup the default proposer roles
        address[] memory proposerAddresses = config.readAddressArray(".governor.proposers");
        uint256[] memory expiresAts = config.readUintArray(".governor.proposersExpiresAts");
        bytes32[] memory roles = new bytes32[](proposerAddresses.length);

        require(proposerAddresses.length == expiresAts.length, "Invalid proposer role array lengths");
        bytes32 proposerRole = keccak256("PROPOSER");
        for (uint256 i = 0; i < proposerAddresses.length; i++) {
            roles[i] = proposerRole;
            // Change zero value to max value (infinite)
            if (expiresAts[i] == 0) {
                expiresAts[i] = type(uint256).max;
            }
        }

        // If array lengths are zero, then should set grantRoles to empty bytes, or else error will be thrown on setup
        bytes memory grantRoles =
            proposerAddresses.length > 0 ? abi.encode(roles, proposerAddresses, expiresAts) : bytes("");

        return PrimordiumGovernorV1.GovernorV1Init({
            name: "Primordium Governor",
            governorBaseInit: IGovernorBase.GovernorBaseInit({
                executor: executor,
                token: token,
                governanceCanBeginAt: config.readUint(".governor.governanceCanBeginAt"),
                governanceThresholdBps: config.readUint(".governor.governanceThresholdBps"),
                proposalThresholdBps: config.readUint(".governor.proposalThresholdBps"),
                votingDelay: config.readUint(".governor.votingDelay"),
                votingPeriod: config.readUint(".governor.votingPeriod"),
                gracePeriod: config.readUint(".governor.gracePeriod"),
                grantRoles: grantRoles
            }),
            proposalVotingInit: IProposalVoting.ProposalVotingInit({
                percentMajority: config.readUint(".governor.percentMajority"),
                quorumBps: config.readUint(".governor.quorumBps"),
                maxDeadlineExtension: config.readUint(".governor.maxDeadlineExtension"),
                baseDeadlineExtension: config.readUint(".governor.baseDeadlineExtension"),
                decayPeriod: config.readUint(".governor.decayPeriod"),
                percentDecay: config.readUint(".governor.percentDecay")
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
        return computeCreate2Address(deploySaltProxy, keccak256(_getGovernorV1InitCode()));
    }

    function _deploy_GovernorV1() internal returns (PrimordiumGovernorV1 deployed) {
        deployed = PrimordiumGovernorV1(_deployProxy(_getGovernorV1InitCode()));
        require(address(deployed) == _address_GovernorV1(), "Governor: invalid proxy deployment address");
    }

    /*/////////////////////////////////////////////////////////////////////////////
        DistributorV1
    /////////////////////////////////////////////////////////////////////////////*/

    function _getDistributorV1InitCode() internal view returns (bytes memory) {
        return _getProxyInitCode(
            _address_implementation_DistributorV1(),
            abi.encodeCall(AuthorizedInitializer.setAuthorizedInitializer, (_address_ExecutorV1()))
        );
    }

    function _address_DistributorV1() internal view returns (address) {
        return computeCreate2Address(deploySaltProxy, keccak256(_getDistributorV1InitCode()));
    }

    function _deploy_DistributorV1() internal returns (DistributorV1 deployed) {
        deployed = DistributorV1(_deployProxy(_getDistributorV1InitCode()));
        require(address(deployed) == _address_DistributorV1(), "Distributor: invalid proxy deployment address");
    }
}
