// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (Governor.sol)

pragma solidity ^0.8.20;

import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IGovernorBase} from "../interfaces/IGovernorBase.sol";
import {IGovernorToken} from "../interfaces/IGovernorToken.sol";
import {Roles} from "contracts/utils/Roles.sol";
import {ClockUtils} from "contracts/utils/ClockUtils.sol";
import {TimelockAvatarControlled} from "./TimelockAvatarControlled.sol";
import {ITimelockAvatar} from "contracts/executor/interfaces/ITimelockAvatar.sol";
import {Enum} from "contracts/common/Enum.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {SelectorChecker} from "contracts/libraries/SelectorChecker.sol";
import {MultiSendEncoder} from "contracts/libraries/MultiSendEncoder.sol";
import {BasisPoints} from "contracts/libraries/BasisPoints.sol";

/**
 * @title GovernorBase
 *
 * @notice Based on the OpenZeppelin Governor.sol contract.
 *
 * @dev Core of the governance system, designed to be extended though various modules.
 *
 * Uses the zodiac TimelockAvatar contract as the executor, and uses an IERC5805 vote token for tracking voting weights.
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract GovernorBase is
    TimelockAvatarControlled,
    ERC165,
    EIP712Upgradeable,
    IGovernorBase,
    Roles,
    ClockUtils
{
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using SafeCast for uint256;
    using BasisPoints for uint256;

    struct ProposalCore {
        bytes32 actionsHash;
        address proposer;
        uint48 voteStart;
        uint32 voteDuration;
        bool executed;
        bool canceled;
        uint48 etaSeconds;
    }

    struct VotesManagement {
        IGovernorToken _token; // 20 bytes
        bool _isFounded; // 1 byte
        uint40 _governanceCanBeginAt; // 5 bytes
        uint16 _governanceThresholdBps; // 2 bytes
    }

    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");
    bytes32 public constant EXTENDED_BALLOT_TYPEHASH =
        keccak256("ExtendedBallot(uint256 proposalId,uint8 support,string reason,bytes params)");

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER");
    bytes32 public constant CANCELER_ROLE = keccak256("CANCELER");

    /// @custom:storage-location erc7201:GovernorBase.Storage
    struct GovernorBaseStorage {
        uint256 _proposalCount;

        mapping(uint256 => ProposalCore) _proposals;

        // Tracking queued operations on the TimelockAvatar
        mapping(uint256 => uint256) _opNonces;

        VotesManagement _votesManagement;
    }

    bytes32 private immutable GOVERNOR_BASE_STORAGE =
        keccak256(abi.encode(uint256(keccak256("GovernorBase.Storage")) - 1)) & ~bytes32(uint256(0xff));

    function _getGovernorBaseStorage() private view returns (GovernorBaseStorage storage $) {
        bytes32 governorBaseStorageSlot = GOVERNOR_BASE_STORAGE;
        assembly {
            $.slot := governorBaseStorageSlot
        }
    }

    function __GovernorBase_init(
        string calldata name_,
        address executor_,
        address token_,
        uint256 governanceCanBeginAt_,
        uint256 governanceThresholdBps_
    ) internal virtual onlyInitializing {
        if (governanceThresholdBps_ > BasisPoints.MAX_BPS) {
            revert BasisPoints.BPSValueTooLarge(governanceThresholdBps_);
        }

        string memory version_ = version();
        __EIP712_init(name_, version_);
        __TimelockAvatarControlled_init(executor_);

        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        $._votesManagement._token = IGovernorToken(token_);
        $._votesManagement._governanceCanBeginAt = governanceCanBeginAt_.toUint40();
        // If it is less than the MAX_BPS (10_000), it fits into uint16 without SafeCast
        $._votesManagement._governanceThresholdBps = uint16(governanceThresholdBps_);

        emit GovernorBaseInitialized(
            name_,
            version_,
            executor_,
            token_,
            governanceCanBeginAt_,
            governanceThresholdBps_,
            $._votesManagement._isFounded
        );
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165) returns (bool) {
        // In addition to the current interfaceId, also support previous version of the interfaceId that did not
        // include the castVoteWithReasonAndParams() function as standard
        return
            interfaceId == type(IGovernorBase).interfaceId ||
            // Previous interface for backwards compatibility
            interfaceId == (type(IGovernorBase).interfaceId ^ type(IERC6372).interfaceId ^ this.cancel.selector) ||
            super.supportsInterface(interfaceId);
    }

    // TODO: This must be turned into a state variable to ensure upgradeability
    /// @inheritdoc IGovernorBase
    function name() public view virtual override returns (string memory) {
        return _EIP712Name();
    }

    /// @inheritdoc IGovernorBase
    function version() public view virtual override returns (string memory) {
        return "1";
    }

    /// @inheritdoc IGovernorBase
    function token() public view returns (IGovernorToken _token) {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        _token = $._votesManagement._token;
    }

    /// @inheritdoc IERC6372
    function clock() public view virtual override(ClockUtils, IERC6372) returns (uint48) {
        return _clock(token());
    }

    function _clock(IGovernorToken _token) internal view virtual returns (uint48) {
        try _token.clock() returns (uint48 timepoint) {
            return timepoint;
        } catch {
            return Time.blockNumber();
        }
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
        _governanceCanBeginAt = _getGovernorBaseStorage()._votesManagement._governanceCanBeginAt;
    }

    /// @inheritdoc IGovernorBase
    function governanceThresholdBps() public view returns (uint256 _governanceThresholdBps) {
        _governanceThresholdBps = _getGovernorBaseStorage()._votesManagement._governanceThresholdBps;
    }

    /// @inheritdoc IGovernorBase
    function initializeGovernance() external virtual onlyGovernance {
        _initializeGovernance();
    }

    function _initializeGovernance() internal virtual {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        $._votesManagement._isFounded = true;
        emit GovernanceInitialized();
    }

    /// @inheritdoc IGovernorBase
    function isGovernanceActive() public view virtual returns (bool _isGovernanceActive) {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        _isGovernanceActive = $._votesManagement._isFounded;
    }

    /// @inheritdoc IGovernorBase
    function proposalCount() public view virtual returns (uint256 _proposalCount) {
        _proposalCount = _getGovernorBaseStorage()._proposalCount;
    }

    /**
     * @dev Defaults to 10e18, which is equivalent to 1 ERC20 vote token with a decimals() value of 18.
     */
    function proposalThreshold() public view virtual returns (uint256) {
        return 10e18;
    }

    /**
     * @dev See {IGovernor-state}.
     */
    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();

        // Single SLOAD
        ProposalCore storage proposal = $._proposals[proposalId];
        bool proposalExecuted = proposal.executed;
        bool proposalCanceled = proposal.canceled;

        if (proposalExecuted) {
            return ProposalState.Executed;
        }

        if (proposalCanceled) {
            return ProposalState.Canceled;
        }

        uint256 snapshot = proposalSnapshot(proposalId);

        if (snapshot == 0) {
            revert UnknownProposalId(proposalId);
        }

        uint256 currentTimepoint = clock();

        if (snapshot >= currentTimepoint) {
            return ProposalState.Pending;
        }

        uint256 deadline = proposalDeadline(proposalId);

        if (deadline >= currentTimepoint) {
            return ProposalState.Active;
        }

        // If no quorum was reached, or if the vote did not succeed, the proposal is defeated
        if (!_quorumReached(proposalId) || !_voteSucceeded(proposalId)) {
            return ProposalState.Defeated;
        }

        uint256 opNonce = $._opNonces[proposalId];
        if (opNonce == 0) {
            return ProposalState.Succeeded;
        }

        ITimelockAvatar.OperationStatus opStatus = executor().getOperationStatus(opNonce);
        if (opStatus == ITimelockAvatar.OperationStatus.Done) {
            return ProposalState.Executed;
        }
        if (opStatus == ITimelockAvatar.OperationStatus.Expired) {
            return ProposalState.Expired;
        }

        return ProposalState.Queued;
    }

    /// @inheritdoc IGovernorBase
    function proposalSnapshot(uint256 proposalId) public view virtual override returns (uint256) {
        return _getGovernorBaseStorage()._proposals[proposalId].voteStart;
    }

    /// @inheritdoc IGovernorBase
    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256) {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        return $._proposals[proposalId].voteStart + $._proposals[proposalId].voteDuration;
    }

    /// @inheritdoc IGovernorBase
    function proposalActionsHash(uint256 proposalId) public view virtual override returns (bytes32) {
        return _getGovernorBaseStorage()._proposals[proposalId].actionsHash;
    }

    /// @inheritdoc IGovernorBase
    function proposalProposer(uint256 proposalId) public view virtual override returns (address) {
        return _getGovernorBaseStorage()._proposals[proposalId].proposer;
    }

    /// @inheritdoc IGovernorBase
    function proposalEta(uint256 proposalId) public view virtual override returns (uint256) {
        return _getGovernorBaseStorage()._proposals[proposalId].etaSeconds;
    }

    /**
     * @dev See {IGovernor-hashProposaActions}.
     *
     * The actionsHash is produced by hashing the ABI encoded 'proposalId', the `targets` array, the `values` array, and
     *  the `calldatas` array.
     * This can be reproduced from the proposal data which is part of the {ProposalCreated} event.
     *
     * Note that the chainId and the governor address are not part of the proposal id computation. Consequently, the
     * same proposal (with same operation and same description) will have the same id if submitted on multiple governors
     * across multiple networks. This also means that in order to execute the same operation twice (on the same
     * governor) the proposer will have to change the description in order to avoid proposal id conflicts.
     */
    function hashProposalActions(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) public pure virtual override returns (bytes32) {
        return keccak256(abi.encode(proposalId, targets, values, calldatas));
    }

    // TODO: Document this with signatures, etc.
    /**
     * @dev See {IGovernor-propose}.
     */
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string[] calldata signatures,
        string calldata description
    ) public virtual override returns (uint256) {

        address proposer = _msgSender();

        (, uint256 currentClock) = _authorizeProposal(proposer, targets, values, calldatas);

        (uint256 _votingDelay, uint256 duration) = _getVotingDelayAndPeriod();

        return _propose(
            proposer,
            currentClock + _votingDelay,
            duration,
            targets,
            values,
            calldatas,
            signatures,
            description
        );

    }

    /**
     * @dev Authorizes whether a proposal can be submitted by the provided proposer.
     *
     * @notice This function also checks whether the Governor has been founded, and restricts proposals to only
     * initializing governance if the Governor is not yet founded.
     *
     * @return _token The IGovernorToken token read from storage for internal gas optimization
     * @return currentClock The current clock() value for the token for internal gas optimization (avoid re-calling)
     */
    function _authorizeProposal(
        address proposer,
        address[] calldata targets,
        uint256[] calldata /*values*/,
        bytes[] calldata calldatas
    ) internal view virtual returns (IGovernorToken _token, uint256 currentClock) {
        VotesManagement storage _votesManagement = _getGovernorBaseStorage()._votesManagement;

        bytes32 packedVotesManagement;
        bool isFounded;
        assembly {
            packedVotesManagement := sload(_votesManagement.slot)
            _token := packedVotesManagement
            // The _isFounded bool is at byte index 20 (after the 20 address bytes)
            isFounded := byte(0x14, packedVotesManagement)
        }

        currentClock = _clock(_token);

        // Check if the Governor has been founded yet
        if (!isFounded) {

            uint256 _governanceCanBeginAt;
            assembly {
                // Shift right by 20 address bytes + 1 bool byte = 21 bytes * 8 = 168 bits
                _governanceCanBeginAt := and(shr(0xa8, packedVotesManagement), 0xffffffffff)
            }
            if (block.timestamp < _governanceCanBeginAt) {
                revert GovernanceCannotInitializeYet(_governanceCanBeginAt);
            }

            uint256 _governanceThresholdBps;
            assembly {
                // Shift right by 20 address bytes + 1 bool byte + 5 uint40 bytes = 26 bytes * 8 = 208 bits
                _governanceThresholdBps := and(shr(0xd0, packedVotesManagement), 0xffff)
            }
            uint256 currentVoteSupply = _token.getPastTotalSupply(currentClock - 1);
            uint256 requiredVoteSupply = _token.maxSupply().bpsUnchecked(_governanceThresholdBps);
            if (requiredVoteSupply > currentVoteSupply) {
                revert GovernanceThresholdIsNotMet(_governanceThresholdBps, currentVoteSupply, requiredVoteSupply);
            }

            // Ensure that the proposal action is to initializeGovernance() on this Governor
            if (
                targets.length != 1 ||
                targets[0] != address(this) ||
                bytes4(calldatas[0]) != this.initializeGovernance.selector
            ) {
                revert GovernanceInitializationActionRequired();
            }
        }

        // Check the proposer's votes against the proposalThreshold(), also check the proposer's role
        if (
            _getVotes(_token, proposer, currentClock - 1, _defaultParams()) < proposalThreshold() &&
            !_hasRole(PROPOSER_ROLE, proposer)
        ) revert UnauthorizedToSubmitProposal(proposer);

    }

    function _propose(
        address proposer,
        uint256 snapshot,
        uint256 duration,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string[] calldata signatures,
        string calldata description
    ) internal virtual returns (uint256 proposalId) {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();

        if (targets.length == 0) revert MissingArrayItems();
        if (
            targets.length != values.length ||
            targets.length != calldatas.length ||
            targets.length != signatures.length
        ) revert MismatchingArrayLengths();

        // Verify the human-readable function signatures
        SelectorChecker.verifySelectors(calldatas, signatures);

        // Increment proposal counter
        uint256 newProposalId = ++$._proposalCount;

        ProposalCore storage proposal = $._proposals[newProposalId];
        proposal.actionsHash = hashProposalActions(newProposalId, targets, values, calldatas);
        proposal.proposer = proposer;
        proposal.voteStart = snapshot.toUint48();
        proposal.voteDuration = duration.toUint32();

        emit ProposalCreated(
            newProposalId,
            proposer,
            targets,
            values,
            signatures,
            calldatas,
            snapshot,
            snapshot + duration,
            description
        );

        return newProposalId;
    }

    /**
     * @dev Function to queue a proposal to the timelock.
     */
    function queue(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) public virtual override returns (uint256) {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();

        if (state(proposalId) != ProposalState.Succeeded) revert ProposalUnsuccessful();
        if(
            $._proposals[proposalId].actionsHash != hashProposalActions(proposalId, targets, values, calldatas)
        ) revert InvalidActionsForProposal();

        ITimelockAvatar _executor = executor();
        (address to, uint256 value, bytes memory data) = MultiSendEncoder.encodeMultiSendCalldata(
            address(_executor),
            targets,
            values,
            calldatas
        );

        (,bytes memory returnData) = _executor.execTransactionFromModuleReturnData(
            to,
            value,
            data,
            Enum.Operation.Call
        );

        (uint256 opNonce,,uint256 eta) = abi.decode(returnData, (uint256, bytes32, uint256));
        $._opNonces[proposalId] = opNonce;
        $._proposals[proposalId].etaSeconds = eta.toUint48();

        emit ProposalQueued(proposalId, eta);

        return proposalId;
    }


    /**
     * @dev See {IGovernor-execute}.
     */
    function execute(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) public virtual override returns (uint256) {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();

        ProposalState status = state(proposalId);
        if (
            status != ProposalState.Queued
        ) revert ProposalUnsuccessful();
        // NOTE: We don't check the actionsHash here because the TimelockAvatar's opHash will be checked
        $._proposals[proposalId].executed = true;

        // before execute: queue any operations on self
        DoubleEndedQueue.Bytes32Deque storage governanceCall = _getGovernanceCallQueue();
        for (uint256 i = 0; i < targets.length; ++i) {
            if (targets[i] == address(this)) {
                governanceCall.pushBack(keccak256(calldatas[i]));
            }
        }

        _executeOperations(proposalId, targets, values, calldatas);

        // after execute: cleanup governance call queue
        if (!governanceCall.empty()) {
            governanceCall.clear();
        }

        emit ProposalExecuted(proposalId);

        return proposalId;
    }

    /**
     * @dev Overridden execute function that run the already queued proposal through the timelock.
     */
    function _executeOperations(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) internal virtual {
        ITimelockAvatar _executor = executor();
        (address to, uint256 value, bytes memory data) = MultiSendEncoder.encodeMultiSendCalldata(
            address(_executor),
            targets,
            values,
            calldatas
        );

        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        _executor.executeOperation($._opNonces[proposalId], to, value, data, Enum.Operation.Call);
    }

    function cancel(
        uint256 proposalId
    ) public virtual override returns (uint256) {
        // Only allow cancellation if the sender is canceler role, or if the proposer cancels before voting starts
        if (!(
            _hasRole(CANCELER_ROLE, msg.sender) || (
                msg.sender == proposalProposer(proposalId) &&
                state(proposalId) == ProposalState.Pending
            )
        )) revert UnauthorizedToCancelProposal();

        return _cancel(proposalId);
    }

    /**
     * @dev Internal cancel mechanism: locks up the proposal timer, preventing it from being re-submitted. Marks it as
     * canceled to allow distinguishing it from executed proposals.
     *
     * Emits a {IGovernor-ProposalCanceled} event.
     */
    // This function can reenter through the external call to the timelock, but we assume the timelock is trusted and
    // well behaved (according to TimelockController) and this will not happen.
    // slither-disable-next-line reentrancy-no-eth
    function _cancel(
        uint256 proposalId
    ) internal virtual returns (uint256) {
        ProposalState status = state(proposalId);

        if (
            status == ProposalState.Canceled || status == ProposalState.Expired || status == ProposalState.Executed
        ) revert ProposalAlreadyFinished();

        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        $._proposals[proposalId].canceled = true;

        // Cancel the op if it exists (will revert if it cannot be cancelled)
        uint256 opNonce = $._opNonces[proposalId];
        if (opNonce != 0) {
            executor().cancelOperation(opNonce);
        }

        emit ProposalCanceled(proposalId);

        return proposalId;
    }

    /// @inheritdoc IGovernorBase
    function getVotes(address account, uint256 timepoint) public view virtual override returns (uint256) {
        return _getVotes(account, timepoint, _defaultParams());
    }

    /// @inheritdoc IGovernorBase
    function getVotesWithParams(
        address account,
        uint256 timepoint,
        bytes memory params
    ) public view virtual override returns (uint256) {
        return _getVotes(account, timepoint, params);
    }

    /**
     * @dev Get the voting weight of `account` at a specific `timepoint`, for a vote as described by `params`.
     */
    function _getVotes(
        address account,
        uint256 timepoint,
        bytes memory params
    ) internal view virtual returns (uint256 voteWeight) {
        voteWeight = _getVotes(token(), account, timepoint, params);
    }

    function _getVotes(
        IGovernorToken _token,
        address account,
        uint256 timepoint,
        bytes memory /*params*/
    ) internal view virtual returns (uint256 voteWeight) {
        voteWeight = _token.getPastVotes(account, timepoint);
    }

    /// @inheritdoc IGovernorBase
    function castVote(uint256 proposalId, uint8 support) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, "");
    }

    /// @inheritdoc IGovernorBase
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason);
    }

    /// @inheritdoc IGovernorBase
    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason, params);
    }

    /// @inheritdoc IGovernorBase
    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256) {
        address voter = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support))),
            v,
            r,
            s
        );
        return _castVote(proposalId, voter, support, "");
    }

    /// @inheritdoc IGovernorBase
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256) {
        address voter = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EXTENDED_BALLOT_TYPEHASH,
                        proposalId,
                        support,
                        keccak256(bytes(reason)),
                        keccak256(params)
                    )
                )
            ),
            v,
            r,
            s
        );

        return _castVote(proposalId, voter, support, reason, params);
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function. Uses the _defaultParams().
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason
    ) internal virtual returns (uint256) {
        return _castVote(proposalId, account, support, reason, _defaultParams());
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function.
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual returns (uint256) {
        if (state(proposalId) != ProposalState.Active) revert ProposalVotingInactive();

        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        ProposalCore storage proposal = $._proposals[proposalId];

        uint256 weight = _getVotes(account, proposal.voteStart, params);
        _countVote(proposalId, account, support, weight, params);

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }

        return weight;
    }

    /**
     * @dev Default additional encoded parameters used by castVote methods that don't include them
     *
     * Note: Should be overridden by specific implementations to use an appropriate value, the
     * meaning of the additional params, in the context of that implementation
     */
    function _defaultParams() internal view virtual returns (bytes memory) {
        return "";
    }

    function votingDelay() public view virtual returns (uint256);

    function votingPeriod() public view virtual returns (uint256);

    /// @dev Get both values at once to optimize gas
    function _getVotingDelayAndPeriod() internal view virtual returns (uint256 _votingDelay, uint256 _votingPeriod);

    function quorum(uint256 timepoint) public view virtual returns (uint256);

    /**
     * @dev Governance-only function to add a role to the specified account.
     */
    function grantRole(bytes32 role, address account) public virtual onlyGovernance {
        _grantRole(role, account);
    }

    /**
     * @dev Governance-only function to add a role to the specified account that expires at the specified timestamp.
     */
    function grantRole(bytes32 role, address account, uint256 expiresAt) public virtual onlyGovernance {
        _grantRole(role, account, expiresAt);
    }

    /**
     * @dev Batch method for granting roles.
     */
    function grantRolesBatch(
        bytes32[] calldata roles,
        address[] calldata accounts,
        uint256[] calldata expiresAts
    ) public virtual onlyGovernance {
        _grantRolesBatch(roles, accounts, expiresAts);
    }

    /**
     * @dev Governance-only function to revoke a role from the specified account.
     */
    function revokeRole(bytes32 role, address account) public virtual onlyGovernance {
        _revokeRole(role, account);
    }

    /**
     * @dev Batch method for revoking roles.
     */
    function revokeRolesBatch(
        bytes32[] calldata roles,
        address[] calldata accounts
    ) public virtual onlyGovernance {
        _revokeRolesBatch(roles, accounts);
    }

    /**
     * @dev Amount of votes already cast passes the threshold limit.
     */
    function _quorumReached(uint256 proposalId) internal view virtual returns (bool);

    /**
     * @dev Is the proposal successful or not.
     */
    function _voteSucceeded(uint256 proposalId) internal view virtual returns (bool);

    /**
     * @dev The vote spread (the difference between For and Against counts)
     */
    function _voteMargin(uint256 proposalId) internal view virtual returns (uint256);

    /**
     * @dev Register a vote for `proposalId` by `account` with a given `support`, voting `weight` and voting `params`.
     *
     * Note: Support is generic and can represent various things depending on the voting system used.
     */
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory params
    ) internal virtual;

    /**
     * @dev Relays a transaction or function call to an arbitrary target. In cases where the governance _executor
     * is some contract other than the governor itself, like when using a timelock, this function can be invoked
     * in a governance proposal to recover tokens or Ether that was sent to the governor contract by mistake.
     * Note that if the _executor is simply the governor itself, use of `relay` is redundant.
     */
    function relay(address target, uint256 value, bytes calldata data) external payable virtual onlyGovernance {
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        Address.verifyCallResult(success, returndata);
    }

}
