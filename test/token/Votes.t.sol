// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract VotesTest is BaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_Delegate(address account, uint16 amount, address delegatee1, address delegatee2) public {
        vm.assume(account != address(0));

        vm.prank(token.owner());
        token.mint(account, amount);

        // No delegation = no votes
        assertEq(address(0), token.delegates(account));
        assertEq(0, token.getVotes(account));
        assertEq(0, token.getVotes(delegatee1));
        assertEq(0, token.getVotes(delegatee2));

       uint256 expectedVotes = delegatee1 == address(0) ? 0 : amount;

        // Delegate to delegatee1
        vm.prank(account);
        vm.expectEmit(true, true, true, true, address(token));
        emit IVotes.DelegateChanged(account, address(0), delegatee1);
        if (amount > 0) {
            if (delegatee1 != address(0)) {
                vm.expectEmit(true, false, false, true, address(token));
                emit IVotes.DelegateVotesChanged(delegatee1, 0, amount);
            }
        }
        token.delegate(delegatee1);

        assertEq(delegatee1, token.delegates(account));
        assertEq(0, token.getVotes(account));
        assertEq(expectedVotes, token.getVotes(delegatee1));

        // Change delegates to delegatee2
        expectedVotes = delegatee2 == address(0) ? 0 : amount;

        vm.prank(account);
        vm.expectEmit(true, true, true, true, address(token));
        emit IVotes.DelegateChanged(account, delegatee1, delegatee2);
        if (delegatee1 != delegatee2 && amount > 0) {
            if (delegatee1 != address(0)) {
                vm.expectEmit(true, false, false, true, address(token));
                emit IVotes.DelegateVotesChanged(delegatee1, amount, 0);
            }
            if (delegatee2 != address(0)) {
                vm.expectEmit(true, false, false, true, address(token));
                emit IVotes.DelegateVotesChanged(delegatee2, 0, amount);
            }
        }
        token.delegate(delegatee2);

        assertEq(delegatee2, token.delegates(account));
        assertEq(0, token.getVotes(delegatee1));
        assertEq(expectedVotes, token.getVotes(delegatee2));
    }

    function test_DelegateBySig(
        address sender,
        uint16 amount,
        address delegatee,
        uint48 expiry
    ) public {
        vm.assume(sender != address(0) && delegatee != address(0) && amount != 0);

        address owner = users.signer.addr;

        // Give owner tokens to delegate
        vm.prank(token.owner());
        token.mint(owner, amount);

        (,string memory name, string memory version,,,,) = token.eip712Domain();
        uint256 nonce = token.nonces(owner);

        bytes32 DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 dataHash = _hashTypedData(_buildEIP712DomainSeparator(name, version, address(token)), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signer.privateKey, dataHash);

        // Create snapshot to test again with both signature options
        uint256 snapshot = vm.snapshot();

        address expectedDelegates = delegatee;
        uint256 expectedVotes = amount;
        uint256 expectedNonce = nonce + 1;

        bytes memory revertBytes;
        if (block.timestamp > expiry) {
            revertBytes = abi.encodeWithSelector(IVotes.VotesExpiredSignature.selector, expiry);
            vm.expectRevert(revertBytes);
        }

        if (revertBytes.length > 0) {
            expectedDelegates = address(0);
            expectedVotes = 0;
            expectedNonce = nonce;
        }

        vm.prank(sender);
        token.delegateBySig(delegatee, nonce, expiry, v, r, s);

        assertEq(expectedDelegates, token.delegates(owner));
        assertEq(expectedVotes, token.getVotes(delegatee));
        assertEq(expectedNonce, token.nonces(owner));

        // Revert to snapshot, test again with packed signature
        vm.revertTo(snapshot);
        assertEq(0, token.getVotes(delegatee));

        bytes memory signature = abi.encodePacked(r, s, v);

        if (revertBytes.length > 0) {
            vm.expectRevert(revertBytes);
        }

        vm.prank(sender);
        token.delegateBySig(delegatee, owner, expiry, signature);

        assertEq(expectedDelegates, token.delegates(owner));
        assertEq(expectedVotes, token.getVotes(delegatee));
        assertEq(expectedNonce, token.nonces(owner));
    }
}