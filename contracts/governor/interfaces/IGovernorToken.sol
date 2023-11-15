// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {IERC20Checkpoints} from "contracts/shares/interfaces/IERC20Checkpoints.sol";

interface IGovernorToken is IERC20Checkpoints, IERC5805 {

    function getPastTotalSupply(uint256 timepoint) external view override(IERC20Checkpoints, IVotes) returns (uint256);

}