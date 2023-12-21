// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v4.8.0) (IGovernor.sol)

pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IGovernorToken} from "src/governor/interfaces/IGovernorToken.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

/**
 * @dev Interface of the {GovernorBase} core.
 */
interface IGovernorBase is IERC165, IERC6372 {

    event GovernorBaseInitialized(
        string name,
        string version,
        address timelockAvatar,
        address token,
        uint256 governanceCanBeginAt,
        uint256 governanceThresholdBps,
        bool isFounded
    );

    /**
     * @dev Emitted when governance is initialized.
     */
    event GovernanceInitialized(uint256 proposalId);
    error GovernanceCannotInitializeYet(uint256 governanceCanBeginAt);
    error GovernanceThresholdIsNotMet(uint256 governanceThreshold, uint256 voteSupply);
    error GovernanceInitializationActionRequired();
    error InvalidProposalIdForInitialization(uint256 expectedProposalId, uint256 providedProposalId);
    error GovernanceAlreadyInitialized();
    error UnknownProposalId(uint256 proposalId);
    error GovernorClockMustMatchTokenClock();
    error GovernorRestrictedProposer(address proposer);
    error UnauthorizedToSubmitProposal(address proposer);
    error UnauthorizedToCancelProposal();
    error NotReadyForGovernance();
    error InvalidActionSignature(uint256 index);
    error InvalidActionsForProposal();
    error TooLateToCancelProposal();
    error GovernorInvalidSignature(address voter);

    /**
     * @dev Name of the governor instance (used in building the ERC712 domain separator).
     */
    function name() external view returns (string memory);

    /**
     * @dev Version of the governor instance (used in building the ERC712 domain separator). Default: "1"
     */
    function version() external view returns (string memory);

    /**
     * @dev A description of the possible `support` values for {castVote} and the way these votes are counted, meant to
     * be consumed by UIs to show correct vote options and interpret the results. The string is a URL-encoded sequence
     * of key-value pairs that each describe one aspect, for example `support=bravo&quorum=for,abstain`.
     *
     * There are 2 standard keys: `support` and `quorum`.
     *
     * - `support=bravo` refers to the vote options 0 = Against, 1 = For, 2 = Abstain, as in `GovernorBravo`.
     * - `quorum=bravo` means that only For votes are counted towards quorum.
     * - `quorum=for,abstain` means that both For and Abstain votes are counted towards quorum.
     *
     * If a counting module makes use of encoded `params`, it should  include this under a `params` key with a unique
     * name that describes the behavior. For example:
     *
     * - `params=fractional` might refer to a scheme where votes are divided fractionally between for/against/abstain.
     * - `params=erc721` might refer to a scheme where specific NFTs are delegated to vote.
     *
     * NOTE: The string can be decoded by the standard
     * https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams[`URLSearchParams`]
     * JavaScript class.
     */
    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() external view returns (string memory);

    /**
     * @notice Returns the address of the token used for vote counting.
     */
    function token() external view returns (IGovernorToken);

    /**
     * Returns the timestamp that governance can be initiated after.
     */
    function governanceCanBeginAt() external view returns (uint256 _governanceCanBeginAt);

    /**
     * Returns the amount of the vote token's initial max supply that needs to be in circulation (via deposits) before
     * governance can be initiated. Returns zero if governance is already active.
     */
    function governanceThreshold() external view returns (uint256 _governanceThreshold);

    /**
     * @notice Initializes governance. This function is the only allowable proposal action on the Governor until it has
     * been successfully executed through the proposal process.
     * @dev The governance threshold of tokens must be allocated before a proposal can be submitted. Additionally,
     * the governance threshold of tokens must still be met at the end of the proposal's voting period to successfully
     * execute this action, or else the action will revert on execution (even if the proposal vote succeeded).
     * @param proposalId This MUST be equal to the proposalId of the proposal creating the action, or creating the
     * proposal will not work. The proposalId can be predicted by taking the current proposalCount() and adding one.
     */
    function initializeGovernance(uint256 proposalId) external;

    /**
     * @notice Returns true if the Governor has been initialized, meaning any proposal actions are available for
     * submission and execution.
     */
    function isGovernanceActive() external view returns (bool);

    /**
     * @notice Voting power of an `account` at a specific `timepoint` (which is according to the clock mode - see
     * EIP6372).
     */
    function getVotes(address account, uint256 timepoint) external view returns (uint256);

    /**
     * @notice Voting power of an `account` at a specific `timepoint` given additional encoded parameters.
     */
    function getVotesWithParams(
        address account,
        uint256 timepoint,
        bytes memory params
    )
        external
        view
        returns (uint256);

}
