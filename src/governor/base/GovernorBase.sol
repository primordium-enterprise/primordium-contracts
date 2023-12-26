// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (Governor.sol)
// Based on OpenZeppelin Contracts (last updated v5.0.0) (GovernorVotes.sol)

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
import {BasisPoints} from "src/libraries/BasisPoints.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

/**
 * @title GovernorBase
 * @author Ben Jett - @BCJdevelopment
 * @notice The base governance storage for the Governor (token and executor addresses, founding parameters)
 * @dev Uses the zodiac-based TimelockAvatar contract as the executor, and uses an IERC5805 vote token for tracking
 * voting weights.
 */
abstract contract GovernorBase is
    Initializable,
    ContextUpgradeable,
    EIP712Upgradeable,
    NoncesUpgradeable,
    IGovernorBase
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

    function __GovernorBase_init(bytes memory governorBaseInitParams) internal virtual onlyInitializing {
        (
            string memory name_,
            address executor_,
            address token_,
            uint256 governanceCanBeginAt_,
            uint256 governanceThresholdBps_
        ) = abi.decode(governorBaseInitParams, (string, address, address, uint256, uint256));

        if (governanceThresholdBps_ > BasisPoints.MAX_BPS) {
            revert BasisPoints.BPSValueTooLarge(governanceThresholdBps_);
        }

        string memory version_ = version();
        __EIP712_init(name_, version_);

        // Initialize executor
        if (address(executor()) != address(0)) {
            revert GovernorExecutorAlreadyInitialized();
        }
        _updateExecutor(executor_);

        GovernorBaseLogicV1.GovernorBaseStorage storage $ = GovernorBaseLogicV1._getGovernorBaseStorage();
        $._token = IGovernorToken(token_);
        $._governanceCanBeginAt = governanceCanBeginAt_.toUint40();
        // If it is less than the MAX_BPS (10_000), it fits into uint16 without SafeCast
        $._governanceThresholdBps = uint16(governanceThresholdBps_);

        emit GovernorBaseInitialized(
            name_, version_, executor_, token_, governanceCanBeginAt_, governanceThresholdBps_, $._isFounded
        );
    }

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
    function updateExecutor(address newExecutor) external virtual onlyGovernance {
        _updateExecutor(newExecutor);
    }

    function _updateExecutor(address newExecutor) internal virtual {
        GovernorBaseLogicV1.updateExecutor(newExecutor);
    }

    /// @inheritdoc IGovernorBase
    function token() public view returns (IGovernorToken _token) {
        return GovernorBaseLogicV1._token();
    }

    /// @inheritdoc IERC6372
    function clock() public view virtual override returns (uint48) {
        return GovernorBaseLogicV1._clock();
    }

    // function _clock(IGovernorToken _token) internal view virtual returns (uint48) {
    //     return GovernorBaseLogicV1._clock(_token);
    // }

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
        return GovernorBaseLogicV1.governanceCanBeginAt();
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
        GovernorBaseLogicV1._foundGovernor(proposalId);
    }

    /// @inheritdoc IGovernorBase
    function isFounded() public view virtual returns (bool) {
        return GovernorBaseLogicV1.isFounded();
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

    /**
     * @dev Default additional encoded parameters used by castVote methods that don't include them
     *
     * Note: Should be overridden by specific implementations to use an appropriate value, the
     * meaning of the additional params, in the context of that implementation
     */
    function _defaultParams() internal pure returns (bytes memory) {
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
