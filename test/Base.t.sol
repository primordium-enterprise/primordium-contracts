// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PRBTest} from "@prb/test/PRBTest.sol";
import {Vm} from "@prb/test/Vm.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {ExecutorV1Harness, PrimordiumExecutorV1} from "./harness/ExecutorV1Harness.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {ITreasurer} from "src/executor/interfaces/ITreasurer.sol";
import {GovernorV1Harness, PrimordiumGovernorV1} from "./harness/GovernorV1Harness.sol";
import {IGovernorBase} from "src/governor/interfaces/IGovernorBase.sol";
import {IProposals} from "src/governor/interfaces/IProposals.sol";
import {IProposalVoting} from "src/governor/interfaces/IProposalVoting.sol";
import {IProposalDeadlineExtensions} from "src/governor/interfaces/IProposalDeadlineExtensions.sol";
import {TokenV1Harness, PrimordiumTokenV1} from "./harness/TokenV1Harness.sol";
import {ISharesToken} from "src/token/interfaces/ISharesToken.sol";
import {OnboarderV1Harness, PrimordiumSharesOnboarderV1} from "./harness/OnboarderV1Harness.sol";
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

    PrimordiumExecutorV1.ExecutorV1Init EXECUTOR = PrimordiumExecutorV1.ExecutorV1Init({
        timelockAvatarInit: ITimelockAvatar.TimelockAvatarInit({
            minDelay: 2 days,
            modules: new address[](0)
        }),
        treasurerInit: ITreasurer.TreasurerInit({
            token: address(0),
            sharesOnboarder: address(0),
            balanceSharesManager: address(0),
            balanceSharesManagerCalldatas: new bytes[](0),
            erc1967CreationCode: type(ERC1967Proxy).creationCode,
            distributorImplementation: address(0),
            distributionClaimPeriod: 60 days
        })
    });

    address internal executorImpl;
    ExecutorV1Harness internal executor;

    PrimordiumTokenV1.TokenV1Init internal TOKEN = PrimordiumTokenV1.TokenV1Init({
        owner: address(0),
        name: "Primordium",
        symbol: "MUSHI",
        sharesTokenInit: ISharesToken.SharesTokenInit({
            treasury: address(0),
            maxSupply: 100_000_000 ether
        })
    });

    address internal tokenImpl;
    TokenV1Harness internal token;

    PrimordiumSharesOnboarderV1.SharesOnboarderV1Init internal ONBOARDER = PrimordiumSharesOnboarderV1.SharesOnboarderV1Init({
        owner: address(0),
        sharesOnboarderInit: ISharesOnboarder.SharesOnboarderInit({
            treasury: address(0),
            quoteAsset: address(0),
            quoteAmount: 10 gwei,
            mintAmount: 1 gwei,
            fundingBeginsAt: STARTING_TIMESTAMP,
            fundingEndsAt: STARTING_TIMESTAMP + 30 days
        })
    });

    address internal onboarderImpl;
    OnboarderV1Harness internal onboarder;

    PrimordiumGovernorV1.GovernorV1Init internal GOVERNOR = PrimordiumGovernorV1.GovernorV1Init({
        name: "Primordium Governor",
        governorBaseInit: IGovernorBase.GovernorBaseInit({
            executor: address(0),
            token: address(0),
            governanceCanBeginAt: STARTING_TIMESTAMP,
            governanceThresholdBps: 2000 // 20 %
        }),
        proposalsInit: IProposals.ProposalsInit({
            proposalThresholdBps: 2000, // 20%
            votingDelay: _secondsToBlocks(2 days),
            votingPeriod: _secondsToBlocks(3 days),
            gracePeriod: _secondsToBlocks(21 days),
            initGrantRoles: ""
        }),
        proposalVotingInit: IProposalVoting.ProposalVotingInit({
            percentMajority: 50,
            quorumBps: 100 // 0.1%
        }),
        proposalDeadlineExtensionsInit: IProposalDeadlineExtensions.ProposalDeadlineExtensionsInit({
            maxDeadlineExtension: _secondsToBlocks(10 days),
            baseDeadlineExtension: _secondsToBlocks(2 days),
            decayPeriod: _secondsToBlocks(4 hours),
            percentDecay: 10 // base extension decays by 10% every decay period past original deadline
        })
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

        tokenImpl = address(new TokenV1Harness());
        token = TokenV1Harness(address(new ERC1967Proxy(tokenImpl, "")));
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
        TOKEN.owner = address(executor);
        TOKEN.sharesTokenInit.treasury = address(executor);
        token.setUp(TOKEN);
    }

    function _initializeOnboarder() internal {
        ONBOARDER.owner = address(executor);
        ONBOARDER.sharesOnboarderInit.treasury = address(executor);
        onboarder.setUp(ONBOARDER);
    }

    function _initializeGovernor() internal {
        GOVERNOR.governorBaseInit.executor = address(executor);
        GOVERNOR.governorBaseInit.token = address(token);
        GOVERNOR.proposalsInit.initGrantRoles = _getDefaultGovernorRoles();
        governor.setUp(GOVERNOR);
    }

    function _initializeExecutor(address[] memory modules) internal {
        EXECUTOR.timelockAvatarInit.modules = modules;
        EXECUTOR.treasurerInit.token = address(token);
        EXECUTOR.treasurerInit.sharesOnboarder = address(onboarder);
        EXECUTOR.treasurerInit.distributorImplementation = address(distributorImpl);
        executor.setUp(EXECUTOR);
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
