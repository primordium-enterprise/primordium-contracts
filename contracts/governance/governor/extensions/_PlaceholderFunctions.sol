// TEMPORARY CONTRACT, NEED TO INTEGRATE THESE FUNCTIONS IN MAIN CONTRACTS

pragma solidity ^0.8.0;

import "../Governor.sol";

abstract contract _PlaceholderFunctions is Governor {

    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal {}

    function _quorumReached(uint256 proposalId) internal view override returns(bool) { return false; }

    function _voteSucceeded(uint256 proposalId) internal view override returns(bool) { return false; }

    function quorum(
        uint256 timepoint
    ) public view virtual override returns (uint256) { return timepoint; }

    function hasVoted(
        uint256 proposalId,
        address account
    ) public view virtual override returns (bool) { return true; }

    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory params
    ) internal virtual override {}


}