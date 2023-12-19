// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {IERC20Snapshots} from "contracts/shares/interfaces/IERC20Snapshots.sol";

interface IGovernorToken is IERC20Snapshots, IERC5805 {}
