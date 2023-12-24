#!/usr/bin/env node

import path from "path";
import fs from "fs";

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

        json = JSON.parse(String(data));

        let hexToNum = (str: string) => parseInt(`0x${str}`);

        let items = Object.entries(json["methodIdentifiers"]).sort((a, b) => {
            return hexToNum(String(a[1])) - hexToNum(String(b[1]));
        });

        for (let i = 0; i < items.length; i++) {
            console.log(`${items[i][0]}: ${items[i][1]}`);
        }
    }
);

