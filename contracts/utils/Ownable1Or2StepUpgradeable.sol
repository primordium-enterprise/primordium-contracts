// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

abstract contract Ownable1Or2StepUpgradeable is Ownable2StepUpgradeable {

    function forceTransferOwnership(address newOwner) public virtual onlyOwner {
        _transferOwnership(newOwner);
    }

}