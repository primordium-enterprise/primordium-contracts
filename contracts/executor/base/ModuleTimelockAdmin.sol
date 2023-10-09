// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import {ExecutorBaseCallOnly} from "./ExecutorBaseCallOnly.sol";
import {IAvatar} from "../interfaces/IAvatar.sol";

/**
 * @title Module Timelock Admin implements a timelock control on all call executions for the Executor.
 *
 * @author Ben Jett @BCJdevelopment
 */
abstract contract ModuleTimelockAdmin is ExecutorBaseCallOnly, IAvatar {



}