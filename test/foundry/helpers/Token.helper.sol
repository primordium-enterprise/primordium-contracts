// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "contracts/token/extensions/VotesProvisioner.sol";
import "contracts/token/extensions/IVotesProvisioner.sol";
import "contracts/token/extensions/provisioners/VotesProvisionerETH.sol";
import "contracts/token/extensions/provisioners/VotesProvisionerERC20.sol";
import "contracts/executor/extensions/treasurer/TreasurerETH.sol";
import "contracts/executor/extensions/treasurer/TreasurerERC20.sol";

abstract contract TokenBase is Test, VotesProvisioner {

    constructor(
        TokenHelper.TokenConfig memory tokenConfig,
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
        TokenHelper.TokenConfig memory tokenConfig,
        TreasurerETH executor
    )
        TokenBase(
            tokenConfig,
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
        TokenHelper.TokenConfig memory tokenConfig,
        TreasurerERC20 executor,
        IERC20 baseAsset
    )
        TokenBase(
            tokenConfig,
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

abstract contract TokenHelper is Test {

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

    TokenBase token;

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

    function _tokenDepositFor(address account, uint256 depositAmount) internal virtual returns (uint256);

}

contract TokenHelperETH is TokenHelper {

    constructor(address executor) {
        token = new TokenETH(
            tokenConfig,
            TreasurerETH(payable(executor))
        );
    }

    function _tokenDepositFor(address account, uint256 depositAmount) internal virtual override returns (uint256) {
        vm.deal(address(this), depositAmount);
        return token.depositFor{value: depositAmount}(account, depositAmount);
    }

}

contract TokenHelperERC20 is TokenHelper {

    ERC20PresetMinterPauser erc20BaseAsset = new ERC20PresetMinterPauser("BaseAsset", "BA");

    constructor(address executor, address baseAsset) {
        token = new TokenERC20(
            tokenConfig,
            TreasurerERC20(payable(executor)),
            IERC20(baseAsset)
        );
    }

    function _tokenDepositFor(address account, uint256 depositAmount) internal virtual override returns (uint256) {
        erc20BaseAsset.mint(address(this), depositAmount);
        erc20BaseAsset.approve(address(token), depositAmount);
        return token.depositFor(account, depositAmount);
    }

}