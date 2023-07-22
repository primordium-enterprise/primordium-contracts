// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v4.8.0) (governance/Governor.sol)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "../token/extensions/VotesProvisioner.sol";
import "../executor/Executor.sol";
import "./IGovernor.sol";
import "../utils/ExecutorControlled.sol";

/**
 * @dev Core of the governance system, designed to be extended though various modules.
 *
 * This contract is abstract and requires several function to be implemented in various modules:
 *
 * - A counting module must implement {quorum}, {_quorumReached}, {_voteSucceeded} and {_countVote}
 * - A voting module must implement {_getVotes}
 * - Additionally, {votingPeriod} must also be implemented
 *
 * _Available since v4.3._
 */
abstract contract Governor is Context, ERC165, EIP712, ExecutorControlled, IGovernor {

    /**
     * @notice The minimum supply of vote tokens that must be in circulation before proposals to enter governance mode
     * can be submitted.
     */
    uint256 public immutable governanceThreshold;

    VotesProvisioner internal immutable _token;

    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using SafeCast for uint256;

    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");
    bytes32 public constant EXTENDED_BALLOT_TYPEHASH =
        keccak256("ExtendedBallot(uint256 proposalId,uint8 support,string reason,bytes params)");

    function name() public view virtual override returns (string memory) {
        return "__Governor";
    }

    function version() public view virtual override returns (string memory) {
        return "1";
    }

    // Proposals counter
    uint256 public proposalCount = 0;

    /**
     * @dev Public endpoint to update the underlying timelock instance. Restricted to the timelock itself, so updates
     * must be proposed, scheduled, and executed through governance proposals.
     *
     * CAUTION: It is not recommended to change the timelock while there are other queued governance proposals.
     */
    function updateExecutor(Executor newExecutor) public virtual onlyGovernance {
        _updateExecutor(newExecutor);
    }

    /**
     * @dev Public endpoint to transfer ownership of the Executor contract to a new Governor. Restricted to the timelock
     * itself, so updates must be proposed, scheduled, and executed through governance proposals.
     *
     * NOTE: This Governor can only transfer ownership if it is the current owner. The new owner must accept ownership.
     */
    function transferExecutorOwnership(address newOwner) public virtual onlyGovernance {
        _executor.transferOwnership(newOwner);
    }

    /**
     * @dev A helpful extension for initializing the Governor when deploying the first version
     *
     * 1. Deploy Executor (deployer address as the owner)
     * 2. Deploy Governor with _executor address set to address(0)
     * 3. Call initialize on Governor from deployer address (to set the _executor and complete the ownership transfer)
     */
    function initialize(Executor newExecutor) public virtual {
        initializeExecutor(newExecutor);
        _executor.acceptOwnership();
    }

    // Tracking queued operations on the _executor
    mapping(uint256 => bytes32) private _executorIds;

    // solhint-disable var-name-mixedcase
    struct ProposalCore {
        uint256 proposalId;
        uint256 actionsHash;
        // --- start retyped from Timers.BlockNumber at offset 0x00 ---
        uint64 voteStart;
        address proposer;
        bytes4 __gap_unused0;
        // --- start retyped from Timers.BlockNumber at offset 0x20 ---
        uint64 voteEnd;
        bytes24 __gap_unused1;
        // --- Remaining fields starting at offset 0x40 ---------------
        bool executed;
        bool canceled;
    }
    // solhint-enable var-name-mixedcase

    /// @custom:oz-retyped-from mapping(uint256 => Governor.ProposalCore)
    mapping(uint256 => ProposalCore) private _proposals;

    // This queue keeps track of the governor operating on itself. Calls to functions protected by the
    // {onlyGovernance} modifier needs to be whitelisted in this queue. Whitelisting is set in {_beforeExecute},
    // consumed by the {onlyGovernance} modifier and eventually reset in {_afterExecute}. This ensures that the
    // execution of {onlyGovernance} protected calls can only be achieved through successful proposals.
    DoubleEndedQueue.Bytes32Deque private _governanceCall;

    /**
     * @dev Restricts a function so it can only be executed through governance proposals. For example, governance
     * parameter setters in {GovernorSettings} are protected using this modifier.
     *
     * The governance executing address may be different from the Governor's own address, for example it could be a
     * timelock. This can be customized by modules by overriding {_executor}. The _executor is only able to invoke these
     * functions during the execution of the governor's {execute} function, and not under any other circumstances. Thus,
     * for example, additional timelock proposers are not able to change governance parameters without going through the
     * governance protocol (since v4.6).
     */
    modifier onlyGovernance() {
        require(_msgSender() == address(_executor), "Governor: onlyGovernance");
        if (executor() != address(this)) {
            bytes32 msgDataHash = keccak256(_msgData());
            // loop until popping the expected operation - throw if deque is empty (operation not authorized)
            while (_governanceCall.popFront() != msgDataHash) {}
        }
        _;
    }

    /**
     * @dev Sets the value for {name} and {version}
     */
    constructor(
        Executor executor_,
        VotesProvisioner token_,
        uint256 governanceThreshold_
    ) EIP712(name(), version()) ExecutorControlled(executor_) {
        _token = token_;
        governanceThreshold = governanceThreshold_;
    }

    /**
     * @dev Clock (as specified in EIP-6372) is set to match the token's clock. Fallback to block numbers if the token
     * does not implement EIP-6372.
     */
    function clock() public view virtual override returns (uint48) {
        try _token.clock() returns (uint48 timepoint) {
            return timepoint;
        } catch {
            return SafeCast.toUint48(block.number);
        }
    }

    /**
     * @dev Machine-readable description of the clock as specified in EIP-6372.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        try _token.CLOCK_MODE() returns (string memory clockmode) {
            return clockmode;
        } catch {
            return "mode=blocknumber&from=default";
        }
    }

    /**
     * @notice Returns the address of the token contract used for keeping a tally of votes
     */
    function token() public view returns (address) {
        return address(_token);
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
     * @dev See {IGovernor-state}.
     */
    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        ProposalCore storage proposal = _proposals[proposalId];

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        uint256 snapshot = proposalSnapshot(proposalId);

        if (snapshot == 0) {
            revert("Governor: unknown proposal id");
        }

        uint256 currentTimepoint = clock();

        if (snapshot >= currentTimepoint) {
            return ProposalState.Pending;
        }

        uint256 deadline = proposalDeadline(proposalId);

        if (deadline >= currentTimepoint) {
            return ProposalState.Active;
        }

        if (_quorumReached(proposalId) && _voteSucceeded(proposalId)) {
            bytes32 queueId = _executorIds[proposalId];
            if (queueId == bytes32(0)) {
                return ProposalState.Succeeded;
            } else if (_executor.isOperationDone(queueId)) {
                return ProposalState.Executed;
            } else if (_executor.isOperationPending(queueId)) {
                return ProposalState.Queued;
            } else {
                return ProposalState.Canceled;
            }
        } else {
            return ProposalState.Defeated;
        }
    }

    /**
     * @dev Part of the Governor Bravo's interface: _"The number of votes required in order for a voter to become a proposer"_.
     */
    function proposalThreshold() public view virtual returns (uint256) {
        return 1;
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
        return _proposals[proposalId].voteEnd;
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
     * The actionsHash is produced by hashing the ABI encoded 'proposalId', the `targets` array, the `values` array, and the
     * `calldatas` array.
     * This can be reproduced from the proposal data which is part of the {ProposalCreated} event.
     *
     * Note that the chainId and the governor address are not part of the proposal id computation. Consequently, the
     * same proposal (with same operation and same description) will have the same id if submitted on multiple governors
     * across multiple networks. This also means that in order to execute the same operation twice (on the same
     * governor) the proposer will have to change the description in order to avoid proposal id conflicts.
     */
    function hashProposalActions(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) public pure virtual override returns (uint256) {
        return uint256(keccak256(abi.encode(proposalId, targets, values, calldatas)));
    }

    /**
     * @dev Generates a salt for the _executor's operationId, by hashing the proposalId with the Governor version.
     *
     * Important for avoiding operationId clashes in the Executor for (potential) future versions of Governor.
     */
    function generateExecutorSalt(uint256 proposalId) public view override returns (bytes32 salt) {
        return keccak256(abi.encode(proposalId, bytes(version())));
    }

    /**
     * @dev See {IGovernor-propose}.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string[] memory signatures,
        string memory description
    ) public virtual override returns (uint256) {
        address proposer = _msgSender();
        uint256 currentTimepoint = clock();

        require(
            getVotes(proposer, currentTimepoint - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );

        require(targets.length > 0, "Governor: proposal must provide actions");
        require(targets.length == values.length, "Governor: invalid proposal length");
        require(targets.length == calldatas.length, "Governor: invalid proposal length");
        require(targets.length == signatures.length, "Governor: invalid proposal length");

        if (_token.provisionMode() == IVotesProvisioner.ProvisionModes.Founding) {
            require(
                _token.totalSupply() >= governanceThreshold,
                "Governor: Not enough votes to enter governance"
            );
            require(
                targets[0] == address(_token) && bytes4(calldatas[0]) == _token.setProvisionMode.selector,
                "Governor: Cannot propose additional actions until the token's provision mode is upgraded from founding mode"
            );
        }

        // Verify the human-readable function signatures
        // Fail if calldata is included BUT the function signature doesn't match the calldata function identifier
        for (uint256 i = 0; i < signatures.length; ++i) {
            if (calldatas[i].length > 0) {
                require(
                    bytes4(calldatas[i]) == bytes4(keccak256(bytes(signatures[i]))),
                    "Governor: function signature(s) must match the calldata function identifiers"
                );
            }
        }

        // Increment proposal counter
        proposalCount++;
        uint256 newProposalId = proposalCount;

        // Generate voting periods
        uint256 snapshot = currentTimepoint + votingDelay();
        uint256 deadline = snapshot + votingPeriod();

        _proposals[newProposalId] = ProposalCore({
            proposalId: newProposalId,
            actionsHash: hashProposalActions(newProposalId, targets, values, calldatas),
            proposer: proposer,
            voteStart: snapshot.toUint64(),
            voteEnd: deadline.toUint64(),
            executed: false,
            canceled: false,
            __gap_unused0: 0,
            __gap_unused1: 0
        });

        emit ProposalCreated(
            newProposalId,
            proposer,
            targets,
            values,
            signatures,
            calldatas,
            snapshot,
            deadline,
            description
        );

        return newProposalId;
    }

    /**
     * @dev Function to queue a proposal to the timelock.
     */
    function queue(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) public virtual override returns (uint256) {

        require(state(proposalId) == ProposalState.Succeeded, "Governor: proposal not successful");

        uint256 actionsHash = hashProposalActions(proposalId, targets, values, calldatas);
        require(_proposals[proposalId].actionsHash == actionsHash);

        uint256 delay = _executor.getMinDelay();
        bytes32 operationId = _executor.scheduleBatch(
            targets,
            values,
            calldatas,
            0,
            generateExecutorSalt(proposalId),
            delay
        );
        _executorIds[proposalId] = operationId;

        emit ProposalQueued(proposalId, block.timestamp + delay);

        return proposalId;
    }

    /**
     * @dev See {IGovernor-execute}.
     */
    function execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) public virtual override returns (uint256) {

        ProposalState status = state(proposalId);
        require(
            status == ProposalState.Succeeded || status == ProposalState.Queued,
            "Governor: proposal not successful"
        );
        _proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);

        _beforeExecute(proposalId, targets, values, calldatas);
        _execute(proposalId, targets, values, calldatas);
        _afterExecute(proposalId, targets, values, calldatas);

        return proposalId;
    }

    /**
     * @dev See {IGovernor-cancel}.
     */
    function cancel(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) public virtual override returns (uint256) {
        require(state(proposalId) == ProposalState.Pending, "Governor: too late to cancel");
        require(_msgSender() == _proposals[proposalId].proposer, "Governor: only proposer can cancel");
        return _cancel(proposalId, targets, values, calldatas);
    }

    /**
     * @dev Overridden execute function that run the already queued proposal through the timelock.
     */
    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) internal virtual {
        _executor.executeBatch{value: msg.value}(targets, values, calldatas, 0, generateExecutorSalt(proposalId));
    }

    /**
     * @dev Hook before execution is triggered.
     */
    function _beforeExecute(
        uint256 /* proposalId */,
        address[] memory targets,
        uint256[] memory /* values */,
        bytes[] memory calldatas
    ) internal virtual {
        if (executor() != address(this)) {
            for (uint256 i = 0; i < targets.length; ++i) {
                if (targets[i] == address(this)) {
                    _governanceCall.pushBack(keccak256(calldatas[i]));
                }
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
        if (executor() != address(this)) {
            if (!_governanceCall.empty()) {
                _governanceCall.clear();
            }
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
        uint256 proposalId,
        address[] memory /*targets*/,
        uint256[] memory /*values*/,
        bytes[] memory /*calldatas*/
    ) internal virtual returns (uint256) {

        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Canceled && status != ProposalState.Expired && status != ProposalState.Executed,
            "Governor: proposal not active"
        );
        _proposals[proposalId].canceled = true;

        // Added from "TimelockController"
        if (_executorIds[proposalId] != 0) {
            _executor.cancel(_executorIds[proposalId]);
            delete _executorIds[proposalId];
        }

        emit ProposalCanceled(proposalId);

        return proposalId;
    }

    /**
     * @dev Public accessor to check the eta of a queued proposal
     */
    function proposalEta(uint256 proposalId) public view virtual override returns (uint256) {
        uint256 eta = _executor.getTimestamp(_executorIds[proposalId]);
        return eta == 1 ? 0 : eta; // _DONE_TIMESTAMP (1) should be replaced with a 0 value
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
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

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
     * @dev Relays a transaction or function call to an arbitrary target. In cases where the governance _executor
     * is some contract other than the governor itself, like when using a timelock, this function can be invoked
     * in a governance proposal to recover tokens or Ether that was sent to the governor contract by mistake.
     * Note that if the _executor is simply the governor itself, use of `relay` is redundant.
     */
    function relay(address target, uint256 value, bytes calldata data) external payable virtual onlyGovernance {
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        Address.verifyCallResult(success, returndata, "Governor: relay reverted without message");
    }

}
