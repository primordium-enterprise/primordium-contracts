// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PRBTest} from "@prb/test/PRBTest.sol";
import {Vm} from "@prb/test/Vm.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {ExecutorV1Harness} from "./harness/ExecutorV1Harness.sol";
import {GovernorV1Harness} from "./harness/GovernorV1Harness.sol";
import {SharesTokenV1Harness} from "./harness/SharesTokenV1Harness.sol";
import {OnboarderV1Harness} from "./harness/OnboarderV1Harness.sol";
import {DistributorV1Harness} from "./harness/DistributorV1Harness.sol";
import {BalanceSharesSingleton} from "balance-shares-protocol/BalanceSharesSingleton.sol";
import {ISharesOnboarder} from "src/onboarder/interfaces/ISharesOnboarder.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "./helpers/ERC20Mock.sol";
import {EIP712Utils} from "./helpers/EIP712Utils.sol";
import {Users} from "./helpers/Types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165Contract} from "./helpers/ERC165Contract.sol";

// Import console2 for easy import in other test files
import {console2} from "forge-std/console2.sol";

abstract contract BaseTest is PRBTest, StdCheats, StdUtils, EIP712Utils {
    Users internal users;

    uint256 internal constant STARTING_TIMESTAMP = 1703487600;
    uint256 internal constant STARTING_BLOCK = 18861890;

    uint256 internal constant MAX_BPS = 10_000;

    /*//////////////////////////////////////////////////////////
        MOCK CONTRACTS
    //////////////////////////////////////////////////////////*/

    ERC20Mock erc20Mock;
    address erc165Address;

    function _dealMockERC20(address to, uint256 give) internal {
        deal(address(erc20Mock), to, give, true);
    }

    /*//////////////////////////////////////////////////////////
        IMPLEMENTATION CONTRACTS
    //////////////////////////////////////////////////////////*/

    struct ExecutorParams {
        uint256 minDelay;
        uint256 distributionClaimPeriod;
    }

    ExecutorParams EXECUTOR = ExecutorParams({minDelay: 2 days, distributionClaimPeriod: 60 days});

    address internal executorImpl;
    ExecutorV1Harness internal executor;

    struct TokenParams {
        string name;
        string symbol;
        uint256 maxSupply;
    }

    TokenParams internal TOKEN = TokenParams({name: "Primordium", symbol: "MUSHI", maxSupply: 100_000_000 ether});

    address internal tokenImpl;
    SharesTokenV1Harness internal token;

    struct OnboarderParams {
        IERC20 quoteAsset;
        uint256 quoteAmount;
        uint256 mintAmount;
        uint256 fundingBeginsAt;
        uint256 fundingEndsAt;
    }

    OnboarderParams internal ONBOARDER = OnboarderParams({
        quoteAsset: IERC20(address(0)),
        quoteAmount: 10 gwei,
        mintAmount: 1 gwei,
        fundingBeginsAt: STARTING_TIMESTAMP,
        fundingEndsAt: STARTING_TIMESTAMP + 30 days
    });

    address internal onboarderImpl;
    OnboarderV1Harness internal onboarder;

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
        governanceCanBeginAt: STARTING_TIMESTAMP,
        governanceThresholdBps: 2000, // 20 %
        proposalThresholdBps: 2000, // 20%
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
    GovernorV1Harness internal governor;

    address internal distributorImpl;

    BalanceSharesSingleton balanceSharesSingleton;

    constructor() {
        vm.warp(STARTING_TIMESTAMP);
        vm.roll(STARTING_BLOCK);

        users = Users({
            proposer: _createUser("uProposer"),
            canceler: _createUser("uCanceler"),
            sharesGifter: _createUser("uSharesGifter"),
            sharesGiftReceiver: _createUser("uSharesGiftReceiver"),
            gwart: _createUser("uGwart"),
            bob: _createUser("uBob"),
            alice: _createUser("uAlice"),
            maliciousUser: _createUser("uMaliciousUser"),
            signer: vm.createWallet("uSigner"),
            balanceSharesReceiver: _createUser("uBalanceSharesRecipient")
        });

        erc20Mock = new ERC20Mock();
        vm.label({account: address(erc20Mock), newLabel: "ERC20Mock"});

        erc165Address = address(new ERC165Contract());
        vm.label({account: address(erc165Address), newLabel: "ERC165"});

        balanceSharesSingleton = new BalanceSharesSingleton();
        vm.label({account: address(balanceSharesSingleton), newLabel: "BalanceSharesSingleton"});
    }

    function setUp() public virtual {
        _deployAndInitializeDefaults();
    }

    function _deploy() internal {
        executorImpl = address(new ExecutorV1Harness());
        executor = ExecutorV1Harness(payable(address(new ERC1967Proxy(executorImpl, ""))));
        vm.label({account: address(executor), newLabel: "Executor"});

        tokenImpl = address(new SharesTokenV1Harness());
        token = SharesTokenV1Harness(address(new ERC1967Proxy(tokenImpl, "")));
        vm.label({account: address(token), newLabel: "SharesToken"});

        onboarderImpl = address(new OnboarderV1Harness());
        onboarder = OnboarderV1Harness(address(new ERC1967Proxy(onboarderImpl, "")));
        vm.label({account: address(onboarder), newLabel: "SharesOnboarder"});

        governorImpl = address(new GovernorV1Harness());
        governor = GovernorV1Harness(address(new ERC1967Proxy(governorImpl, "")));
        vm.label({account: address(governor), newLabel: "Governor"});

        distributorImpl = address(new DistributorV1Harness());
    }

    function _initializeDefaults() internal {
        _initializeToken();
        _initializeOnboarder();
        _initializeGovernor();
        // Governor is only module
        address[] memory modules = new address[](1);
        modules[0] = address(governor);
        _initializeExecutor(modules);
    }

    function _deployAndInitializeDefaults() internal {
        _deploy();
        _initializeDefaults();
    }

    function _initializeToken() internal {
        bytes memory sharesTokenInitParams = abi.encode(TOKEN.maxSupply, address(executor));
        token.setUp(address(executor), TOKEN.name, TOKEN.symbol, sharesTokenInitParams);
    }

    function _initializeOnboarder() internal {
        bytes memory sharesOnboarderInitParams = abi.encode(
            address(executor),
            ONBOARDER.quoteAsset,
            ISharesOnboarder.SharePrice({
                quoteAmount: uint128(ONBOARDER.quoteAmount),
                mintAmount: uint128(ONBOARDER.mintAmount)
            }),
            ONBOARDER.fundingBeginsAt,
            ONBOARDER.fundingEndsAt
        );
        onboarder.setUp(address(executor), sharesOnboarderInitParams);
    }

    function _initializeGovernor() internal {
        bytes memory governorBaseInitParams = abi.encode(
            address(executor), address(token), GOVERNOR.governanceCanBeginAt, GOVERNOR.governanceThresholdBps
        );

        bytes memory proposalsInitParams = abi.encode(
            GOVERNOR.proposalThresholdBps,
            GOVERNOR.votingDelay,
            GOVERNOR.votingPeriod,
            GOVERNOR.gracePeriod,
            _getDefaultGovernorRoles()
        );

        bytes memory proposalVotingInitParams = abi.encode(GOVERNOR.percentMajority, GOVERNOR.quorumBps);

        bytes memory proposalDeadlineExtensionsInitParams = abi.encode(
            GOVERNOR.maxDeadlineExtension,
            GOVERNOR.baseDeadlineExtension,
            GOVERNOR.extensionDecayPeriod,
            GOVERNOR.extensionPercentDecay
        );

        governor.setUp(
            GOVERNOR.name,
            governorBaseInitParams,
            proposalsInitParams,
            proposalVotingInitParams,
            proposalDeadlineExtensionsInitParams
        );
    }

    function _initializeExecutor(address[] memory modules) internal {
        bytes memory timelockAvatarInitParams = abi.encode(EXECUTOR.minDelay, modules);

        bytes memory treasurerInitParams = abi.encode(
            address(token),
            address(onboarder),
            address(0),
            "",
            type(ERC1967Proxy).creationCode,
            distributorImpl,
            EXECUTOR.distributionClaimPeriod
        );

        executor.setUp(timelockAvatarInitParams, treasurerInitParams);
    }

    function _getDefaultGovernorRoles() internal view returns (bytes memory) {
        bytes32[] memory roles = new bytes32[](2);
        address[] memory accounts = new address[](2);
        uint256[] memory expiresAts = new uint256[](2);

        roles[0] = governor.PROPOSER_ROLE();
        accounts[0] = users.proposer;
        expiresAts[0] = type(uint256).max;

        roles[1] = governor.CANCELER_ROLE();
        accounts[1] = users.canceler;
        expiresAts[1] = type(uint256).max;

        return abi.encode(roles, accounts, expiresAts);
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

    /**
     * @dev Wrapper around "deal" that gives specified amount of the quote asset to the address. Returns `amount` if the
     * quote asset is ETH, or zero otherwise.
     */
    function _giveQuoteAsset(address to, uint256 amount) internal returns (uint256 value) {
        address quoteAsset = address(onboarder.quoteAsset());
        if (quoteAsset == address(0)) {
            deal(to, amount);
            value = amount;
        } else {
            _dealMockERC20(to, amount);
        }
    }

    function _balanceOf(address account, IERC20 asset) internal view returns (uint256 balance) {
        if (address(asset) == address(0)) {
            balance = account.balance;
        } else {
            balance = IERC20(asset).balanceOf(account);
        }
    }

    function _quoteAssetBalanceOf(address account) internal view returns (uint256 balance) {
        balance = _balanceOf(account, onboarder.quoteAsset());
    }

    function _mintShares(address account, uint256 amount) internal {
        vm.prank(token.owner());
        token.mint(account, amount);
    }

    /// @dev Rolls forward the block.number by 1, ensuring votes count for proposal threshold if submitting a proposal
    function _mintSharesForVoting(address account, uint256 amount) internal {
        _mintSharesForVoting(account, amount, true);
    }

    /// @dev Includes true/false option for rolling forward
    function _mintSharesForVoting(address account, uint256 amount, bool rollForward) internal {
        _mintShares(account, amount);
        vm.prank(account);
        token.delegate(account);
        if (rollForward) {
            vm.roll(block.number + 1);
        }
    }
}
