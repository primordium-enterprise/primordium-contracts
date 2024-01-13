// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ProposalVotingLogicV1} from "./ProposalVotingLogicV1.sol";
import {GovernorBase} from "../GovernorBase.sol";
import {IGovernorBase} from "../../interfaces/IGovernorBase.sol";
import {IGovernorToken} from "../../interfaces/IGovernorToken.sol";
import {IAvatar} from "src/executor/interfaces/IAvatar.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {ITreasurer} from "src/executor/interfaces/ITreasurer.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {ERC165Verifier} from "src/libraries/ERC165Verifier.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {RolesLib} from "src/libraries/RolesLib.sol";
import {Enum} from "src/common/Enum.sol";
import {MultiSendEncoder} from "src/libraries/MultiSendEncoder.sol";
import {BatchArrayChecker} from "src/utils/BatchArrayChecker.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

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
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using Checkpoints for Checkpoints.Trace208;
    using SafeCast for uint256;

    bytes32 internal constant _PROPOSER_ROLE = keccak256("PROPOSER");
    bytes32 internal constant _CANCELER_ROLE = keccak256("CANCELER");

    bytes32 internal constant ALL_PROPOSAL_STATES_BITMAP =
        bytes32((2 ** (uint8(type(IGovernorBase.ProposalState).max) + 1)) - 1);

    /// @custom:storage-location erc7201:GovernorBase.Storage
    struct GovernorBaseStorage {
        // Governor settings
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

    /// @custom:storage-location erc7201:Proposals.Storage
    struct ProposalsStorage {
        uint256 _proposalCount;
        // Tracking core proposal data
        mapping(uint256 => IGovernorBase.ProposalCore) _proposals;
        // Tracking hashes of each proposal's actions
        mapping(uint256 => bytes32) _proposalActionsHashes;
        // Tracking queued operations on the TimelockAvatar
        mapping(uint256 => uint256) _proposalOpNonces;
    }

    // keccak256(abi.encode(uint256(keccak256("Proposals.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant PROPOSALS_STORAGE = 0x12dae0b7a75163feb738f3ebdd36c1ba0747f551a5ac705c9e7c1824cec3b800;

    function _getProposalsStorage() internal pure returns (ProposalsStorage storage $) {
        assembly {
            $.slot := PROPOSALS_STORAGE
        }
    }

    /// @custom:storage-location erc7201:Proposals.ProposalSettings.Storage
    struct ProposalSettingsStorage {
        uint16 _proposalThresholdBps;
        // uint24 allows each period to be up to 194 days long using timestamps (longer using block numbers)
        uint24 _votingDelay;
        uint24 _votingPeriod;
        // Grace period can be set to max to be unlimited
        uint48 _gracePeriod;
        Checkpoints.Trace208 _quorumBpsCheckpoints;
    }

    // keccak256(abi.encode(uint256(keccak256("Proposals.ProposalSettings.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant PROPOSAL_SETTINGS_STORAGE =
        0xddaa15f4123548e9bd63b0bf0b1ef94e9857e581d03ae278a788cfe245267b00;

    function _getProposalSettingsStorage() internal pure returns (ProposalSettingsStorage storage $) {
        assembly {
            $.slot := PROPOSAL_SETTINGS_STORAGE
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
    function setExecutor(address newExecutor) public {
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

    function foundGovernor(uint256 proposalId) public {
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();

        IGovernorToken token = $._token;
        uint256 _governanceThresholdBps = $._governanceThresholdBps;

        // Check that the total supply at the vote end is still above the threshold
        uint256 voteEndedSupply = token.getPastTotalSupply(_proposalDeadline(proposalId));
        uint256 threshold = token.maxSupply().bpsUnchecked(_governanceThresholdBps);
        if (voteEndedSupply < threshold) {
            revert IGovernorBase.GovernorFoundingVoteThresholdNotMet(threshold, voteEndedSupply);
        }

        // Revert if already initialized
        bool isFounded_ = $._isFounded;
        if (isFounded_) {
            revert IGovernorBase.GovernorAlreadyFounded();
        }

        // Try enabling balance shares on the executor (continue if already enabled, revert otherwise)
        try ITreasurer(payable(address(_executor()))).enableBalanceShares(true) {}
        catch (bytes memory errData) {
            if (bytes4(errData) != ITreasurer.DepositSharesAlreadyInitialized.selector) {
                assembly ("memory-safe") {
                    revert(add(errData, 0x20), mload(errData))
                }
            }
        }

        $._isFounded = true;
        emit IGovernorBase.GovernorFounded(proposalId);
    }

    function _isFounded() internal view returns (bool isFounded_) {
        // NOTE: The below leads to lower bytecode size than just calling _getGovernorBaseStorage()._isFounded
        GovernorBaseStorage storage $ = _getGovernorBaseStorage();
        assembly ("memory-safe") {
            isFounded_ := and(0xff, shr(160, sload($.slot)))
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL GETTERS
    //////////////////////////////////////////////////////////////////////////*/

    function _proposalCount() internal view returns (uint256 count) {
        count = _getProposalsStorage()._proposalCount;
    }

    function _proposalSnapshot(uint256 proposalId) internal view returns (uint256 snapshot) {
        snapshot = _getProposalsStorage()._proposals[proposalId].voteStart;
    }

    function _proposalDeadline(uint256 proposalId) internal view returns (uint256 deadline) {
        ProposalsStorage storage $ = _getProposalsStorage();
        deadline = $._proposals[proposalId].voteStart + $._proposals[proposalId].voteDuration;
    }

    function _proposalProposer(uint256 proposalId) internal view returns (address proposer) {
        proposer = _getProposalsStorage()._proposals[proposalId].proposer;
    }

    function _proposalActionsHash(uint256 proposalId) internal view returns (bytes32 actionsHash) {
        actionsHash = _getProposalsStorage()._proposalActionsHashes[proposalId];
    }

    function _proposalEta(uint256 proposalId) internal view returns (uint256 eta) {
        ProposalsStorage storage $ = _getProposalsStorage();
        if ($._proposals[proposalId].queued) {
            uint256 opNonce = $._proposalOpNonces[proposalId];
            eta = _executor().getOperationExecutableAt(opNonce);
        }
    }

    function _proposalOpNonce(uint256 proposalId) internal view returns (uint256 opNonce) {
        opNonce = _getProposalsStorage()._proposalOpNonces[proposalId];
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

    function hashProposalActions(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
        pure
        returns (bytes32 actionsHash)
    {
        // Below performs gas-optimized equivalent of "keccak256(abi.encode(targets, values, calldatas))"
        assembly ("memory-safe") {
            // Start at free memory (don't update free mem pointer, just hash and exit)
            let start := mload(0x40)
            // Initialize pointer (3 dynamic arrays, so point past 3 * 32 byte header values)
            let p := add(start, 0x60)

            // Store targets
            {
                mstore(start, 0x60) // targets is first header item, store offset to pointer
                mstore(0, mul(targets.length, 0x20)) // byte length is array length times 32
                mstore(p, targets.length) // store targets length
                calldatacopy(add(p, 0x20), targets.offset, mload(0)) // copy targets array items

                // Increment pointer
                p := add(p, add(0x20, mload(0)))
            }

            // Store values
            {
                mstore(add(start, 0x20), sub(p, start)) // values is second header item, store offset to pointer
                mstore(0, mul(values.length, 0x20)) // byte length is array length times 32
                mstore(p, values.length) // store values length
                calldatacopy(add(p, 0x20), values.offset, mload(0)) // copy values array items

                // Increment pointer
                p := add(p, add(0x20, mload(0)))
            }

            // Store calldatas
            {
                mstore(add(start, 0x40), sub(p, start)) // calldatas is third header item, store offset to pointer
                let calldatasByteLength := 0 // initialize byte length to zero
                if gt(calldatas.length, 0) {
                    // since calldatas is dynamic array of dynamic arrays, not as straightforward to copy...
                    // but the calldata is already abi encoded
                    // so we can add the last item's offset to the last item's (padded) length for total copy length
                    let finalItemOffset := calldataload(add(calldatas.offset, mul(sub(calldatas.length, 0x01), 0x20)))
                    let finalItemByteLength := calldataload(add(calldatas.offset, finalItemOffset))
                    finalItemByteLength := mul(0x20, div(add(finalItemByteLength, 0x1f), 0x20)) // pad to 32 bytes
                    calldatasByteLength :=
                        add(
                            finalItemOffset,
                            add(0x20, finalItemByteLength) // extra 32 bytes for the item length
                        )
                }
                mstore(p, calldatas.length) // store calldatas length
                calldatacopy(add(p, 0x20), calldatas.offset, calldatasByteLength) // copy calldatas array items

                // Increment pointer
                p := add(p, add(0x20, calldatasByteLength))
            }

            // The result is the hash starting at "start", hashing the pointer "p" minus "start" bytes
            actionsHash := keccak256(start, sub(p, start))
        }
    }

    function state(uint256 proposalId) public view returns (IGovernorBase.ProposalState) {
        ProposalsStorage storage $ = _getProposalsStorage();

        // Single SLOAD
        IGovernorBase.ProposalCore storage proposal = $._proposals[proposalId];
        bool proposalQueued = proposal.queued;
        bool proposalCanceled = proposal.canceled;

        if (proposalQueued) {
            uint256 opNonce = $._proposalOpNonces[proposalId];
            ITimelockAvatar.OperationStatus opStatus = _executor().getOperationStatus(opNonce);

            if (opStatus == ITimelockAvatar.OperationStatus.Done) {
                return IGovernorBase.ProposalState.Executed;
            } else if (opStatus == ITimelockAvatar.OperationStatus.Canceled) {
                return IGovernorBase.ProposalState.Canceled;
            } else if (opStatus == ITimelockAvatar.OperationStatus.Expired) {
                return IGovernorBase.ProposalState.Expired;
            }

            return IGovernorBase.ProposalState.Queued;
        }

        if (proposalCanceled) {
            return IGovernorBase.ProposalState.Canceled;
        }

        uint256 snapshot = _proposalSnapshot(proposalId);
        if (snapshot == 0) {
            revert IGovernorBase.GovernorUnknownProposalId(proposalId);
        }

        uint256 currentClock = _clock();
        if (currentClock < snapshot) {
            return IGovernorBase.ProposalState.Pending;
        }

        uint256 deadline = _proposalDeadline(proposalId);
        if (currentClock < deadline) {
            return IGovernorBase.ProposalState.Active;
        }

        // If no quorum was reached, or if the vote did not succeed, the proposal is defeated
        if (!ProposalVotingLogicV1._quorumReached(proposalId) || !ProposalVotingLogicV1._voteSucceeded(proposalId)) {
            return IGovernorBase.ProposalState.Defeated;
        }

        uint256 grace = _proposalGracePeriod();
        if (currentClock > deadline + grace) {
            return IGovernorBase.ProposalState.Expired;
        }

        return IGovernorBase.ProposalState.Succeeded;
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL SETTINGS
    //////////////////////////////////////////////////////////////////////////*/

    function proposalThreshold() public view returns (uint256 proposalThreshold_) {
        IGovernorToken token = _token();
        uint256 proposalThresholdBps_ = _proposalThresholdBps();


        // Only need to calculate against totalSupply if the BPS is greater than zero
        if (proposalThresholdBps_ > 0) {
            uint256 totalSupply = token.getPastTotalSupply(_clock(token) - 1);

            // Block proposals if totalSupply is zero
            if (totalSupply == 0) {
                proposalThreshold_ = type(uint256).max;
                return proposalThreshold_;
            }

            // Use unchecked, overflow not a problem as long as the token's max supply <= type(uint224).max
            proposalThreshold_ = proposalThresholdBps_.bpsUnchecked(totalSupply);
        }
    }

    function _proposalThresholdBps() internal view returns (uint256 proposalThresholdBps_) {
        proposalThresholdBps_ = _getProposalSettingsStorage()._proposalThresholdBps;
    }

    function setProposalThresholdBps(uint256 newProposalThresholdBps) public {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();

        emit IGovernorBase.ProposalThresholdBPSUpdate($._proposalThresholdBps, newProposalThresholdBps);
        $._proposalThresholdBps = newProposalThresholdBps.toBps(); // toBps() checks for out of range BPS value
    }

    function _votingDelay() internal view returns (uint256 votingDelay_) {
        votingDelay_ = _getProposalSettingsStorage()._votingDelay;
    }

    function setVotingDelay(uint256 newVotingDelay) public {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();

        emit IGovernorBase.VotingDelayUpdate($._votingDelay, newVotingDelay);
        $._votingDelay = SafeCast.toUint24(newVotingDelay);
    }

    function _votingPeriod() internal view returns (uint256 votingPeriod_) {
        votingPeriod_ = _getProposalSettingsStorage()._votingPeriod;
    }

    function setVotingPeriod(uint256 newVotingPeriod) public {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();

        emit IGovernorBase.VotingPeriodUpdate($._votingPeriod, newVotingPeriod);
        $._votingPeriod = SafeCast.toUint24(newVotingPeriod);
    }

    function _proposalGracePeriod() internal view returns (uint256 proposalGracePeriod_) {
        proposalGracePeriod_ = _getProposalSettingsStorage()._gracePeriod;
    }

    function setProposalGracePeriod(uint256 newGracePeriod) public {
        // Don't allow overflow for setting to a high value "unlimited" value
        if (newGracePeriod > type(uint48).max) {
            newGracePeriod = type(uint48).max;
        }

        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        emit IGovernorBase.ProposalGracePeriodUpdate($._gracePeriod, newGracePeriod);
        $._gracePeriod = uint48(newGracePeriod);
    }

    /*//////////////////////////////////////////////////////////////////////////
        PROPOSAL CREATION/EXECUTION LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string[] memory signatures,
        string calldata description,
        address proposer
    )
        public
        returns (uint256 proposalId)
    {
        uint256 snapshot;
        uint256 duration;
        {
            (, uint256 currentClock) = _authorizeProposal(proposer, targets, values, calldatas, description);

            (uint256 votingDelay_, uint256 votingPeriod_) = _getVotingDelayAndPeriod();

            snapshot = currentClock + votingDelay_;
            duration = votingPeriod_;
        }

        proposalId = _propose(proposer, snapshot, duration, targets, values, calldatas, signatures, description);
    }

    /**
     * @dev Authorizes whether a proposal can be submitted by the provided proposer. Also includes front-running
     * protection as used in OpenZeppelin 5.0.0's {Governor.sol} contract.
     *
     * @notice This function checks whether the Governor has been founded, and restricts proposals to only initializing
     * governance if the Governor is not yet founded.
     *
     * @return token The IGovernorToken token read from storage for internal gas optimization
     * @return currentClock The current clock() value for the token for internal gas optimization (avoid re-calling)
     */
    function _authorizeProposal(
        address proposer,
        address[] calldata targets,
        uint256[] calldata, /*values*/
        bytes[] calldata calldatas,
        string calldata description
    )
        internal
        view
        returns (IGovernorToken token, uint256 currentClock)
    {
        // check description restriction
        if (!_isValidDescriptionForProposer(proposer, description)) {
            revert IGovernorBase.GovernorRestrictedProposer();
        }

        // check founded status
        bytes32 packedGovernorBaseStorage;
        bool isFounded;
        {
            bytes32 governorBaseStorageSlot = GOVERNOR_BASE_STORAGE;
            assembly ("memory-safe") {
                packedGovernorBaseStorage := sload(governorBaseStorageSlot)
                token := packedGovernorBaseStorage
                // The _isFounded bool is at byte index 20 (after 20 address bytes), so shift right 20 * 8 = 160 bits
                isFounded := and(shr(160, packedGovernorBaseStorage), 0xff)
            }
        }

        currentClock = _clock(token);

        // Check if the Governor has been founded yet
        if (!isFounded) {
            // Check if goverance can begin yet
            uint256 governanceCanBeginAt;
            assembly ("memory-safe") {
                // Shift right by 20 address bytes + 1 bool byte = 21 bytes * 8 = 168 bits
                governanceCanBeginAt := and(shr(0xa8, packedGovernorBaseStorage), 0xffffffffff)
            }
            if (block.timestamp < governanceCanBeginAt) {
                revert IGovernorBase.GovernorCannotBeFoundedYet(governanceCanBeginAt);
            }

            // Check the governance threshold
            uint256 _governanceThresholdBps;
            assembly ("memory-safe") {
                // Shift right by 20 address bytes + 1 bool byte + 5 uint40 bytes = 26 bytes * 8 = 208 bits
                _governanceThresholdBps := and(shr(0xd0, packedGovernorBaseStorage), 0xffff)
            }
            uint256 currentSupply = token.getPastTotalSupply(currentClock - 1);
            uint256 threshold = token.maxSupply().bpsUnchecked(_governanceThresholdBps);
            if (currentSupply < threshold) {
                revert IGovernorBase.GovernorFoundingVoteThresholdNotMet(threshold, currentSupply);
            }

            // Ensure that the only proposal action is to foundGovernor() on this Governor
            bytes calldata initData = calldatas[0];
            // forgefmt: disable-next-item
            if (
                targets.length != 1 ||
                targets[0] != address(this) ||
                bytes4(initData) != GovernorBase.foundGovernor.selector ||
                initData.length < 36 // 4 selector bytes + 32 proposalId bytes
            ) {
                revert IGovernorBase.GovernorFoundingActionRequired();
            }

            // Check that the provided proposalId is the expected proposalId
            uint256 expectedProposalId = _getProposalsStorage()._proposalCount + 1;
            uint256 providedProposalId;
            assembly ("memory-safe") {
                // Offset by 4 bytes for the function selector
                providedProposalId := calldataload(add(initData.offset, 0x04))
            }
            if (providedProposalId != expectedProposalId) {
                revert IGovernorBase.GovernorInvalidFoundingProposalID(expectedProposalId, providedProposalId);
            }
        }

        // Check the proposer's votes against the proposalThreshold() (if greater than zero)
        uint256 _proposalThreshold = proposalThreshold();
        if (_proposalThreshold > 0) {
            uint256 _proposerVotes =
                _getVotes(token, proposer, currentClock - 1, _defaultParams());
            if (_proposerVotes < _proposalThreshold) {
                // If the proposer votes is less than the threshold, and the proposer does not have the PROPOSER_ROLE...
                if (!RolesLib._hasRole(_PROPOSER_ROLE, proposer)) {
                    revert IGovernorBase.GovernorUnauthorizedSender(proposer);
                }
            }
        }
    }

    function _propose(
        address proposer,
        uint256 snapshot,
        uint256 duration,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string[] memory signatures,
        string calldata description
    )
        internal
        returns (uint256 proposalId)
    {
        BatchArrayChecker.checkArrayLengths(targets.length, values.length, calldatas.length, signatures.length);

        // Verify the human-readable function signatures
        _validateCalldataSignatures(calldatas, signatures);

        // Increment proposal counter
        ProposalsStorage storage $ = _getProposalsStorage();
        {
            bytes32 actionsHash = hashProposalActions(targets, values, calldatas);
            proposalId = ++$._proposalCount;
            $._proposalActionsHashes[proposalId] = actionsHash;
        }

        IGovernorBase.ProposalCore storage proposal = $._proposals[proposalId];
        proposal.proposer = proposer;
        proposal.voteStart = snapshot.toUint48();
        proposal.voteDuration = duration.toUint32();

        emit IGovernorBase.ProposalCreated(
            proposalId, proposer, targets, values, calldatas, signatures, snapshot, snapshot + duration, description
        );
    }

    function queue(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
        returns (uint256)
    {
        ProposalsStorage storage $ = _getProposalsStorage();
        if ($._proposalActionsHashes[proposalId] != hashProposalActions(targets, values, calldatas)) {
            revert IGovernorBase.GovernorInvalidProposalActions(proposalId);
        }

        _validateStateBitmap(proposalId, _encodeStateBitmap(IGovernorBase.ProposalState.Succeeded));

        // Set "queued" to true
        $._proposals[proposalId].queued = true;

        ITimelockAvatar executor = _executor();
        (address to, uint256 value, bytes memory data) =
            MultiSendEncoder.encodeMultiSendCalldata(address(executor), targets, values, calldatas);

        (, bytes memory returnData) =
            executor.execTransactionFromModuleReturnData(to, value, data, Enum.Operation.Call);

        (uint256 opNonce,, uint256 eta) = abi.decode(returnData, (uint256, bytes32, uint256));
        $._proposalOpNonces[proposalId] = opNonce;

        emit IGovernorBase.ProposalQueued(proposalId, eta);

        return proposalId;
    }

    function execute(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
        returns (uint256)
    {
        ProposalsStorage storage $ = _getProposalsStorage();
        if ($._proposalActionsHashes[proposalId] != hashProposalActions(targets, values, calldatas)) {
            revert IGovernorBase.GovernorInvalidProposalActions(proposalId);
        }

        _validateStateBitmap(proposalId, _encodeStateBitmap(IGovernorBase.ProposalState.Queued));

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

        emit IGovernorBase.ProposalExecuted(proposalId);

        return proposalId;
    }

    /**
     * @dev Executes an already queued proposal op on the timelock executor.
     */
    function _executeOperations(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        internal
    {
        ITimelockAvatar executor = _executor();
        (address to, uint256 value, bytes memory data) =
            MultiSendEncoder.encodeMultiSendCalldata(address(executor), targets, values, calldatas);

        ProposalsStorage storage $ = _getProposalsStorage();
        executor.executeOperation($._proposalOpNonces[proposalId], to, value, data, Enum.Operation.Call);
    }

    function cancel(
        uint256 proposalId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        public
        returns (uint256)
    {
        ProposalsStorage storage $ = _getProposalsStorage();
        if ($._proposalActionsHashes[proposalId] != hashProposalActions(targets, values, calldatas)) {
            revert IGovernorBase.GovernorInvalidProposalActions(proposalId);
        }

        // Only allow cancellation if the sender is CANCELER_ROLE, or if the proposer cancels before voting starts
        if (!RolesLib._hasRole(_CANCELER_ROLE, msg.sender)) {
            if (msg.sender != _proposalProposer(proposalId)) {
                revert IGovernorBase.GovernorUnauthorizedSender(msg.sender);
            }
            _validateStateBitmap(proposalId, _encodeStateBitmap(IGovernorBase.ProposalState.Pending));
        }

        return _cancel(proposalId);
    }

    /**
     * @dev Internal cancel mechanism: locks up the proposal timer, preventing it from being re-submitted. Marks it as
     * canceled to allow distinguishing it from executed proposals.
     *
     * Emits a {IGovernor-ProposalCanceled} event.
     */
    function _cancel(uint256 proposalId) internal returns (uint256) {
        // Can cancel in any state other than Canceled, Expired, or Executed.
        // forgefmt: disable-next-item
        _validateStateBitmap(
            proposalId,
            ALL_PROPOSAL_STATES_BITMAP ^
                _encodeStateBitmap(IGovernorBase.ProposalState.Canceled) ^
                _encodeStateBitmap(IGovernorBase.ProposalState.Expired) ^
                _encodeStateBitmap(IGovernorBase.ProposalState.Executed)
        );

        ProposalsStorage storage $ = _getProposalsStorage();
        IGovernorBase.ProposalCore storage proposal = $._proposals[proposalId];
        proposal.canceled = true;

        // Cancel the op if the proposal has been queued (will revert if it cannot be canceled)
        if (proposal.queued) {
            uint256 opNonce = $._proposalOpNonces[proposalId];
            _executor().cancelOperation(opNonce);
        }

        emit IGovernorBase.ProposalCanceled(proposalId);

        return proposalId;
    }

    /// @dev Get both values at once to optimize gas where applicable
    function _getVotingDelayAndPeriod() internal view returns (uint256 votingDelay_, uint256 votingPeriod_) {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        votingDelay_ = $._votingDelay;
        votingPeriod_ = $._votingPeriod;
    }

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
    function _encodeStateBitmap(IGovernorBase.ProposalState proposalState) internal pure returns (bytes32) {
        return bytes32(1 << uint8(proposalState));
    }

    /**
     * @dev Check that the current state of a proposal matches the requirements described by the `allowedStates` bitmap.
     * This bitmap should be built using `_encodeStateBitmap`.
     *
     * If requirements are not met, reverts with a {GovernorUnexpectedProposalState} error.
     */
    function _validateStateBitmap(
        uint256 proposalId,
        bytes32 allowedStates
    )
        internal
        view
        returns (IGovernorBase.ProposalState)
    {
        IGovernorBase.ProposalState currentState = state(proposalId);
        if (_encodeStateBitmap(currentState) & allowedStates == bytes32(0)) {
            revert IGovernorBase.GovernorUnexpectedProposalState(proposalId, currentState, allowedStates);
        }
        return currentState;
    }

    /**
     * @dev Gas-optimized validation. Assumes that the array lengths have already been checked
     */
    function _validateCalldataSignatures(bytes[] calldata calldatas, string[] memory signatures) internal pure {
        assembly ("memory-safe") {
            let i := 0
            for {} lt(i, calldatas.length) { i := add(i, 0x01) } {
                // If the calldata item byte length is greater than zero, check the signature
                let calldataItemOffset := add(calldatas.offset, calldataload(add(calldatas.offset, mul(i, 0x20))))
                if gt(calldataload(calldataItemOffset), 0) {
                    // Load the function selector from the currnet calldata item (shift right 28 * 8 = 224 bits)
                    let selector := shr(224, calldataload(add(0x20, calldataItemOffset)))

                    let signature := mload(add(0x20, add(signatures, mul(i, 0x20))))
                    let signatureLength := mload(signature)
                    let signatureHash := keccak256(add(signature, 0x20), signatureLength)

                    if iszero(eq(selector, shr(224, signatureHash))) {
                        // `GovernorInvalidActionSignature(uint256)`
                        mstore(0, 0xb8e4a11400000000000000000000000000000000000000000000000000000000)
                        mstore(0x04, i) // index
                        revert(0, 0x24)
                    }
                }
            }
        }
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
    )
        internal
        pure
        returns (bool)
    {
        uint256 len;
        assembly ("memory-safe") {
            len := description.length
        }

        // Length is too short to contain a valid proposer suffix
        if (len < 52) {
            return true;
        }

        // Extract what would be the `#proposer=0x` marker beginning the suffix
        bytes12 marker;
        assembly ("memory-safe") {
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
            unchecked {
                ++i;
            }
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
     * @dev Defaults to no params.
     */
    function _defaultParams() internal pure returns (bytes memory) {
        return "";
    }
}
