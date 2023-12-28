// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PRBTest} from "@prb/test/PRBTest.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {PrimordiumExecutorV1} from "src/executor/PrimordiumExecutorV1.sol";
import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {PrimordiumSharesTokenV1} from "src/token/PrimordiumSharesTokenV1.sol";
import {PrimordiumSharesOnboarderV1} from "src/onboarder/PrimordiumSharesOnboarderV1.sol";
import {Distributor} from "src/executor/extensions/Distributor.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "./helpers/MockERC20.sol";
import {Users} from "./helpers/Types.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract BaseTest is PRBTest, StdCheats {

    Users internal users;

    /*//////////////////////////////////////////////////////////
        MOCK CONTRACTS
    //////////////////////////////////////////////////////////*/

    MockERC20 mockERC20;

    function _dealMockERC20(address to, uint256 give) internal {
        deal(address(mockERC20), to, give, true);
    }

    /*//////////////////////////////////////////////////////////
        IMPLEMENTATION CONTRACTS
    //////////////////////////////////////////////////////////*/

    struct ExecutorParams {
        uint256 minDelay;
        uint256 distributionClaimPeriod;
    }

    ExecutorParams EXECUTOR = ExecutorParams({
        minDelay: 2 days,
        distributionClaimPeriod: 60 days
    });

    address internal executorImpl;
    PrimordiumExecutorV1 internal executor;

    struct TokenParams {
        string name;
        string symbol;
        uint256 maxSupply;
    }

    TokenParams internal TOKEN = TokenParams({
        name: "Primordium",
        symbol: "MUSHI",
        maxSupply: 100 ether
    });

    address internal tokenImpl;
    PrimordiumSharesTokenV1 internal token;

    struct OnboarderParams {
        IERC20 quoteAsset;
        uint256 quoteAmount;
        uint256 mintAmount;
        uint256 fundingBeginsAt;
        uint256 fundingEndsAt;
    }

    OnboarderParams internal ONBOARDER = OnboarderParams({
        quoteAsset: IERC20(address(0)),
        quoteAmount: 10 ether,
        mintAmount: 1 ether,
        fundingBeginsAt: block.timestamp,
        fundingEndsAt: block.timestamp + 365 days
    });

    address internal onboarderImpl;
    PrimordiumSharesOnboarderV1 internal onboarder;

    struct GovernorParams {
        string name;
        string version;
        uint256 governanceCanBeginAt;
        uint256 governanceThresholdBps;
        uint256 proposalThresholdBps;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 gracePeriod;
        uint256 percentMajority;
        uint256 quorumBps;
        uint256 maxDeadlineExtension;
        uint256 baseDeadlineExtension;
        uint256 extensionDecayPeriod;
        uint256 extensionPercentDecay;
    }

    GovernorParams internal GOVERNOR = GovernorParams({
        name: "Primordium Governor",
        version: "1",
        governanceCanBeginAt: block.timestamp + 1,
        governanceThresholdBps: 2000, // 20 %
        proposalThresholdBps: 1000, // 10%
        votingDelay: _secondsToBlocks(2 days),
        votingPeriod: _secondsToBlocks(3 days),
        gracePeriod: _secondsToBlocks(21 days),
        percentMajority: 50,
        quorumBps: 100, // 0.1%
        maxDeadlineExtension: _secondsToBlocks(10 days),
        baseDeadlineExtension: _secondsToBlocks(2 days),
        extensionDecayPeriod: _secondsToBlocks(4 hours),
        extensionPercentDecay: 10 // base extension decays by 10% every decay period past original deadline
    });

    address internal governorImpl;
    PrimordiumGovernorV1 internal governor;

    address internal distributorImpl;

    constructor() {
        users = Users({
            proposer: _createUser("uProposer"),
            canceler: _createUser("uCanceler"),
            sharesGifter: _createUser("uSharesGifter"),
            sharesGiftReceiver: _createUser("uSharesGiftReceiver"),
            gwart: _createUser("uGwart"),
            maliciousUser: _createUser("uMaliciousUser")
        });

        mockERC20 = new MockERC20();
        vm.label({ account: address(mockERC20), newLabel: "MockERC20" });
    }

    function setUp() public {
        _deploy();
    }

    function _deploy() internal {
        executorImpl = address(new PrimordiumExecutorV1());
        executor = PrimordiumExecutorV1(payable(address(new ERC1967Proxy(executorImpl, ''))));
        vm.label({ account: address(executor), newLabel: "Executor" });

        tokenImpl = address(new PrimordiumSharesTokenV1());
        token = PrimordiumSharesTokenV1(address(new ERC1967Proxy(tokenImpl, '')));
        vm.label({ account: address(token), newLabel: "SharesToken" });

        onboarderImpl = address(new PrimordiumSharesOnboarderV1());
        onboarder = PrimordiumSharesOnboarderV1(address(new ERC1967Proxy(onboarderImpl, '')));
        vm.label({ account: address(onboarder), newLabel: "SharesOnboarder" });

        governorImpl = address(new PrimordiumGovernorV1());
        governor = PrimordiumGovernorV1(address(new ERC1967Proxy(governorImpl, '')));
        vm.label({ account: address(governor), newLabel: "Governor" });

        distributorImpl = address(new Distributor());
    }

    function _deployAndInitializeDefaults() internal {

    }

    function _createUser(string memory name) internal returns (address payable user) {
        user = payable(makeAddr(name));
    }

    function _secondsToBlocks(uint256 durationInSeconds) internal pure returns (uint256 durationInBlocks) {
        durationInBlocks = durationInSeconds / _secondsPerBlock();
    }

    function _secondsPerBlock() internal pure virtual returns (uint256 secondsPerBlock) {
        return 12;
    }
}
