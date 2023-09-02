// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "contracts/token/extensions/IVotesProvisioner.sol";

contract TokenSetupTest is Test {

    struct TokenSettings {
        string name;
        string symbol;
        uint256 maxSupply;
        IVotesProvisioner.TokenPrice tokenPrice;
        uint256 tokenSaleBeginsAt;
        uint256 governanceCanBeginAt;
    }

    struct TestAccounts {
        address a;
        address b;
        address c;
        address d;
        address e;
        address f;
    }

    struct TestDepositAmounts {
        uint256 a;
        uint256 b;
        uint256 c;
        uint256 d;
        uint256 e;
        uint256 f;
    }

    TokenSettings internal TOKEN_CONFIG;

    TestAccounts internal testAccounts = TestAccounts(
        address(0x01),
        address(0x02),
        address(0x03),
        address(0x04),
        address(0x05),
        address(0x06)
    );

    TestDepositAmounts internal testDepositAmounts = TestDepositAmounts(
        1 ether,
        2 ether,
        3 ether,
        4 ether,
        5 ether,
        6 ether
    );

    constructor() {

        TOKEN_CONFIG = TokenSettings({
            name: "TestToken",
            symbol: "TEST",
            maxSupply: 1 ether,
            tokenPrice: IVotesProvisioner.TokenPrice(10, 1),
            tokenSaleBeginsAt: block.timestamp,
            governanceCanBeginAt: block.timestamp + 1 days
        });

    }



}