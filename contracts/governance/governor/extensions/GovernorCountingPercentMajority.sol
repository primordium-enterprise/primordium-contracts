// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "./GovernorCountingSimple.sol";

abstract contract GovernorCountingPercentMajority is GovernorCountingSimple {

    uint256 constant private MAX_PERCENT = 100;

    uint256 private _percentMajority;
    uint256 public MIN_PERCENT_MAJORITY = 50;
    uint256 public MAX_PERCENT_MAJORITY = 66;
    event PercentMajoritySet(uint256 oldPercentMajority, uint256 newPercentMajority);

    constructor(uint256 percentMajority_) {
        _setPercentMajority(percentMajority_);
    }

    function setPercentMajority(uint256 newPercentMajority) public virtual onlyGovernance {
        _setPercentMajority(newPercentMajority);
    }

    function _setPercentMajority(uint256 newPercentMajority) internal virtual {
        require(
            newPercentMajority >= MIN_PERCENT_MAJORITY &&
            newPercentMajority <= MAX_PERCENT_MAJORITY
        );
        emit PercentMajoritySet(_percentMajority, newPercentMajority);
    }
}