// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title Wrapper around OpenZeppelin ERC165Checker library that throws a common error for invalid interface support.
 * @author Ben Jett - @BCJdevelopment
 */
library ERC165Verifier {
    using ERC165Checker for address;

    error InvalidERC165InterfaceSupport(address _contract, bytes4 missingInterfaceId);

    function checkInterface(address _contract, bytes4 interfaceId) internal view {
        _checkIERC165Support(_contract);
        if (!_contract.supportsInterface(interfaceId)) {
            revert InvalidERC165InterfaceSupport(_contract, interfaceId);
        }
    }

    function checkInterfaces(address _contract, bytes4[2] memory interfaceIds) internal view {
        _checkIERC165Support(_contract);
        for (uint256 i = 0; i < interfaceIds.length; ++i) {
            if (!_contract.supportsERC165InterfaceUnchecked(interfaceIds[i])) {
                revert InvalidERC165InterfaceSupport(_contract, interfaceIds[i]);
            }
        }
    }

    function checkInterfaces(address _contract, bytes4[3] memory interfaceIds) internal view {
        _checkIERC165Support(_contract);
        for (uint256 i = 0; i < interfaceIds.length; ++i) {
            if (!_contract.supportsERC165InterfaceUnchecked(interfaceIds[i])) {
                revert InvalidERC165InterfaceSupport(_contract, interfaceIds[i]);
            }
        }
    }

    function checkInterfaces(address _contract, bytes4[4] memory interfaceIds) internal view {
        _checkIERC165Support(_contract);
        for (uint256 i = 0; i < interfaceIds.length; ++i) {
            if (!_contract.supportsERC165InterfaceUnchecked(interfaceIds[i])) {
                revert InvalidERC165InterfaceSupport(_contract, interfaceIds[i]);
            }
        }
    }

    function checkInterfaces(address _contract, bytes4[5] memory interfaceIds) internal view {
        _checkIERC165Support(_contract);
        for (uint256 i = 0; i < interfaceIds.length; ++i) {
            if (!_contract.supportsERC165InterfaceUnchecked(interfaceIds[i])) {
                revert InvalidERC165InterfaceSupport(_contract, interfaceIds[i]);
            }
        }
    }

    function _checkIERC165Support(address _contract) private view {
        if (!_contract.supportsERC165()) {
            revert InvalidERC165InterfaceSupport(_contract, type(IERC165).interfaceId);
        }
    }
}
