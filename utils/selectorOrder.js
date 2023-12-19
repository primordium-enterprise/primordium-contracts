#!/usr/bin/env node

const path = require("path");
const fs = require("fs");

const contractName = process.argv[2];

let json;

fs.readFile(
    path.join(
        process.cwd(),
        'out',
        `${contractName}.sol`,
        `${contractName}.json`
    ),
    (err, data) => {
        if (err) {
            console.error(err);
            process.exit();
        }

        json = JSON.parse(data);

        let hexToNum = (str) => parseInt(Number(`0x${str}`));

        let items = Object.entries(json["methodIdentifiers"]).sort((a, b) => {
            return hexToNum(a[1]) - hexToNum(b[1]);
        });

        for (let i = 0; i < items.length; i++) {
            console.log(`${items[i][0]}: ${items[i][1]}`);
        }
    }
);

