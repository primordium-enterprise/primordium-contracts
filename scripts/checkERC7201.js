#!/usr/bin/env node

const glob = require("glob");
const fs = require("fs/promises");
const path = require("path");
const chalk = require("chalk");
const getERC7201Hash = require("./getERC7201Hash");

const contracts = glob.sync('contracts/**/*.sol');

const run = async () => {

    const ops = [];
    let erc7201Count = 0;
    let errorCount = 0;

    contracts.forEach(contract => {
        ops.push(
            fs.readFile(path.join(process.cwd(), contract), 'utf-8')
            .then((contents) => {
                // Match each instance of "@custom:storage-location erc7201:HASHED_STRING"
                const matches = Array.from(contents.matchAll(/(?<=@custom:storage-location\serc7201:)\S*/gm));
                let j = 0;
                if (matches.length > 0) {
                    erc7201Count++;
                    for (let j = 0; j < matches.length; j++) {
                        let match = matches[j];

                        // Search the contract, starting from the match index, for the first occurrence of bytes32 constant
                        let hardcodedHashMatch = match.input
                            .substring(match.index)
                            .match(/bytes32\s.*constant(?:.|\s)*?(0x[0-9a-fA-F]{64});/gm);

                        if (hardcodedHashMatch == null) {
                            console.log(chalk.red(contract), "(HASH NOT FOUND)");
                            errorCount++;
                            return;
                        }

                        // Extract the hash hex value from the match
                        hhm = hardcodedHashMatch[0]
                        const hardcodedHash = hhm.substring(hhm.length - 67, hhm.length - 1);

                        let isValid = getERC7201Hash(match[0]).normalize() === hardcodedHash.normalize();
                        if (isValid) {
                            console.log(chalk.green(contract), match[0]);
                        } else {
                            errorCount++;
                            console.log(chalk.red(contract), finalHashTo32Multiple);
                        }

                    }
                }

            })
            .catch(console.error)
        )
    });

    await Promise.all(ops);

    console.log(
        "\n",
        "Found", erc7201Count, "erc:7201 contracts,",
        errorCount > 0 ? chalk.red(errorCount) : chalk.green(errorCount),
        "of which had errors."
    );

    return;
}

run();