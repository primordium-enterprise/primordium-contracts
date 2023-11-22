// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (Governor.sol)

pragma solidity ^0.8.20;

import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {IGovernorBase} from "../interfaces/IGovernorBase.sol";
import {IGovernorToken} from "../interfaces/IGovernorToken.sol";
import {Roles} from "contracts/utils/Roles.sol";
import {TimelockAvatarControlled} from "./TimelockAvatarControlled.sol";
import {ITimelockAvatar} from "contracts/executor/interfaces/ITimelockAvatar.sol";
import {Enum} from "contracts/common/Enum.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
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
    NoncesUpgradeable,
    IGovernorBase,
    Roles
{
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using SafeCast for uint256;
    using BasisPoints for uint256;

    struct ProposalCore {
        address proposer; // 20 bytes
        uint48 voteStart; // 6 bytes
        uint32 voteDuration; // 4 bytes
        bool executed; // 1 byte
        bool canceled; // 1 byte
    }

    struct VotesManagement {
        IGovernorToken _token; // 20 bytes
        bool _isFounded; // 1 byte
        uint40 _governanceCanBeginAt; // 5 bytes
        uint16 _governanceThresholdBps; // 2 bytes
    }

    bytes32 private constant ALL_PROPOSAL_STATES_BITMAP = bytes32((2 ** (uint8(type(ProposalState).max) + 1)) - 1);

    bytes32 public immutable BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,uint8 support,address voter,uint256 nonce)");
    bytes32 public immutable EXTENDED_BALLOT_TYPEHASH =
        keccak256(
            "ExtendedBallot(uint256 proposalId,uint8 support,address voter,uint256 nonce,string reason,bytes params)"
        );

    bytes32 public immutable PROPOSER_ROLE = keccak256("PROPOSER");
    bytes32 public immutable CANCELER_ROLE = keccak256("CANCELER");

    /// @custom:storage-location erc7201:GovernorBase.Storage
    struct GovernorBaseStorage {
        uint256 _proposalCount;

        // Tracking core proposal data
        mapping(uint256 => ProposalCore) _proposals;

        // Tracking hashes of each proposal's actions
        mapping(uint256 => bytes32) _proposalActionsHashes;

        // Tracking queued operations on the TimelockAvatar
        mapping(uint256 => uint256) _proposalOpNonces;

        // Track the token address and other voting management
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
    function clock() public view virtual override returns (uint48) {
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
    function proposalCount() public view virtual returns (uint256 count) {
        count = _getGovernorBaseStorage()._proposalCount;
    }

    /**
     * @dev Defaults to 10e18, which is equivalent to 1 ERC20 vote token with a decimals() value of 18.
     */
    function proposalThreshold() public view virtual returns (uint256) {
        return 10e18;
    }

    /// @inheritdoc IGovernorBase
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

        uint256 opNonce = $._proposalOpNonces[proposalId];
        if (opNonce == 0) {
            uint256 grace = proposalGracePeriod();
            if (deadline + grace >= currentTimepoint) {
                return ProposalState.Expired;
            }
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
    function proposalSnapshot(uint256 proposalId) public view virtual override returns (uint256 snapshot) {
        snapshot = _getGovernorBaseStorage()._proposals[proposalId].voteStart;
    }

    /// @inheritdoc IGovernorBase
    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256 deadline) {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        deadline = $._proposals[proposalId].voteStart + $._proposals[proposalId].voteDuration;
    }

    /// @inheritdoc IGovernorBase
    function proposalActionsHash(uint256 proposalId) public view virtual override returns (bytes32 actionsHash) {
        actionsHash = _getGovernorBaseStorage()._proposalActionsHashes[proposalId];
    }

    /// @inheritdoc IGovernorBase
    function proposalProposer(uint256 proposalId) public view virtual override returns (address proposer) {
        proposer = _getGovernorBaseStorage()._proposals[proposalId].proposer;
    }

    /// @inheritdoc IGovernorBase
    function proposalEta(uint256 proposalId) public view virtual override returns (uint256 eta) {
        uint256 opNonce = _getGovernorBaseStorage()._proposalOpNonces[proposalId];
        if (opNonce == 0) {
            return eta;
        }
        eta = executor().getOperationExecutableAt(opNonce);
    }

    /// @inheritdoc IGovernorBase
    function proposalOpNonce(uint256 proposalId) public view virtual override returns (uint256 opNonce) {
        opNonce = _getGovernorBaseStorage()._proposalOpNonces[proposalId];
    }

    /**
     * @dev See {IGovernor-hashProposaActions}.
     *
     * The actionsHash is produced by hashing the ABI encoded `targets` array, the `values` array, and the `calldatas`
     * array. This can be reproduced from the proposal data which is part of the {ProposalCreated} event.
     *
     * Note that the chainId and the governor address are not part of the proposal id computation. Consequently, the
     * same proposal (with same operation and same description) will have the same id if submitted on multiple governors
     * across multiple networks. This also means that in order to execute the same operation twice (on the same
     * governor) the proposer will have to change the description in order to avoid proposal id conflicts.
     */
    function hashProposalActions(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) public pure virtual override returns (bytes32) {
        return keccak256(abi.encode(targets, values, calldatas));
    }

    /// @inheritdoc IGovernorBase
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string[] calldata signatures,
        string calldata description
    ) public virtual override returns (uint256) {

        address proposer = _msgSender();

        (, uint256 currentClock) = _authorizeProposal(proposer, targets, values, calldatas, description);

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
     * @dev Authorizes whether a proposal can be submitted by the provided proposer. Also includes front-running
     * protection as used in OpenZeppelin 5.0.0's {Governor.sol} contract.
     *
     * @notice This function checks whether the Governor has been founded, and restricts proposals to only initializing
     * governance if the Governor is not yet founded.
     *
     * @return _token The IGovernorToken token read from storage for internal gas optimization
     * @return currentClock The current clock() value for the token for internal gas optimization (avoid re-calling)
     */
    function _authorizeProposal(
        address proposer,
        address[] calldata targets,
        uint256[] calldata /*values*/,
        bytes[] calldata calldatas,
        string calldata description
    ) internal view virtual returns (IGovernorToken _token, uint256 currentClock) {

        // check description restriction
        if (!_isValidDescriptionForProposer(proposer, description)) {
            revert GovernorRestrictedProposer(proposer);
        }

        // check founded status
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
        $._proposalActionsHashes[newProposalId] = hashProposalActions(targets, values, calldatas);
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

        _validateStateBitmap(proposalId, _encodeStateBitmap(ProposalState.Succeeded));

        if(
            $._proposalActionsHashes[proposalId] != hashProposalActions(targets, values, calldatas)
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
        $._proposalOpNonces[proposalId] = opNonce;

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

        _validateStateBitmap(proposalId, _encodeStateBitmap(ProposalState.Queued));

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
        _executor.executeOperation($._proposalOpNonces[proposalId], to, value, data, Enum.Operation.Call);
    }

    function cancel(
        uint256 proposalId
    ) public virtual override returns (uint256) {
        // Only allow cancellation if the sender is CANCELER_ROLE, or if the proposer cancels before voting starts
        if (!_hasRole(CANCELER_ROLE, msg.sender)) {
            if (msg.sender != proposalProposer(proposalId)) {
                revert UnauthorizedToCancelProposal();
            }
            _validateStateBitmap(proposalId, _encodeStateBitmap(ProposalState.Pending));
        }

        return _cancel(proposalId);
    }

    /**
     * @dev Internal cancel mechanism: locks up the proposal timer, preventing it from being re-submitted. Marks it as
     * canceled to allow distinguishing it from executed proposals.
     *
     * Emits a {IGovernor-ProposalCanceled} event.
     */
    function _cancel(
        uint256 proposalId
    ) internal virtual returns (uint256) {

        // Can cancel in any state other than Canceled, Expired, or Executed.
        _validateStateBitmap(
            proposalId,
            ALL_PROPOSAL_STATES_BITMAP ^
                _encodeStateBitmap(ProposalState.Canceled) ^
                _encodeStateBitmap(ProposalState.Expired) ^
                _encodeStateBitmap(ProposalState.Executed)
        );

        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        $._proposals[proposalId].canceled = true;

        // Cancel the op if it exists (will revert if it cannot be cancelled)
        uint256 opNonce = $._proposalOpNonces[proposalId];
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
        address voter,
        bytes memory signature
    ) public virtual override returns (uint256) {
        bool valid = SignatureChecker.isValidSignatureNow(
            voter,
            _hashTypedDataV4(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support, voter, _useNonce(voter)))),
            signature
        );

        if (!valid) {
            revert GovernorInvalidSignature(voter);
        }

        return _castVote(proposalId, voter, support, "");
    }

    /// @inheritdoc IGovernorBase
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        address voter,
        string calldata reason,
        bytes memory params,
        bytes memory signature
    ) public virtual override returns (uint256) {
        bool valid = SignatureChecker.isValidSignatureNow(
            voter,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EXTENDED_BALLOT_TYPEHASH,
                        proposalId,
                        support,
                        voter,
                        _useNonce(voter),
                        keccak256(bytes(reason)),
                        keccak256(params)
                    )
                )
            ),
            signature
        );

        if (!valid) {
            revert GovernorInvalidSignature(voter);
        }

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
    ) internal virtual returns (uint256 weight) {
        _validateStateBitmap(proposalId, _encodeStateBitmap(ProposalState.Active));

        ProposalCore storage proposal = _getGovernorBaseStorage()._proposals[proposalId];

        weight = _getVotes(account, proposal.voteStart, params);
        _countVote(proposalId, account, support, weight, params);

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }
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

    /// @inheritdoc IGovernorBase
    function votingDelay() public view virtual returns (uint256);

    /// @inheritdoc IGovernorBase
    function votingPeriod() public view virtual returns (uint256);

    /// @inheritdoc IGovernorBase
    function proposalGracePeriod() public view virtual returns (uint256);

    /// @inheritdoc IGovernorBase
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

    /// @dev Get both values at once to optimize gas where applicable
    function _getVotingDelayAndPeriod() internal view virtual returns (uint256 _votingDelay, uint256 _votingPeriod);

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
     * @dev Encodes a `ProposalState` into a `bytes32` representation where each bit enabled corresponds to
     * the underlying position in the `ProposalState` enum. For example:
     *
     * 0x000...10000
     *   ^^^^^^------ ...
     *         ^----- Succeeded
     *          ^---- Defeated
     *           ^--- Canceled
     *            ^-- Active
     *             ^- Pending
     */
    function _encodeStateBitmap(ProposalState proposalState) internal pure returns (bytes32) {
        return bytes32(1 << uint8(proposalState));
    }

    /**
     * @dev Check that the current state of a proposal matches the requirements described by the `allowedStates` bitmap.
     * This bitmap should be built using `_encodeStateBitmap`.
     *
     * If requirements are not met, reverts with a {GovernorUnexpectedProposalState} error.
     */
    function _validateStateBitmap(uint256 proposalId, bytes32 allowedStates) private view returns (ProposalState) {
        ProposalState currentState = state(proposalId);
        if (_encodeStateBitmap(currentState) & allowedStates == bytes32(0)) {
            revert GovernorUnexpectedProposalState(proposalId, currentState, allowedStates);
        }
        return currentState;
    }

    /**
     * @dev Check if the proposer is authorized to submit a proposal with the given description.
     *
     * If the proposal description ends with `#proposer=0x???`, where `0x???` is an address written as a hex string
     * (case insensitive), then the submission of this proposal will only be authorized to said address.
     *
     * This is used for frontrunning protection. By adding this pattern at the end of their proposal, one can ensure
     * that no other address can submit the same proposal. An attacker would have to either remove or change that part,
     * which would result in a different proposal id.
     *
     * If the description does not match this pattern, it is unrestricted and anyone can submit it. This includes:
     * - If the `0x???` part is not a valid hex string.
     * - If the `0x???` part is a valid hex string, but does not contain exactly 40 hex digits.
     * - If it ends with the expected suffix followed by newlines or other whitespace.
     * - If it ends with some other similar suffix, e.g. `#other=abc`.
     * - If it does not end with any such suffix.
     */
    function _isValidDescriptionForProposer(
        address proposer,
        string calldata description
    ) internal view virtual returns (bool) {
        uint256 len;
        assembly {
            len := description.length
        }

        // Length is too short to contain a valid proposer suffix
        if (len < 52) {
            return true;
        }

        // Extract what would be the `#proposer=0x` marker beginning the suffix
        bytes12 marker;
        assembly {
            // - Start of the string contents in calldata = description.offset
            // - First character of the marker = len - 52
            //   - Length of "#proposer=0x0000000000000000000000000000000000000000" = 52
            // - We read the memory word starting at the first character of the marker:
            //   - (description.offset) + (len - 52)
            // - Note: Solidity will ignore anything past the first 12 bytes
            marker := calldataload(add(description.offset, sub(len, 52)))
        }

        // If the marker is not found, there is no proposer suffix to check
        if (marker != bytes12("#proposer=0x")) {
            return true;
        }

        // Parse the 40 characters following the marker as uint160
        uint160 recovered = 0;
        for (uint256 i = len - 40; i < len;) {
            (bool isHex, uint8 value) = _tryHexToUint(bytes(description)[i]);
            // If any of the characters is not a hex digit, ignore the suffix entirely
            if (!isHex) {
                return true;
            }
            recovered = (recovered << 4) | value;
            unchecked { ++i; }
        }

        return recovered == uint160(proposer);
    }

    /**
     * @dev Try to parse a character from a string as a hex value. Returns `(true, value)` if the char is in
     * `[0-9a-fA-F]` and `(false, 0)` otherwise. Value is guaranteed to be in the range `0 <= value < 16`
     */
    function _tryHexToUint(bytes1 char) private pure returns (bool, uint8) {
        uint8 c = uint8(char);
        unchecked {
            // Case 0-9
            if (47 < c && c < 58) {
                return (true, c - 48);
            }
            // Case A-F
            else if (64 < c && c < 71) {
                return (true, c - 55);
            }
            // Case a-f
            else if (96 < c && c < 103) {
                return (true, c - 87);
            }
            // Else: not a hex char
            else {
                return (false, 0);
            }
        }
    }

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
