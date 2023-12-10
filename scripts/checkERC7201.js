#!/usr/bin/env node

const glob = require("glob");
const fs = require("fs/promises");
const path = require("path");
const chalk = require("chalk");
const {
    id,
    keccak256
} = require("ethers");

const contracts = glob.sync('contracts/**/*.sol');

// Matches two groups: group 1 is the string to hash, group two is the hardcodedHash
// const regex = new RegExp(/@custom:storage-location\s+erc7201:(\S*)(?:.|\s)*?bytes32\s.*constant(?:.|\s)*?=\s*(0x[0-9a-fA-F]{64});/gm);

const run = async () => {

    const ops = [];

    contracts.forEach(contract => {
        ops.push(
            fs.readFile(path.join(process.cwd(), contract), 'utf-8')
            .then((contents) => {
                const matches = Array.from(contents.matchAll(/(?<=@custom:storage-location\serc7201:)\S*/gm));
                for (let j = 0; j < matches.length; j++) {
                    let match = matches[j];
                    let hardcodedHashMatch = match.input.substring(match.index)
                        .match(/bytes32\s.*constant(?:.|\s)*?(0x[0-9a-fA-F]{64});/gm);
                    if (hardcodedHashMatch != null) {
                        hhm = hardcodedHashMatch[0]
                        const hardcodedHash = hhm.substring(hhm.length - 67, hhm.length - 1);
                        console.log(hardcodedHash);

                        console.log(match[0]);
                        let wordHash = id(match[0]);
                        let wordHashAsInt = BigInt(wordHash) - BigInt(1);
                        let finalHash = keccak256(`0x${wordHashAsInt.toString(16)}`);
                        console.log(finalHash);
                        console.log(`${finalHash.slice(0, finalHash.length - 2)}00`);

                        if (`${finalHash.slice(0, finalHash.length - 2)}00` == hardcodedHash) {
                            chalk.green(contract)
                        } else {
                            chalk.red(contract);
                        }
                    }
                }
            })
        )
    });

    await Promise.allSettled(ops);

    return;
}

run();