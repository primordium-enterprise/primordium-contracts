// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "contracts/token/extensions/VotesProvisioner.sol";
import "contracts/token/extensions/IVotesProvisioner.sol";
import "contracts/token/extensions/provisioners/VotesProvisionerETH.sol";
import "contracts/token/extensions/provisioners/VotesProvisionerERC20.sol";
import "contracts/executor/extensions/treasurer/TreasurerETH.sol";
import "contracts/executor/extensions/treasurer/TreasurerERC20.sol";

abstract contract TokenBase is Test, VotesProvisioner {

    struct TokenConfig {
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

    TokenConfig internal tokenConfig = TokenConfig({
        name: "TestToken",
        symbol: "TEST",
        maxSupply: 1 ether,
        tokenPrice: IVotesProvisioner.TokenPrice(10, 1),
        tokenSaleBeginsAt: block.timestamp,
        governanceCanBeginAt: block.timestamp + 1 days
    });

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

    constructor(
        Treasurer executor,
        IERC20 baseAsset
    )
        ERC20Permit(tokenConfig.name)
        ERC20Checkpoints(tokenConfig.name, tokenConfig.symbol)
        VotesProvisioner(
            executor,
            baseAsset,
            tokenConfig.maxSupply,
            tokenConfig.tokenPrice,
            tokenConfig.tokenSaleBeginsAt,
            tokenConfig.governanceCanBeginAt
        )
    {}

}

contract TokenETH is TokenBase, VotesProvisionerETH {

    constructor(
        TreasurerETH executor
    )
        TokenBase(
            executor,
            IERC20(address(0))
        )
    {}

    function depositFor(
        address account,
        uint256 depositAmount
    ) public payable virtual override(VotesProvisioner, VotesProvisionerETH) returns(uint256) {
        return super.depositFor(account, depositAmount);
    }

}

contract TokenERC20 is TokenBase, VotesProvisionerERC20 {

    constructor(
        TreasurerERC20 executor,
        IERC20 baseAsset
    )
        TokenBase(
            executor,
            baseAsset
        )
    {}

    function depositFor(
        address account,
        uint256 depositAmount
    ) public payable virtual override(VotesProvisioner, VotesProvisionerERC20) returns (uint256) {
        return super.depositFor(account, depositAmount);
    }

}