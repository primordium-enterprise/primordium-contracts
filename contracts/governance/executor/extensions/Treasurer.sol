// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../../token/extensions/VotesProvisioner.sol";
import "../Executor.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract Treasurer is Executor {

    VotesProvisioner internal immutable _votes;
    IERC20 internal immutable _baseAsset;

    constructor(
        VotesProvisioner votes_
    ) {
        _votes = votes_;
        _baseAsset = IERC20(votes_.baseAsset());
    }

    function votes() public view returns(address) {
        return address(_votes);
    }

    modifier onlyVotes() {
        require(_msgSender() == address(_votes), "Treasurer: call must come from the _votes contract.");
        _;
    }

    function baseAsset() public view returns (address) {
        return address(_baseAsset);
    }

    /**
     * @notice Returns the current DAO balance of the base asset in the treasury.
     */
    // function treasuryBalance() public view returns (uint256) {
    //     return _balance();
    // }

    /**
     * @dev An internal function that must be overridden to properly return the DAO.
     */
    // function _balance() internal view virtual returns (uint256);

    function registerDeposit(uint256 depositAmount) public payable virtual onlyVotes {
        _registerDeposit(depositAmount);
    }

    /// @dev Can override and call super._registerDeposit for additional checks/functionality depending on baseAsset used
    function _registerDeposit(uint256 depositAmount) internal virtual {
        require(depositAmount > 0, "Treasurer: Deposit amount must be greater than zero");
    }

    function processWithdrawal(address receiver, uint256 withdrawAmount) public virtual onlyVotes {
        _processWithdrawal(receiver, withdrawAmount);
    }

    /// @dev Must override to implement the actual transfer functionality depending on what baseAsset is used
    function _processWithdrawal(address receiver, uint256 withdrawAmount) internal virtual { }

}