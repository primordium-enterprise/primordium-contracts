// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "contracts/token/extensions/VotesProvisioner.sol";
import "contracts/token/extensions/IVotesProvisioner.sol";
import "contracts/token/extensions/provisioners/VotesProvisionerETH.sol";

contract TokenETH is VotesProvisionerETH {

    constructor(
        Treasurer executor_,
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        TokenPrice memory tokenPrice_,
        uint256 tokenSaleBeginsAt_,
        uint256 governanceCanBeginAt_
    )
        ERC20Permit(name_)
        ERC20Checkpoints(name_, symbol_)
        VotesProvisioner(
            executor_,
            maxSupply_,
            tokenPrice_,
            IERC20(address(0)),
            tokenSaleBeginsAt_,
            governanceCanBeginAt_
        )
    {}

}

contract TokenHelper is Test {

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

    TokenSettings internal tokenConfig;

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
        0,
        0,
        0
    );

    VotesProvisioner token;

    constructor() {

        tokenConfig = TokenSettings({
            name: "TestToken",
            symbol: "TEST",
            maxSupply: 1 ether,
            tokenPrice: IVotesProvisioner.TokenPrice(10, 1),
            tokenSaleBeginsAt: block.timestamp,
            governanceCanBeginAt: block.timestamp + 1 days
        });

    }

    function _setupTokenETH(Treasurer executor_) internal virtual {
        token = new TokenETH(
            executor_,
            tokenConfig.name,
            tokenConfig.symbol,
            tokenConfig.maxSupply,
            tokenConfig.tokenPrice,
            tokenConfig.tokenSaleBeginsAt,
            tokenConfig.governanceCanBeginAt
        );
    }

}