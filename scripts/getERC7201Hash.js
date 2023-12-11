#!/usr/bin/env node

const path = require("path");
const {
    id,
    keccak256,
    toBeHex
} = require("ethers");

function getERC7201Hash(str) {
    let finalHash = keccak256(toBeHex(BigInt(id(str)) - 1n, 32));
    // Set to multiple of 32 by zeroing the last byte
    let finalHashTo32Multiple = `${finalHash.slice(0, finalHash.length - 2)}00`;
    return finalHashTo32Multiple;
}

if (process.argv[1].indexOf(path.basename(__filename)) > -1) {
    console.log(getERC7201Hash(process.argv[2]));
}

module.exports = getERC7201Hash;