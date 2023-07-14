// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../../token/extensions/VotesProvisioner.sol";
import "../Executor.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract Treasurer is Executor {

    VotesProvisioner internal immutable _votes;

    constructor(
        VotesProvisioner votes_
    ) {
        _votes = votes_;
    }

    function votes() public view returns(address) {
        return address(_votes);
    }

    modifier onlyVotes() {
        require(_msgSender() == address(_votes), "Treasurer: call must come from the _votes contract.");
        _;
    }

    function registerDepositERC20(uint256 depositAmount) public virtual onlyVotes {
        _registerDeposit(depositAmount);
    }

    function registerDepositETH(uint256 depositAmount) public payable virtual onlyVotes {
        require(msg.value == depositAmount, "Treasurer: depositEth mismatching depositAmount and msg.value");
        _registerDeposit(depositAmount);
    }

    function _registerDeposit(uint256 depositAmount) private {
        // NEED TO IMPLEMENT BALANCE CHECKS
    }

    function processWithdrawalERC20(IERC20 baseAsset, address receiver, uint256 withdrawAmount) public virtual onlyVotes {
        SafeERC20.safeTransfer(baseAsset, receiver, withdrawAmount);
        _processWithdrawal(withdrawAmount);
    }

    function processWithdrawalETH(address receiver, uint256 withdrawAmount) public virtual onlyVotes {
        (bool success,) = receiver.call{value: withdrawAmount}("");
        if (!success) revert("Treasurer: Failed to process ETH withdrawal.");
    }

    function _processWithdrawal(uint256 withdrawAmount) private {
        // NEED TO IMPLEMENT BALANCE CHECKS
    }

}