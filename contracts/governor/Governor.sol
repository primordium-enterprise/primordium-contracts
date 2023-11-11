// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v4.8.0) (Governor.sol)

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "../token/extensions/VotesProvisioner.sol";
import "../executor/Executor.sol";
import "./IGovernor.sol";
import "../utils/TimelockAvatarControlled.sol";
import "../utils/Roles.sol";
import "contracts/libraries/MultiSendEncoder.sol";

/**
 * @dev Core of the governance system, designed to be extended though various modules.
 *
 * This contract is abstract and requires several function to be implemented in various modules:
 *
 * - A counting module must implement {quorum}, {_quorumReached}, {_voteSucceeded} and {_countVote}
 * - A voting module must implement {_getVotes}
 * - Additionally, {proposalThreshold}, {votingDelay} and {votingPeriod} must also be implemented (see the
 * GovernorSettings extension)
 *
 * _Available since v4.3._
 */
abstract contract Governor is ContextUpgradeable, ERC165, EIP712Upgradeable, TimelockAvatarControlled, IGovernor, Roles {

    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using SafeCast for uint256;

    struct ProposalCore {
        bytes32 actionsHash;
        address proposer;
        uint48 voteStart;
        uint32 voteDuration;
        bool executed;
        bool canceled;
        uint48 etaSeconds;
    }

    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");
    bytes32 public constant EXTENDED_BALLOT_TYPEHASH =
        keccak256("ExtendedBallot(uint256 proposalId,uint8 support,string reason,bytes params)");

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER");
    bytes32 public constant CANCELER_ROLE = keccak256("CANCELER");

    // Proposals counter
    uint256 public proposalCount;

    // Tracking queued operations on the _timelockAvatar
    mapping(uint256 => uint256) private _opNonces;

    mapping(uint256 => ProposalCore) private _proposals;

    // This queue keeps track of the governor operating on itself. Calls to functions protected by the
    // {onlyGovernance} modifier needs to be whitelisted in this queue. Whitelisting is set in {_beforeExecute},
    // consumed by the {onlyGovernance} modifier and eventually reset in {_afterExecute}. This ensures that the
    // execution of {onlyGovernance} protected calls can only be achieved through successful proposals.
    DoubleEndedQueue.Bytes32Deque private _governanceCall;

    address internal _token;
    bool internal _isFounding;

    /**
     * @dev Restricts a function so it can only be executed through governance proposals. For example, governance
     * parameter setters in {GovernorSettings} are protected using this modifier.
     */
    modifier onlyGovernance() {
        _onlyGovernance();
        _;
    }

    function _onlyGovernance() private {
        address timelock = address(_timelockAvatar);
        if (msg.sender != timelock) revert OnlyGovernance();
        bytes32 msgDataHash = keccak256(_msgData());
        // loop until popping the expected operation - throw if deque is empty (operation not authorized)
        while (_governanceCall.popFront() != msgDataHash) {}
    }

    function __Governor_init(
        address timelockAvatar_,
        address token_
    ) internal virtual onlyInitializing {
        __EIP712_init(name(), version());
        __TimelockAvatarControlled_init(timelockAvatar_);
        _token = token_;
        // Token clock must match
        if (ERC20Checkpoints(token_).clock() != clock()) revert GovernorClockMustMatchTokenClock();
        // Set founding bool (for checking proposals)
        _isFounding = VotesProvisioner(token_).provisionMode() == IVotesProvisioner.ProvisionMode.Founding;
    }

    function name() public view virtual override returns (string memory) {
        return "__Governor";
    }

    function version() public view virtual override returns (string memory) {
        return "1";
    }

    /**
     * @dev Clock (as specified in EIP-6372) defaults to block number. Should be overridden to match token if different.
     */
    function clock() public view virtual override returns (uint48) {
        return SafeCast.toUint48(block.number);
    }

    /**
     * @dev Machine-readable description of the clock as specified in EIP-6372.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    /**
     * @notice Returns the address of the token contract used for keeping a tally of votes
     */
    function token() public view returns (address) {
        return _token;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165) returns (bool) {
        // In addition to the current interfaceId, also support previous version of the interfaceId that did not
        // include the castVoteWithReasonAndParams() function as standard
        return
            interfaceId == type(IGovernor).interfaceId ||
            // Previous interface for backwards compatibility
            interfaceId == (type(IGovernor).interfaceId ^ type(IERC6372).interfaceId ^ this.cancel.selector) ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev A helpful extension for initializing the Governor when deploying the first version
     *
     * 1. Deploy Executor (deployer address as the owner)
     * 2. Deploy Governor with _executor address set to address(0)
     * 3. Call initialize on Governor from deployer address (to set the _executor and complete the ownership transfer)
     */
    // function initialize(Executor newExecutor) public virtual {
    //     initializeExecutor(newExecutor);
    //     _executor.acceptOwnership();
    // }

    /**
     * @dev Public endpoint to update the underlying timelock instance. Restricted to the timelock itself, so updates
     * must be proposed, scheduled, and executed through governance proposals.
     *
     * CAUTION: It is not recommended to change the timelock while there are other queued governance proposals.
     */
    function updateTimelockAvatar(address newExecutor) public virtual onlyGovernance {
        _updateTimelockAvatar(newExecutor);
    }

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
     * @dev See {IGovernor-state}.
     */
    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        // Single SLOAD
        ProposalCore storage proposal = _proposals[proposalId];
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

        uint256 opNonce = _opNonces[proposalId];
        if (opNonce == 0) {
            return ProposalState.Succeeded;
        }

        TimelockAvatar.OperationStatus opStatus = _timelockAvatar.getOperationStatus(opNonce);
        if (opStatus == TimelockAvatar.OperationStatus.Done) {
            return ProposalState.Executed;
        }
        if (opStatus == TimelockAvatar.OperationStatus.Expired) {
            return ProposalState.Expired;
        }

        return ProposalState.Queued;
    }

    /**
     * @dev See {IGovernor-proposalSnapshot}.
     */
    function proposalSnapshot(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].voteStart;
    }

    /**
     * @dev See {IGovernor-proposalDeadline}.
     */
    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].voteStart + _proposals[proposalId].voteDuration;
    }

    function proposalActionsHash(uint256 proposalId) public view virtual override returns (bytes32) {
        return _proposals[proposalId].actionsHash;
    }

    /**
     * @dev Address of the proposer
     */
    function _proposalProposer(uint256 proposalId) internal view virtual returns (address) {
        return _proposals[proposalId].proposer;
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
     * @dev Get the voting weight of `account` at a specific `timepoint`, for a vote as described by `params`.
     */
    function _getVotes(address account, uint256 timepoint, bytes memory params) internal view virtual returns (uint256);

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
     * @dev Default additional encoded parameters used by castVote methods that don't include them
     *
     * Note: Should be overridden by specific implementations to use an appropriate value, the
     * meaning of the additional params, in the context of that implementation
     */
    function _defaultParams() internal view virtual returns (bytes memory) {
        return "";
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
        uint256 currentTimepoint = clock();

        if (
            getVotes(proposer, currentTimepoint - 1) < proposalThreshold() &&
            !_hasRole(PROPOSER_ROLE, proposer)
        ) revert UnauthorizedToSubmitProposal();

        if (targets.length == 0) revert MissingArrayItems();
        if (
            targets.length != values.length ||
            targets.length != calldatas.length ||
            targets.length != signatures.length
        ) revert MismatchingArrayLengths();

        // If the DAO is in founding mode, then check if governance is even allowed
        if (_isFounding) {
            address token_ = _token;
            (bool isGovernanceAllowed, IVotesProvisioner.ProvisionMode provisionMode) =
                VotesProvisioner(token_).isGovernanceAllowed();
            // If no longer in founding mode, we can reset the _isFounding flag and move on
            if (provisionMode > IVotesProvisioner.ProvisionMode.Founding) {
                delete _isFounding;
            } else {
                if (!isGovernanceAllowed) revert NotReadyForGovernance();
                if (
                    targets.length != 1 || // Only allow a single action until we exit founding mode
                    targets[0] != token_ || // And the action must be to upgrade the token from founding mode
                    bytes4(calldatas[0]) != VotesProvisioner.setProvisionMode.selector // So the selector must match
                ) revert InvalidFoundingModeActions();
            }
        }

        // Verify the human-readable function signatures
        // Fail if calldata is included BUT the function signature doesn't match the calldata function identifier
        for (uint256 i = 0; i < signatures.length;) {
            if (calldatas[i].length > 0) {
                if (
                    bytes4(calldatas[i]) != bytes4(keccak256(bytes(signatures[i])))
                ) revert InvalidActionSignature(i);
            }
            unchecked { ++i; }
        }

        // Increment proposal counter
        uint256 newProposalId = ++proposalCount;

        // Generate voting periods
        uint256 snapshot = currentTimepoint + votingDelay();
        uint256 duration = votingPeriod();

        ProposalCore storage proposal = _proposals[newProposalId];
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

        if (state(proposalId) != ProposalState.Succeeded) revert ProposalUnsuccessful();
        if(
            _proposals[proposalId].actionsHash != hashProposalActions(proposalId, targets, values, calldatas)
        ) revert InvalidActionsForProposal();

        (address to, uint256 value, bytes memory data) = MultiSendEncoder.encodeMultiSendCalldata(
            address(_timelockAvatar),
            targets,
            values,
            calldatas
        );

        (,bytes memory returnData) = _timelockAvatar.execTransactionFromModuleReturnData(
            to,
            value,
            data,
            Enum.Operation.Call
        );

        (uint256 opNonce,,uint256 eta) = abi.decode(returnData, (uint256, bytes32, uint256));
        _opNonces[proposalId] = opNonce;
        _proposals[proposalId].etaSeconds = eta.toUint48();

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

        ProposalState status = state(proposalId);
        if (
            status != ProposalState.Succeeded && status != ProposalState.Queued
        ) revert ProposalUnsuccessful();
        // NOTE: We don't check the actionsHash here because the TimelockAvatar's opHash will be checked
        _proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);

        _beforeExecute(proposalId, targets, values, calldatas);
        _execute(proposalId, targets, values, calldatas);
        _afterExecute(proposalId, targets, values, calldatas);

        return proposalId;
    }

    function cancel(
        uint256 proposalId
    ) public virtual override returns (uint256) {
        // Only allow cancellation if the sender is canceler role, or if the proposer cancels before voting starts
        if (!(
            _hasRole(CANCELER_ROLE, msg.sender) || (
                msg.sender == _proposals[proposalId].proposer &&
                state(proposalId) == ProposalState.Pending
            )
        )) revert UnauthorizedToCancelProposal();

        return _cancel(proposalId);
    }

    /**
     * @dev Overridden execute function that run the already queued proposal through the timelock.
     */
    function _execute(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) internal virtual {
        (address to, uint256 value, bytes memory data) = MultiSendEncoder.encodeMultiSendCalldata(
            address(_timelockAvatar),
            targets,
            values,
            calldatas
        );
        _timelockAvatar.executeOperation(_opNonces[proposalId], to, value, data, Enum.Operation.Call);
    }

    /**
     * @dev Hook before execution is triggered.
     */
    function _beforeExecute(
        uint256 /* proposalId */,
        address[] calldata targets,
        uint256[] calldata /* values */,
        bytes[] calldata calldatas
    ) internal virtual {
        // Queue any operations on self
        for (uint256 i = 0; i < targets.length; ++i) {
            if (targets[i] == address(this)) {
                _governanceCall.pushBack(keccak256(calldatas[i]));
            }
        }
    }

    /**
     * @dev Hook after execution is triggered.
     */
    function _afterExecute(
        uint256 /* proposalId */,
        address[] memory /* targets */,
        uint256[] memory /* values */,
        bytes[] memory /* calldatas */
    ) internal virtual {
        // Clear the self operation queue
        if (!_governanceCall.empty()) {
            _governanceCall.clear();
        }
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
        _proposals[proposalId].canceled = true;

        // Cancel the op if it exists (will revert if it cannot be cancelled)
        uint256 opNonce = _opNonces[proposalId];
        if (opNonce != 0) {
            _timelockAvatar.cancelOperation(opNonce);
        }

        emit ProposalCanceled(proposalId);

        return proposalId;
    }

    /**
     * @dev Public accessor to check the eta of a queued proposal
     */
    function proposalEta(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].etaSeconds;
    }

    /**
     * @dev See {IGovernor-getVotes}.
     */
    function getVotes(address account, uint256 timepoint) public view virtual override returns (uint256) {
        return _getVotes(account, timepoint, _defaultParams());
    }

    /**
     * @dev See {IGovernor-getVotesWithParams}.
     */
    function getVotesWithParams(
        address account,
        uint256 timepoint,
        bytes memory params
    ) public view virtual override returns (uint256) {
        return _getVotes(account, timepoint, params);
    }

    /**
     * @dev See {IGovernor-castVote}.
     */
    function castVote(uint256 proposalId, uint8 support) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, "");
    }

    /**
     * @dev See {IGovernor-castVoteWithReason}.
     */
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason);
    }

    /**
     * @dev See {IGovernor-castVoteWithReasonAndParams}.
     */
    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason, params);
    }

    /**
     * @dev See {IGovernor-castVoteBySig}.
     */
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

    /**
     * @dev See {IGovernor-castVoteWithReasonAndParamsBySig}.
     */
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
        ProposalCore storage proposal = _proposals[proposalId];
        if (state(proposalId) != ProposalState.Active) revert ProposalVotingInactive();

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
     * @dev Relays a transaction or function call to an arbitrary target. In cases where the governance _timelockAvatar
     * is some contract other than the governor itself, like when using a timelock, this function can be invoked
     * in a governance proposal to recover tokens or Ether that was sent to the governor contract by mistake.
     * Note that if the _timelockAvatar is simply the governor itself, use of `relay` is redundant.
     */
    function relay(address target, uint256 value, bytes calldata data) external payable virtual onlyGovernance {
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        Address.verifyCallResult(success, returndata);
    }

}
