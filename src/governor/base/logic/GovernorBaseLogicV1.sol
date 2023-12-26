// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IGovernorBase} from "../../interfaces/IGovernorBase.sol";
import {IGovernorToken} from "../../interfaces/IGovernorToken.sol";
import {IAvatar} from "src/executor/interfaces/IAvatar.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {Treasurer} from "src/executor/base/Treasurer.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {ERC165Verifier} from "src/libraries/ERC165Verifier.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

/**
 * @title GovernorBaseLogicV1
 * @author Ben Jett - @BCJdevelopment
 * @notice Internal storage logic for the GovernorBase (founding parameters, executor storage, etc.).
 * @dev Mostly consists of internal functions that are inlined wherever they are used. But this makes these functions
 * available to external libraries that are used with DELEGATECALL's to split the code.
 */
library GovernorBaseLogicV1 {
    using ERC165Verifier for address;
    using BasisPoints for uint256;

    /// @custom:storage-location erc7201:GovernorBase.Storage
    struct GovernorBaseStorage {
        IGovernorToken _token; // 20 bytes
        bool _isFounded; // 1 byte
        uint40 _governanceCanBeginAt; // 5 bytes
        uint16 _governanceThresholdBps; // 2 bytes
    }

    // keccak256(abi.encode(uint256(keccak256("GovernorBase.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant GOVERNOR_BASE_STORAGE = 0xb6d7ebdb5e1a4269d709811afd6c2af6a6e2a583a4e8c954ef3e8b8a20527500;

    function _getGovernorBaseStorage() internal pure returns (GovernorBaseStorage storage $) {
        assembly {
            $.slot := GOVERNOR_BASE_STORAGE
        }
    }

    /// @custom:storage-location erc7201:GovernorBase.Executor.Storage
    struct GovernorBaseExecutorStorage {
        // This queue keeps track of the governor operating on itself. Calls to functions protected by the
        // {onlyGovernance} modifier needs to be whitelisted in this queue. Whitelisting is set in {execute}, consumed
        // by the {onlyGovernance} modifier and eventually reset after {_executeOperations} is complete. This ensures
        // that the execution of {onlyGovernance} protected calls can only be achieved through successful proposals.
        DoubleEndedQueue.Bytes32Deque _governanceCall;
        // The executor serves as the timelock and treasury
        ITimelockAvatar _executor;
    }

    // keccak256(abi.encode(uint256(keccak256("GovernorBase.Executor.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant GOVERNOR_BASE_EXECUTOR_STORAGE =
        0x88bf56bf2ed2d0c9e1e844f78880501dab23bade1f1a40dcf775f39090e6d300;

    function _getExecutorStorage() internal pure returns (GovernorBaseExecutorStorage storage $) {
        assembly {
            $.slot := GOVERNOR_BASE_EXECUTOR_STORAGE
        }
    }

    /**
     * @dev Get the governance call dequeuer for governance operations.
     */
    function _getGovernanceCallQueue() internal view returns (DoubleEndedQueue.Bytes32Deque storage governanceCall) {
        governanceCall = _getExecutorStorage()._governanceCall;
    }

    /**
     * @dev Returns the address of the executor.
     */
    function _executor() internal view returns (ITimelockAvatar executor_) {
        executor_ = _getExecutorStorage()._executor;
    }

    /**
     * @dev Updates the executor to a new address. Does not allow setting to itself. Checks that the executor interface
     * follows the {IAvatar} and {ITimelockAvatar} interfaces.
     */
    function updateExecutor(address newExecutor) public {
        if (newExecutor == address(0) || newExecutor == address(this)) {
            revert IGovernorBase.GovernorInvalidExecutorAddress(newExecutor);
        }

        newExecutor.checkInterfaces([type(IAvatar).interfaceId, type(ITimelockAvatar).interfaceId]);

        GovernorBaseExecutorStorage storage $ = _getExecutorStorage();
        emit IGovernorBase.ExecutorUpdate(address($._executor), newExecutor);
        $._executor = ITimelockAvatar(payable(newExecutor));
    }

    function _token() internal view returns (IGovernorToken token_) {
        token_ = _getGovernorBaseStorage()._token;
    }

    function _clock() internal view returns (uint48) {
        return _clock(_token());
    }

    function _clock(IGovernorToken token_) internal view returns (uint48) {
        try token_.clock() returns (uint48 timepoint) {
            return timepoint;
        } catch {
            return Time.blockNumber();
        }
    }

    function _governanceCanBeginAt() internal view returns (uint256 governanceCanBeginAt_) {
        governanceCanBeginAt_ = _getGovernorBaseStorage()._governanceCanBeginAt;
    }

    function governanceFoundingVoteThreshold() public view returns (uint256 threshold) {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        IGovernorToken token_ = $._token;
        bool isFounded_ = $._isFounded;
        uint256 governanceThresholdBps_ = $._governanceThresholdBps;
        if (isFounded_) {
            return threshold;
        }
        threshold = token_.maxSupply().bpsUnchecked(governanceThresholdBps_);
    }

    function _foundGovernor(uint256 proposalId) internal {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();

        bool isFounded_ = $._isFounded;

        // Revert if already initialized
        if (isFounded_) {
            revert IGovernorBase.GovernorAlreadyFounded();
        }

        // Try enabling balance shares on the executor (continue if already enabled, revert otherwise)
        try Treasurer(payable(address(_executor()))).enableBalanceShares(true) {}
        catch (bytes memory errData) {
            if (bytes4(errData) != Treasurer.DepositSharesAlreadyInitialized.selector) {
                assembly ("memory-safe") {
                    revert(add(errData, 0x20), mload(errData))
                }
            }
        }

        $._isFounded = true;
        emit IGovernorBase.GovernorFounded(proposalId);
    }

    function _isFounded() internal view returns (bool isFounded_) {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        assembly ("memory-safe") {
            isFounded_ := and(0xff, shr(160, sload($.slot)))
        }
    }

    /**
     * @dev Get the voting weight of `account` at a specific `timepoint`, for a vote as described by `params`.
     */
    function _getVotes(
        address account,
        uint256 timepoint,
        bytes memory params
    )
        internal
        view
        returns (uint256 voteWeight)
    {
        voteWeight = _getVotes(_token(), account, timepoint, params);
    }

    /**
     * @dev Overload that takes the vote token as a parameter in case it has already been cached from storage.
     */
    function _getVotes(
        IGovernorToken token_,
        address account,
        uint256 timepoint,
        bytes memory /*params*/
    )
        internal
        view
        returns (uint256 voteWeight)
    {
        voteWeight = token_.getPastVotes(account, timepoint);
    }

    /**
     * @dev Defaults to no params.
     */
    function _defaultParams() internal pure returns (bytes memory) {
        return "";
    }
}
