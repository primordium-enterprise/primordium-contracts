// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {ProposalTestUtils} from "test/helpers/ProposalTestUtils.sol";
import {IProposals} from "src/governor/interfaces/IProposals.sol";
import {IProposalVoting} from "src/governor/interfaces/IProposalVoting.sol";

contract ProposalVotingTest is BaseTest, ProposalTestUtils {
    uint8 maxVoteType = uint8(type(IProposalVoting.VoteType).max);

    function setUp() public virtual override {
        super.setUp();
        governor.harnessFoundGovernor();
    }

    function _setupVotes(
        uint16[3] memory shareAmounts,
        uint8[3] memory voteTypes
    )
        internal
        returns (address payable[3] memory accounts, uint256 proposalId, uint256[3] memory expectedVotes)
    {
        accounts = [users.gwart, users.bob, users.alice];
        for (uint256 i = 0; i < accounts.length; i++) {
            _mintSharesForVoting(accounts[i], shareAmounts[i]);
            uint8 voteType = voteTypes[i] % (maxVoteType + 2);
            voteTypes[i] = voteType;
            if (voteType <= maxVoteType) {
                expectedVotes[voteType] += shareAmounts[i];
            }
        }

        proposalId = _mockPropose(users.proposer);
        vm.roll(governor.proposalSnapshot(proposalId) + 1);
    }

    function _checkVotes(uint256 proposalId, uint256[3] memory expectedVotes) internal {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(againstVotes, expectedVotes[0], "Invalid againstVotes");
        assertEq(forVotes, expectedVotes[1], "Invalid forVotes");
        assertEq(abstainVotes, expectedVotes[2], "Invalid abstainVotes");
    }

    function test_Fuzz_CastVote(uint16[3] memory shareAmounts, uint8[3] memory voteTypes) public {
        (address payable[3] memory accounts, uint256 proposalId, uint256[3] memory expectedVotes) =
            _setupVotes(shareAmounts, voteTypes);

        for (uint256 i = 0; i < accounts.length; i++) {
            if (voteTypes[i] > maxVoteType) {
                vm.expectRevert(IProposalVoting.GovernorInvalidVoteValue.selector);
            } else {
                vm.expectEmit(true, true, false, true, address(governor));
                emit IProposalVoting.VoteCast(accounts[i], proposalId, voteTypes[i], shareAmounts[i], "");
            }
            vm.prank(accounts[i]);
            governor.castVote(proposalId, voteTypes[i]);
        }

        _checkVotes(proposalId, expectedVotes);
    }

    function test_Fuzz_CastVoteWithReason(
        uint16[3] memory shareAmounts,
        uint8[3] memory voteTypes,
        string[3] memory reasons
    )
        public
    {
        (address payable[3] memory accounts, uint256 proposalId, uint256[3] memory expectedVotes) =
            _setupVotes(shareAmounts, voteTypes);

        for (uint256 i = 0; i < accounts.length; i++) {
            if (voteTypes[i] > maxVoteType) {
                vm.expectRevert(IProposalVoting.GovernorInvalidVoteValue.selector);
            } else {
                vm.expectEmit(true, true, false, true, address(governor));
                emit IProposalVoting.VoteCast(accounts[i], proposalId, voteTypes[i], shareAmounts[i], reasons[i]);
            }
            vm.prank(accounts[i]);
            governor.castVoteWithReason(proposalId, voteTypes[i], reasons[i]);
        }

        _checkVotes(proposalId, expectedVotes);
    }

    function test_Fuzz_CastVoteWithReasonAndParams(
        uint16[3] memory shareAmounts,
        uint8[3] memory voteTypes,
        string[3] memory reasons,
        bytes[3] memory params
    )
        public
    {
        (address payable[3] memory accounts, uint256 proposalId, uint256[3] memory expectedVotes) =
            _setupVotes(shareAmounts, voteTypes);

        for (uint256 i = 0; i < accounts.length; i++) {
            if (voteTypes[i] > maxVoteType) {
                vm.expectRevert(IProposalVoting.GovernorInvalidVoteValue.selector);
            } else {
                vm.expectEmit(true, true, false, true, address(governor));
                if (params[i].length > 0) {
                    emit IProposalVoting.VoteCastWithParams(
                        accounts[i], proposalId, voteTypes[i], shareAmounts[i], reasons[i], params[i]
                    );
                } else {
                    emit IProposalVoting.VoteCast(accounts[i], proposalId, voteTypes[i], shareAmounts[i], reasons[i]);
                }
            }
            vm.prank(accounts[i]);
            governor.castVoteWithReasonAndParams(proposalId, voteTypes[i], reasons[i], params[i]);
        }

        _checkVotes(proposalId, expectedVotes);
    }

    function test_Fuzz_CastVoteBySig(uint16 shareAmount, uint8 voteType, address sender) public {
        vm.assume(sender != address(0));
        voteType = voteType % (maxVoteType + 2);

        address voter = users.signer.addr;

        _mintSharesForVoting(voter, shareAmount);
        vm.roll(governor.clock() + 1);

        uint256 proposalId = _mockPropose(users.proposer);
        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        (, string memory name, string memory version,,,,) = governor.eip712Domain();
        uint256 nonce = governor.nonces(voter);

        bytes32 BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support,address voter,uint256 nonce)");

        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, voteType, voter, nonce));
        bytes32 dataHash = _hashTypedData(_buildEIP712DomainSeparator(name, version, address(governor)), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signer.privateKey, dataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256[3] memory expectedVotes;
        if (voteType > maxVoteType) {
            vm.expectRevert(IProposalVoting.GovernorInvalidVoteValue.selector);
        } else {
            expectedVotes[voteType] += shareAmount;
            vm.expectEmit(true, true, false, true);
            emit IProposalVoting.VoteCast(voter, proposalId, voteType, shareAmount, "");
        }
        vm.prank(sender);
        governor.castVoteBySig(proposalId, voteType, voter, signature);

        _checkVotes(proposalId, expectedVotes);
    }

    function test_Fuzz_CastVoteWithReasonAndParamsBySig(
        uint16 shareAmount,
        uint8 voteType,
        string memory reason,
        bytes memory params,
        address sender
    )
        public
    {
        vm.assume(sender != address(0));
        voteType = voteType % (maxVoteType + 2);

        address voter = users.signer.addr;

        _mintSharesForVoting(voter, shareAmount);
        vm.roll(governor.clock() + 1);

        uint256 proposalId = _mockPropose(users.proposer);
        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        (, string memory name, string memory version,,,,) = governor.eip712Domain();
        uint256 nonce = governor.nonces(voter);

        bytes32 EXTENDED_BALLOT_TYPEHASH = keccak256(
            "ExtendedBallot(uint256 proposalId,uint8 support,address voter,uint256 nonce,string reason,bytes params)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                EXTENDED_BALLOT_TYPEHASH,
                proposalId,
                voteType,
                voter,
                nonce,
                keccak256(bytes(reason)),
                keccak256(params)
            )
        );
        bytes32 dataHash = _hashTypedData(_buildEIP712DomainSeparator(name, version, address(governor)), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signer.privateKey, dataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256[3] memory expectedVotes;
        if (voteType > maxVoteType) {
            vm.expectRevert(IProposalVoting.GovernorInvalidVoteValue.selector);
        } else {
            expectedVotes[voteType] += shareAmount;
            vm.expectEmit(true, true, false, true);
            if (params.length > 0) {
                emit IProposalVoting.VoteCastWithParams(voter, proposalId, voteType, shareAmount, reason, params);
            } else {
                emit IProposalVoting.VoteCast(voter, proposalId, voteType, shareAmount, reason);
            }
        }
        vm.prank(sender);
        governor.castVoteWithReasonAndParamsBySig(proposalId, voteType, voter, reason, params, signature);

        _checkVotes(proposalId, expectedVotes);
    }

    function test_Fuzz_QuorumBps(uint16 quorumBps, uint64[3] memory voteAmounts) public {
        while (quorumBps > MAX_BPS) {
            quorumBps = quorumBps / 2;
        }
        governor.harnessSetQuorumBps(quorumBps);

        address payable[3] memory voters = [users.gwart, users.bob, users.alice];
        for (uint256 i = 0; i < voters.length; i++) {
            _mintSharesForVoting(voters[i], voteAmounts[i]);
        }
        vm.roll(governor.clock() + 1);

        uint256 proposalId = _mockPropose(users.proposer);
        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        for (uint256 i = 0; i < voters.length; i++) {
            vm.prank(voters[i]);
            governor.castVote(proposalId, uint8(i));
        }

        // Abstain counts towards a quorum
        bool expectedQuorumReached =
            uint256(voteAmounts[1]) + uint256(voteAmounts[2]) >= quorumBps * token.totalSupply() / MAX_BPS;
        assertEq(expectedQuorumReached, governor.exposeQuorumReached(proposalId));
    }
}
