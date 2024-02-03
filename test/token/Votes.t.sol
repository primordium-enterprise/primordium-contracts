// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract VotesTest is BaseTest {
    uint8 internal constant _TIMEPOINTS_MAX_GAP = 64;

    function setUp() public virtual override {
        super.setUp();
    }

    function test_Delegate(address account, uint16 amount, address delegatee1, address delegatee2) public {
        vm.assume(account != address(0) && account != delegatee1 && account != delegatee2 && delegatee1 != delegatee2);

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

    function test_DelegateBySig(address sender, uint16 amount, address delegatee, uint48 expiry) public {
        vm.assume(sender != address(0) && delegatee != address(0) && amount != 0);

        address owner = users.signer.addr;

        // Give owner tokens to delegate
        _mintShares(owner, amount);

        (, string memory name, string memory version,,,,) = token.eip712Domain();
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

    // Creates list of timepoints in incrementing order
    function _prepareTimepoints(uint48[48] memory timepoints) internal pure {
        uint48 lastTimepoint = 1;
        for (uint256 i = 0; i < timepoints.length; i++) {
            uint48 timepoint = uint48(_bound(timepoints[i], lastTimepoint, lastTimepoint + _TIMEPOINTS_MAX_GAP));
            timepoints[i] = timepoint;
            lastTimepoint = timepoint;
        }
    }

    function test_GetPastVotes(uint48[48] memory timepoints, uint16 amount) public {
        vm.assume(amount > 0);

        _prepareTimepoints(timepoints);

        address account = users.gwart;

        // Mint tokens to account
        _mintShares(account, amount);

        // At each timepoint, delegate to a different delegatee
        address[] memory delegatees = new address[](timepoints.length);
        for (uint256 i = 0; i < timepoints.length; i++) {
            vm.roll(timepoints[i]);
            address delegatee = address(uint160(i + 1));
            delegatees[i] = delegatee;

            vm.prank(account);
            token.delegate(delegatee);
        }

        vm.roll(timepoints[timepoints.length - 1] + 2);

        // Assert that the past votes for each delegatee is correct
        for (uint256 i = 0; i < timepoints.length - 1; i++) {
            address delegatee = delegatees[i];
            uint256 timepoint = timepoints[i] - 1;
            uint256 nextTimepoint = timepoints[i + 1];

            uint256 expectedVotes = 0;
            assertEq(expectedVotes, token.getPastVotes(delegatee, timepoint));

            timepoint += 1;
            expectedVotes = amount;
            if (nextTimepoint == timepoint || delegatee == address(0)) {
                expectedVotes = 0;
            }
            assertEq(expectedVotes, token.getPastVotes(delegatee, timepoint));

            timepoint += 1;
            if (nextTimepoint == timepoint || delegatee == address(0)) {
                expectedVotes = 0;
            }
            assertEq(expectedVotes, token.getPastVotes(delegatee, timepoint));
        }
    }

    function test_TransferVotes(
        address accountDelegatee,
        uint16 amount,
        address receiver,
        address receiverDelegatee
    )
        public
    {
        vm.assume(amount > 0 && receiver != address(0) && accountDelegatee != receiver);

        address account = users.gwart;

        _mintShares(account, amount);

        vm.prank(account);
        token.delegate(accountDelegatee);

        assertEq(0, token.getVotes(account));
        assertEq(accountDelegatee == address(0) ? 0 : amount, token.getVotes(accountDelegatee));

        // Delegate receiver
        vm.prank(receiver);
        token.delegate(receiverDelegatee);

        assertEq(0, token.getVotes(receiver));
        assertEq(0, token.getVotes(receiverDelegatee));

        // Transfer tokens from account to receiver
        vm.prank(account);
        token.transfer(receiver, amount);

        assertEq(0, token.getVotes(account));
        assertEq(0, token.getVotes(accountDelegatee));
        assertEq(receiver == receiverDelegatee ? amount : 0, token.getVotes(receiver));
        assertEq(receiverDelegatee == address(0) ? 0 : amount, token.getVotes(receiverDelegatee));
    }

    function test_MultipleDelegates() public {
        uint256 bobShares = 100;
        uint256 aliceShares = 200;
        uint256 gwartShares = 300;

        uint8[3] memory timepoints = [10, 20, 30];
        vm.roll(timepoints[0]);

        vm.startPrank(token.owner());
        token.mint(users.bob, bobShares);
        token.mint(users.alice, aliceShares);
        token.mint(users.gwart, gwartShares);
        vm.stopPrank();

        // First, bob delegates to gwart
        vm.prank(users.bob);
        token.delegate(users.gwart);

        assertEq(0, token.getVotes(users.bob));
        assertEq(bobShares, token.getVotes(users.gwart));

        // Roll to next timepoint, alice delegates to gwart
        vm.roll(timepoints[1]);
        vm.prank(users.alice);
        token.delegate(users.gwart);

        assertEq(0, token.getVotes(users.bob));
        assertEq(0, token.getVotes(users.alice));
        assertEq(bobShares + aliceShares, token.getVotes(users.gwart));

        // Roll to final timepoint, gwart delegates to self
        vm.roll(timepoints[2]);
        vm.prank(users.gwart);
        token.delegate(users.gwart);

        assertEq(0, token.getVotes(users.bob));
        assertEq(0, token.getVotes(users.alice));
        assertEq(bobShares + aliceShares + gwartShares, token.getVotes(users.gwart));

        // Roll forward one more block, check past votes for each timepoint
        vm.roll(timepoints[2] + 1);
        uint256 i = 0;
        uint256[4] memory gwartExpectedShares =
            [0, bobShares, bobShares + aliceShares, bobShares + aliceShares + gwartShares];
        for (uint256 t = 0;;) {
            assertEq(gwartExpectedShares[i], token.getPastVotes(users.gwart, t));
            t++;
            if (t > timepoints[2]) {
                break;
            } else if (t == timepoints[i]) {
                i++;
            }
        }
    }
}
