// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IDistributor} from "../../interfaces/IDistributor.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Treasurer} from "../../base/Treasurer.sol";

contract Distributor is IDistributor, UUPSUpgradeable, OwnableUpgradeable, ERC165 {
    using Address for address;

    struct Distribution {
        uint48 clockStartTime;
        uint208 cachedTotalSupply;
        uint128 balance;
        uint128 claimedBalance;
        uint256 reclaimableAt;
        mapping(address => bool) hasClaimed;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {
        bytes memory data = abi.encodeCall(Treasurer.authorizeDistributorImplementation, (newImplementation));
        owner().functionCall(data);
    }



}