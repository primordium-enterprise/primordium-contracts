// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (Governor.sol)

pragma solidity ^0.8.20;

import {GovernorBaseLogicV1} from "./logic/GovernorBaseLogicV1.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {IGovernorBase} from "../interfaces/IGovernorBase.sol";
import {IGovernorToken} from "../interfaces/IGovernorToken.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Roles} from "src/utils/Roles.sol";
import {RolesLib} from "src/libraries/RolesLib.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";

/**
 * @title GovernorBase
 * @author Ben Jett - @BCJdevelopment
 * @notice The base governance storage for the Governor, and the base proposal logic.
 * @dev Uses the zodiac-based TimelockAvatar contract as the executor, and uses an IERC5805 vote token for tracking
 * voting weights.
 */
abstract contract GovernorBase is
    Initializable,
    ContextUpgradeable,
    EIP712Upgradeable,
    NoncesUpgradeable,
    IGovernorBase,
    Roles
{
    using SafeCast for uint256;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    /**
     * @dev Restricts a function so it can only be executed through governance proposals. For example, governance
     * parameter setters in {GovernorSettings} are protected using this modifier.
     */
    modifier onlyGovernance() {
        _onlyGovernance();
        _;
    }

    function _onlyGovernance() private {
        GovernorBaseLogicV1.GovernorBaseExecutorStorage storage $ = GovernorBaseLogicV1._getExecutorStorage();
        if (msg.sender != address(executor())) {
            revert IGovernorBase.OnlyGovernance();
        }

        bytes32 msgDataHash = keccak256(_msgData());
        // loop until popping the expected operation - throw if deque is empty (operation not authorized)
        while ($._governanceCall.popFront() != msgDataHash) {}
    }

    function __GovernorBase_init_unchained(GovernorBaseInit memory init) internal virtual onlyInitializing {
        if (init.governanceThresholdBps > BasisPoints.MAX_BPS) {
            revert BasisPoints.BPSValueTooLarge(init.governanceThresholdBps);
        }

        // Initialize executor
        if (address(executor()) != address(0)) {
            revert IGovernorBase.GovernorExecutorAlreadyInitialized();
        }
        _setExecutor(init.executor);

        GovernorBaseLogicV1.GovernorBaseStorage storage $ = GovernorBaseLogicV1._getGovernorBaseStorage();
        $._token = IGovernorToken(init.token);
        $._governanceCanBeginAt = SafeCast.toUint40(init.governanceCanBeginAt);
        // If it is less than the MAX_BPS (10_000), it fits into uint16 without SafeCast
        $._governanceThresholdBps = uint16(init.governanceThresholdBps);

        _setProposalThresholdBps(init.proposalThresholdBps);
        _setVotingDelay(init.votingDelay);
        _setVotingPeriod(init.votingPeriod);
        _setProposalGracePeriod(init.gracePeriod);

        if (init.grantRoles.length > 0) {
            (bytes32[] memory roles, address[] memory accounts, uint256[] memory expiresAts) =
                abi.decode(init.grantRoles, (bytes32[], address[], uint256[]));
            RolesLib._grantRoles(roles, accounts, expiresAts);
        }

        emit IGovernorBase.GovernorBaseInitialized(
            init.executor, init.token, init.governanceCanBeginAt, init.governanceThresholdBps, $._isFounded
        );
    }

    /*//////////////////////////////////////////////////////////////////////////
        BASE GOVERNOR SETTINGS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGovernorBase
    function name() public view virtual override returns (string memory) {
        return _EIP712Name();
    }

    /// @inheritdoc IGovernorBase
    function version() public view virtual override returns (string memory) {
        return "1";
    }

    /// @inheritdoc IGovernorBase
    function executor() public view returns (ITimelockAvatar _executor) {
        return GovernorBaseLogicV1._executor();
    }

    /// @inheritdoc IGovernorBase
    function setExecutor(address newExecutor) external virtual onlyGovernance {
        _setExecutor(newExecutor);
    }

    function _setExecutor(address newExecutor) internal virtual {
        GovernorBaseLogicV1.setExecutor(newExecutor);
    }

    /// @inheritdoc IGovernorBase
    function token() public view returns (IGovernorToken _token) {
        return GovernorBaseLogicV1._token();
    }

    /// @inheritdoc IERC6372
    function clock() public view virtual override returns (uint48) {
        return GovernorBaseLogicV1._clock();
    }

    /// @inheritdoc IERC6372
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        try token().CLOCK_MODE() returns (string memory clockmode) {
            return clockmode;
        } catch {
            return "mode=blocknumber&from=default";
        }
    }

    /// @inheritdoc IGovernorBase
    function governanceCanBeginAt() public view returns (uint256 _governanceCanBeginAt) {
        return GovernorBaseLogicV1._governanceCanBeginAt();
    }

    /// @inheritdoc IGovernorBase
    function governanceFoundingVoteThreshold() public view returns (uint256 threshold) {
        return GovernorBaseLogicV1.governanceFoundingVoteThreshold();
    }

    /// @inheritdoc IGovernorBase
    function foundGovernor(uint256 proposalId) external virtual onlyGovernance {
        _foundGovernor(proposalId);
    }

    /// @dev The proposalId will be verified when the proposal is created.
    function _foundGovernor(uint256 proposalId) internal virtual {
        GovernorBaseLogicV1.foundGovernor(proposalId);
    }

    /// @inheritdoc IGovernorBase
    function isFounded() public view virtual returns (bool _isFounded) {
        _isFounded = GovernorBaseLogicV1._isFounded();
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL GETTERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGovernorBase
    function PROPOSER_ROLE() external pure virtual returns (bytes32) {
        return GovernorBaseLogicV1._PROPOSER_ROLE;
    }

    /// @inheritdoc IGovernorBase
    function CANCELER_ROLE() external pure virtual returns (bytes32) {
        return GovernorBaseLogicV1._CANCELER_ROLE;
    }

    /// @inheritdoc IGovernorBase
    function proposalCount() public view virtual returns (uint256 count) {
        return GovernorBaseLogicV1._proposalCount();
    }

    /// @inheritdoc IGovernorBase
    function proposalSnapshot(uint256 proposalId) public view virtual returns (uint256 snapshot) {
        return GovernorBaseLogicV1._proposalSnapshot(proposalId);
    }

    /// @inheritdoc IGovernorBase
    function proposalDeadline(uint256 proposalId) public view virtual returns (uint256 deadline) {
        return GovernorBaseLogicV1._proposalDeadline(proposalId);
    }

    /// @inheritdoc IGovernorBase
    function proposalProposer(uint256 proposalId) public view virtual returns (address proposer) {
        return GovernorBaseLogicV1._proposalProposer(proposalId);
    }

    /// @inheritdoc IGovernorBase
    function proposalActionsHash(uint256 proposalId) public view virtual returns (bytes32 actionsHash) {
        return GovernorBaseLogicV1._proposalActionsHash(proposalId);
    }

    /// @inheritdoc IGovernorBase
    function proposalEta(uint256 proposalId) public view virtual returns (uint256 eta) {
        return GovernorBaseLogicV1._proposalEta(proposalId);
    }

    /// @inheritdoc IGovernorBase
    function proposalOpNonce(uint256 proposalId) public view virtual returns (uint256 opNonce) {
        return GovernorBaseLogicV1._proposalOpNonce(proposalId);
    }

    /// @inheritdoc IGovernorBase
    function getVotes(address account, uint256 timepoint) public view virtual returns (uint256) {
        return GovernorBaseLogicV1._getVotes(account, timepoint, _defaultParams());
    }

    /// @inheritdoc IGovernorBase
    function getVotesWithParams(
        address account,
        uint256 timepoint,
        bytes memory params
    )
        public
        view
        virtual
        override
        returns (uint256)
    {
        return GovernorBaseLogicV1._getVotes(account, timepoint, params);
    }

    /// @inheritdoc IGovernorBase
    function hashProposalActions(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
        pure
        virtual
        returns (bytes32 actionsHash)
    {
        actionsHash = GovernorBaseLogicV1.hashProposalActions(targets, values, calldatas);
    }

    /// @inheritdoc IGovernorBase
    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        return GovernorBaseLogicV1.state(proposalId);
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL SETTINGS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGovernorBase
    function proposalThreshold() public view virtual returns (uint256 _proposalThreshold) {
        return GovernorBaseLogicV1.proposalThreshold();
    }

    /// @inheritdoc IGovernorBase
    function proposalThresholdBps() public view virtual returns (uint256 _proposalThresholdBps) {
        return GovernorBaseLogicV1._proposalThresholdBps();
    }

    /// @inheritdoc IGovernorBase
    function setProposalThresholdBps(uint256 newProposalThresholdBps) public virtual onlyGovernance {
        _setProposalThresholdBps(newProposalThresholdBps);
    }

    function _setProposalThresholdBps(uint256 newProposalThresholdBps) internal virtual {
        GovernorBaseLogicV1.setProposalThresholdBps(newProposalThresholdBps);
    }

    /// @inheritdoc IGovernorBase
    function votingDelay() public view virtual returns (uint256 _votingDelay) {
        return GovernorBaseLogicV1._votingDelay();
    }

    /// @inheritdoc IGovernorBase
    function setVotingDelay(uint256 newVotingDelay) public virtual onlyGovernance {
        _setVotingDelay(newVotingDelay);
    }

    function _setVotingDelay(uint256 newVotingDelay) internal virtual {
        GovernorBaseLogicV1.setVotingDelay(newVotingDelay);
    }

    /// @inheritdoc IGovernorBase
    function votingPeriod() public view virtual returns (uint256 _votingPeriod) {
        return GovernorBaseLogicV1._votingPeriod();
    }

    /// @inheritdoc IGovernorBase
    function setVotingPeriod(uint256 newVotingPeriod) public virtual onlyGovernance {
        _setVotingPeriod(newVotingPeriod);
    }

    function _setVotingPeriod(uint256 newVotingPeriod) internal virtual {
        GovernorBaseLogicV1.setVotingPeriod(newVotingPeriod);
    }

    /// @inheritdoc IGovernorBase
    function proposalGracePeriod() public view virtual returns (uint256 _gracePeriod) {
        return GovernorBaseLogicV1._proposalGracePeriod();
    }

    /// @inheritdoc IGovernorBase
    function setProposalGracePeriod(uint256 newGracePeriod) public virtual onlyGovernance {
        _setProposalGracePeriod(newGracePeriod);
    }

    function _setProposalGracePeriod(uint256 newGracePeriod) internal virtual {
        GovernorBaseLogicV1.setProposalGracePeriod(newGracePeriod);
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL CREATION/EXECUTION LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGovernorBase
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string[] memory signatures,
        string calldata description
    )
        public
        virtual
        returns (uint256 proposalId)
    {
        proposalId = GovernorBaseLogicV1.propose(targets, values, calldatas, signatures, description, _msgSender());
    }

    /// @inheritdoc IGovernorBase
    function queue(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
        virtual
        returns (uint256)
    {
        return GovernorBaseLogicV1.queue(proposalId, targets, values, calldatas);
    }

    /// @inheritdoc IGovernorBase
    function execute(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
        virtual
        returns (uint256)
    {
        return GovernorBaseLogicV1.execute(proposalId, targets, values, calldatas);
    }

    /// @inheritdoc IGovernorBase
    function cancel(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
        returns (uint256)
    {
        return GovernorBaseLogicV1.cancel(proposalId, targets, values, calldatas);
    }

    /// @inheritdoc IGovernorBase
    function grantRoles(
        bytes32[] memory roles,
        address[] memory accounts,
        uint256[] memory expiresAts
    )
        public
        virtual
        override
        onlyGovernance
    {
        RolesLib._grantRoles(roles, accounts, expiresAts);
    }

    /// @inheritdoc IGovernorBase
    function revokeRoles(bytes32[] memory roles, address[] memory accounts) public virtual override onlyGovernance {
        RolesLib._revokeRoles(roles, accounts);
    }

    /**
     * @dev Default additional encoded parameters used by castVote methods that don't include them
     *
     * Note: Should be overridden by specific implementations to use an appropriate value, the
     * meaning of the additional params, in the context of that implementation
     */
    function _defaultParams() internal pure virtual returns (bytes memory) {
        return GovernorBaseLogicV1._defaultParams();
    }

    /**
     * @dev Relays a transaction or function call to an arbitrary target. In cases where the governance _executor
     * is some contract other than the governor itself, like when using a timelock, this function can be invoked
     * in a governance proposal to recover tokens or Ether that was sent to the governor contract by mistake.
     * Note that if the _executor is simply the governor itself, use of `relay` is redundant.
     */
    function relay(address target, uint256 value, bytes memory data) external payable virtual onlyGovernance {
        assembly ("memory-safe") {
            if iszero(call(gas(), target, value, add(data, 0x20), mload(data), 0, 0)) {
                if gt(returndatasize(), 0) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
                mstore(0, 0xbe73bd9d) // bytes4(keccak256(GovernorRelayFailed()))
                revert(0x1c, 0x04)
            }
        }
    }
}
