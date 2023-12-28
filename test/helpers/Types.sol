// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

struct Users {
    // Address authorized to submit proposals
    address payable proposer;
    // Address authorized to cancel proposals
    address payable canceler;
    // Address that deposits on behalf of `sharesGiftReceiver`
    address payable sharesGifter;
    // Address that receives shares on behalf of `sharesGifter`
    address payable sharesGiftReceiver;
    // Impartial address
    address payable gwart;
    // Malicious address
    address payable maliciousUser;
}