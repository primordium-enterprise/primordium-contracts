// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {SharesOnboarderTest} from "./SharesOnboarder.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ISharesOnboarder} from "src/onboarder/interfaces/ISharesOnboarder.sol";

contract SharesOnboarderERC20Test is SharesOnboarderTest {
    function setUp() public virtual override {
        _deploy();
        // Defaults to ERC20 quote asset
        ONBOARDER.quoteAsset = IERC20(erc20Mock);
        // gwart defaults to unlimited spending by the onboarder
        vm.prank(users.gwart);
        erc20Mock.approve(address(onboarder), type(uint256).max);
        _initializeDefaults();
    }

    function test_Fuzz_DepositWithPermit(
        uint8 depositMultiple,
        uint48 deadline,
        uint64 ownerPrivateKey,
        uint64 invalidSignerPrivateKey
    )
        public
    {
        // forgefmt: disable-next-item
        vm.assume(
            depositMultiple > 0 &&
            ownerPrivateKey != invalidSignerPrivateKey &&
            ownerPrivateKey > 0 &&
            invalidSignerPrivateKey > 0
        );

        uint256 depositAmount = ONBOARDER.quoteAmount * depositMultiple;

        (, string memory name, string memory version,,,,) = erc20Mock.eip712Domain();

        address owner = vm.addr(ownerPrivateKey);
        address spender = address(onboarder);

        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, depositAmount, erc20Mock.nonces(owner), deadline));

        bytes32 dataHash = _hashTypedData(_buildEIP712DomainSeparator(name, version, address(erc20Mock)), structHash);

        _dealMockERC20(owner, depositAmount);

        uint256 expectedMintAmount = ONBOARDER.mintAmount * depositMultiple;

        uint8 v;
        bytes32 r;
        bytes32 s;

        if (block.timestamp > deadline) {
            expectedMintAmount = 0;
            vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        } else {
            // Test invalid signer
            address invalidSigner = vm.addr(invalidSignerPrivateKey);
            (v, r, s) = vm.sign(invalidSignerPrivateKey, dataHash);
            vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612InvalidSigner.selector, invalidSigner, owner));
            onboarder.depositWithPermit(owner, spender, depositAmount, deadline, v, r, s);
        }

        (v, r, s) = vm.sign(ownerPrivateKey, dataHash);

        uint256 mintAmount = onboarder.depositWithPermit(owner, spender, depositAmount, deadline, v, r, s);

        assertEq(expectedMintAmount, mintAmount);
        assertEq(token.balanceOf(owner), expectedMintAmount);
    }
}
