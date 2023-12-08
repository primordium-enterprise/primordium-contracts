// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title A wrapper library for "SafeTransferLib.sol" with common operations based on ERC20 vs ETH operations.
 * @notice Assumes asset is ETH if the token is address(0)
 * @author Ben Jett - @BCJdevelopment
 */
library ERC20Utils {
    using SafeTransferLib for IERC20;
    using SafeTransferLib for address;

    error InvalidMsgValue(uint256 expected, uint256 actual);

    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        if (address(token) == address(0)) {
            to.forceSafeTransferETH(amount);
        } else {
            token.safeTransfer(to, amount);
        }
    }

    function safeReceive(IERC20 token, address from, uint256 amount) internal {
        if (address(token) == address(0)) {
            if (msg.value != amount) {
                revert InvalidMsgValue(amount, msg.value);
            }
        } else {
            if (msg.value > 0) {
                revert InvalidMsgValue(0, msg.value);
            }
            token.safeTransferFrom(from, address(this), amount);
        }
    }

}