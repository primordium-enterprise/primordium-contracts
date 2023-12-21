// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (Governor.sol)

pragma solidity ^0.8.20;

import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {IGovernorBase} from "../interfaces/IGovernorBase.sol";
import {IGovernorToken} from "../interfaces/IGovernorToken.sol";
import {Treasurer} from "src/executor/base/Treasurer.sol";
import {TimelockAvatarControlled} from "./TimelockAvatarControlled.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";

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
    ERC165Upgradeable,
    EIP712Upgradeable,
    NoncesUpgradeable,
    IGovernorBase
{
    using SafeCast for uint256;
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

    function _getGovernorBaseStorage() private pure returns (GovernorBaseStorage storage $) {
        assembly {
            $.slot := GOVERNOR_BASE_STORAGE
        }
    }

    /**
     * @dev Error thrown if a relay call by the exector to this contract reverts.
     */
    error RelayFailed();

    function __GovernorBase_init(
        string calldata name_,
        address executor_,
        address token_,
        uint256 governanceCanBeginAt_,
        uint256 governanceThresholdBps_
    )
        internal
        virtual
        onlyInitializing
    {
        if (governanceThresholdBps_ > BasisPoints.MAX_BPS) {
            revert BasisPoints.BPSValueTooLarge(governanceThresholdBps_);
        }

        string memory version_ = version();
        __EIP712_init(name_, version_);
        __TimelockAvatarControlled_init(executor_);

        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        $._token = IGovernorToken(token_);
        $._governanceCanBeginAt = governanceCanBeginAt_.toUint40();
        // If it is less than the MAX_BPS (10_000), it fits into uint16 without SafeCast
        $._governanceThresholdBps = uint16(governanceThresholdBps_);

        emit GovernorBaseInitialized(
            name_, version_, executor_, token_, governanceCanBeginAt_, governanceThresholdBps_, $._isFounded
        );
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, ERC165Upgradeable)
        returns (bool)
    {
        // forgefmt: disable-next-item
        return
            interfaceId == type(IGovernorBase).interfaceId ||
            super.supportsInterface(interfaceId);
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
    function token() public view override returns (IGovernorToken _token) {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        _token = $._token;
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
        _governanceCanBeginAt = _getGovernorBaseStorage()._governanceCanBeginAt;
    }

    /// @inheritdoc IGovernorBase
    function governanceThreshold() public view returns (uint256 threshold) {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        IGovernorToken _token = $._token;
        bool isFounded = $._isFounded;
        uint256 bps = $._governanceThresholdBps;
        if (isFounded) {
            return threshold;
        }
        threshold = _token.maxSupply().bpsUnchecked(bps);
    }

    /// @inheritdoc IGovernorBase
    function initializeGovernance(uint256 proposalId) external virtual onlyGovernance {
        _initializeGovernance(proposalId);
    }

    /// @dev The proposalId is verified when the proposal is created.
    function _initializeGovernance(uint256 proposalId) internal virtual {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();

        IGovernorToken _token = $._token;
        bool active = $._isFounded;
        uint256 bps = $._governanceThresholdBps;

        // Revert if already initialized
        if (active) {
            revert GovernanceAlreadyInitialized();
        }

        // TODO: Add this back in following Governance reorg
        // Check that the total supply at the vote end is still above the threshold
        // uint256 voteEndedSupply = _token.getPastTotalSupply(proposalDeadline(proposalId));
        // uint256 threshold = _token.maxSupply().bpsUnchecked(bps);
        // if (voteEndedSupply < threshold) {
        //     revert GovernanceThresholdIsNotMet(threshold, voteEndedSupply);
        // }

        // Try enabling balance shares on the executor (continue if already enabled, revert otherwise)
        try Treasurer(payable(address(executor()))).enableBalanceShares(true) {}
        catch (bytes memory errData) {
            if (bytes4(errData) != Treasurer.DepositSharesAlreadyInitialized.selector) {
                assembly ("memory-safe") {
                    revert(add(errData, 0x20), mload(errData))
                }
            }
        }

        $._isFounded = true;
        emit GovernanceInitialized(proposalId);
    }

    /// @inheritdoc IGovernorBase
    function isGovernanceActive() public view virtual returns (bool _isGovernanceActive) {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        _isGovernanceActive = $._isFounded;
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
    )
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _getVotes(account, timepoint, params);
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
        virtual
        returns (uint256 voteWeight)
    {
        voteWeight = _getVotes(token(), account, timepoint, params);
    }

    /**
     * @dev Overload that takes the vote token as a parameter in case it has already been cached from storage.
     */
    function _getVotes(
        IGovernorToken _token,
        address account,
        uint256 timepoint,
        bytes memory /*params*/
    )
        internal
        view
        virtual
        returns (uint256 voteWeight)
    {
        voteWeight = _token.getPastVotes(account, timepoint);
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
                mstore(0, 0xdb6a42ee) // bytes4(keccak256(RelayFailed()))
                revert(0x1c, 0x04)
            }
        }
    }
}
