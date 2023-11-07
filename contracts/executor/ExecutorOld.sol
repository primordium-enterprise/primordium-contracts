// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v4.8.2) (TimelockController.sol)

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @dev Contract module which acts as a timelocked controller. When set as the
 * owner of an `Ownable` smart contract, it enforces a timelock on all
 * `onlyOwner` maintenance operations. This gives time for users of the
 * controlled contract to exit before a potentially dangerous maintenance
 * operation is applied.
 *
 * By default, this contract is self administered, meaning administration tasks
 * have to go through the timelock process. The proposer (resp executor) role
 * is in charge of proposing (resp executing) operations. A common use case is
 * to position this {Executor} as the owner of a smart contract, with
 * a multisig or a DAO as the sole proposer.
 *
 * _Available since v3.3._
 */
abstract contract ExecutorOld is Ownable2Step, IERC721Receiver, IERC1155Receiver {

    uint256 internal constant _DONE_TIMESTAMP = uint256(1);

    uint256 public constant MIN_DELAY = 2 days;
    uint256 public constant MAX_DELAY = 30 days;

    mapping(bytes32 => uint256) private _timestamps;
    uint256 private _minDelay;

    /**
     * @dev Emitted when a call is scheduled as part of operation `id`.
     */
    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );

    /**
     * @dev Emitted when a call is performed as part of operation `id`.
     */
    event CallExecuted(bytes32 indexed id, uint256 indexed index, address target, uint256 value, bytes data);

    /**
     * @dev Emitted when new proposal is scheduled with non-zero salt.
     */
    event CallSalt(bytes32 indexed id, bytes32 salt);

    /**
     * @dev Emitted when operation `id` is cancelled.
     */
    event Cancelled(bytes32 indexed id);

    /**
     * @dev Emitted when the minimum delay for future operations is modified.
     */
    event MinDelayChange(uint256 oldDuration, uint256 newDuration);

    error OwnershipCannotBeRevoked();
    error OnlyTimelock();
    error ActionLengthsMismatch();
    error OperationAlreadyScheduled();
    error InsufficientDelay();
    error OperationCannotBeCancelled();
    error OperationCallReverted(address target, uint256 value, bytes data);
    error OperationNotReady();
    error OperationMissingDependency(bytes32 missingPredecessor);
    error MinDelayOutOfRange(uint256 min, uint256 max);

    /**
     * @dev Modifier to make a function callable only by the owner, or by the Executor itself through the execution
     * of a scheduled transaction.
     */
    modifier onlyOwnerOrSelf() {
        if (_msgSender() != address(this)) {
            _checkOwner();
        }
        _;
    }

    /**
     * @dev Modifier that ensures the caller must be the Executor itself, meaning the transaction must have gone through
     * the timelock process.
     */
    modifier onlyTimelock() {
        _onlyTimelock();
        _;
    }

    function _onlyTimelock() private view {
        if (msg.sender != address(this)) revert OnlyTimelock();
    }

    /**
     * @dev Initializes the contract with the following parameters:
     *
     * - `minDelay_`: initial minimum delay for operations
     * - `owner_`: optional account to transfer ownership to; default to msg.sender() with 0 address.
     */
    constructor(uint256 minDelay_, address owner_) {
        // optional owner
        if (owner_ != address(0)) {
            transferOwnership(owner_);
        }

        _minDelay = minDelay_;
        emit MinDelayChange(0, minDelay_);
    }

    /**
     * @dev Contract might receive/hold ETH as part of the maintenance process.
     */
    receive() external payable {}

    fallback() external payable {}

    // Don't let contract renounce ownership (ownership cannot be recovered)
    function renounceOwnership() public pure override {
        revert OwnershipCannotBeRevoked();
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    /**
     * @dev Returns whether an id correspond to a registered operation. This
     * includes both Pending, Ready and Done operations.
     */
    function isOperation(bytes32 id) public view virtual returns (bool registered) {
        return getTimestamp(id) > 0;
    }

    /**
     * @dev Returns whether an operation is pending or not.
     */
    function isOperationPending(bytes32 id) public view virtual returns (bool pending) {
        return getTimestamp(id) > _DONE_TIMESTAMP;
    }

    /**
     * @dev Returns whether an operation is ready or not.
     */
    function isOperationReady(bytes32 id) public view virtual returns (bool ready) {
        uint256 timestamp = getTimestamp(id);
        return timestamp > _DONE_TIMESTAMP && timestamp <= block.timestamp;
    }

    /**
     * @dev Returns whether an operation is done or not.
     */
    function isOperationDone(bytes32 id) public view virtual returns (bool done) {
        return getTimestamp(id) == _DONE_TIMESTAMP;
    }

    /**
     * @dev Returns the timestamp at which an operation becomes ready (0 for
     * unset operations, 1 for done operations).
     */
    function getTimestamp(bytes32 id) public view virtual returns (uint256 timestamp) {
        return _timestamps[id];
    }

    /**
     * @dev Returns the minimum delay for an operation to become valid.
     *
     * This value can be changed by executing an operation that calls `updateDelay`.
     */
    function getMinDelay() public view virtual returns (uint256 duration) {
        return _minDelay;
    }

    /**
     * @dev Returns the identifier of an operation containing a single
     * transaction.
     */
    function hashOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) public pure virtual returns (bytes32 operationId) {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }

    /**
     * @dev Returns the identifier of an operation containing a batch of
     * transactions.
     */
    function hashOperationBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) public pure virtual returns (bytes32 operationId) {
        return keccak256(abi.encode(targets, values, payloads, predecessor, salt));
    }

    /**
     * @dev Changes the minimum timelock duration for future operations.
     *
     * Emits a {MinDelayChange} event.
     *
     * Requirements:
     *
     * - the caller must be the timelock itself. This can only be achieved by scheduling and later executing
     * an operation where the timelock is the target and the data is the ABI-encoded call to this function.
     */
    function updateDelay(uint256 newDelay) external virtual onlyTimelock {
        if (
            newDelay < MIN_DELAY ||
            newDelay > MAX_DELAY
        ) revert MinDelayOutOfRange(MIN_DELAY, MAX_DELAY);

        emit MinDelayChange(_minDelay, newDelay);
        _minDelay = newDelay;
    }

    /**
     * @dev Schedule an operation containing a single transaction.
     *
     * Emits events {CallScheduled} and {CallSalt}.
     */
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual onlyOwner returns (bytes32 operationId) {
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        _schedule(id, delay);
        emit CallScheduled(id, 0, target, value, data, predecessor, delay);
        if (salt != bytes32(0)) {
            emit CallSalt(id, salt);
        }
        return id;
    }

    /**
     * @dev Schedule an operation containing a batch of transactions.
     *
     * Emits a {CallSalt} event and one {CallScheduled} event per transaction in the batch.
     */
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual onlyOwner returns (bytes32 operationId) {
        if (
            targets.length != values.length ||
            targets.length != payloads.length
        ) revert ActionLengthsMismatch();

        bytes32 id = hashOperationBatch(targets, values, payloads, predecessor, salt);
        _schedule(id, delay);
        for (uint256 i = 0; i < targets.length; ++i) {
            emit CallScheduled(id, i, targets[i], values[i], payloads[i], predecessor, delay);
        }
        if (salt != bytes32(0)) {
            emit CallSalt(id, salt);
        }
        return id;
    }

    /**
     * @dev Schedule an operation that is to become valid after a given delay.
     */
    function _schedule(bytes32 id, uint256 delay) private {
        if (isOperation(id)) revert OperationAlreadyScheduled();
        if (delay < getMinDelay()) revert InsufficientDelay();
        _timestamps[id] = block.timestamp + delay;
    }

    /**
     * @dev Cancel an operation.
     */
    function cancel(bytes32 id) public virtual onlyOwner {
        if (!isOperationPending(id)) revert OperationCannotBeCancelled();
        delete _timestamps[id];

        emit Cancelled(id);
    }

    /**
     * @dev Execute an (ready) operation containing a single transaction.
     *
     * Emits a {CallExecuted} event.
     */
    // This function can reenter, but it doesn't pose a risk because _afterCall checks that the proposal is pending,
    // thus any modifications to the operation during reentrancy should be caught.
    // slither-disable-next-line reentrancy-eth
    function execute(
        address target,
        uint256 value,
        bytes calldata payload,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual onlyOwner {
        bytes32 id = hashOperation(target, value, payload, predecessor, salt);

        _beforeCall(id, predecessor);
        _execute(target, value, payload);
        emit CallExecuted(id, 0, target, value, payload);
        _afterCall(id);
    }

    /**
     * @dev Execute an (ready) operation containing a batch of transactions.
     *
     * Emits one {CallExecuted} event per transaction in the batch.
     *
     * Requirements:
     *
     * - the caller must have the 'executor' role.
     */
    // This function can reenter, but it doesn't pose a risk because _afterCall checks that the proposal is pending,
    // thus any modifications to the operation during reentrancy should be caught.
    // slither-disable-next-line reentrancy-eth
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual onlyOwner {
        if (
            targets.length != values.length ||
            targets.length != payloads.length
        ) revert ActionLengthsMismatch();

        bytes32 id = hashOperationBatch(targets, values, payloads, predecessor, salt);

        _beforeCall(id, predecessor);
        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            uint256 value = values[i];
            bytes calldata payload = payloads[i];
            _execute(target, value, payload);
            emit CallExecuted(id, i, target, value, payload);
        }
        _afterCall(id);
    }

    /**
     * @dev Execute an operation's call.
     */
    function _execute(address target, uint256 value, bytes calldata data) internal virtual {
        _beforeExecute(target, value, data);
        (bool success, ) = target.call{value: value}(data);
        if (!success) revert OperationCallReverted(target, value, data);
    }

    /**
     * @dev Checks before execution of target, value, and calldata
     */
    function _beforeExecute(address target, uint256 value, bytes calldata data) internal virtual { }

    /**
     * @dev Checks before execution of an operation's calls.
     */
    function _beforeCall(bytes32 id, bytes32 predecessor) private view {
        if (!isOperationReady(id)) revert OperationNotReady();
        if (predecessor != bytes32(0) && !isOperationDone(predecessor)) revert OperationMissingDependency(predecessor);
    }

    /**
     * @dev Checks after execution of an operation's calls.
     */
    function _afterCall(bytes32 id) private {
        if (!isOperationReady(id)) revert OperationNotReady();
        _timestamps[id] = _DONE_TIMESTAMP;
    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155Received}.
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155BatchReceived}.
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
