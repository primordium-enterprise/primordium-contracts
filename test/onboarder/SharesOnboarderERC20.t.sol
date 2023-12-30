// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {SharesOnboarderTest} from "./SharesOnboarder.t.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract SharesOnboarderERC20Test is SharesOnboarderTest {
    function setUp() public virtual override {
        _deploy();
        // Defaults to ERC20 quote asset
        ONBOARDER.quoteAsset = IERC20(mockERC20);
        // gwart defaults to unlimited spending by the onboarder
        vm.prank(users.gwart);
        mockERC20.approve(address(onboarder), type(uint256).max);
        _initializeDefaults();
    }

    function test_DepositWithPermit() public {
        uint256 depositAmount = ONBOARDER.quoteAmount;

        (, string memory name, string memory version,,,,) = mockERC20.eip712Domain();

        address owner = users.signer.addr;
        address spender = address(onboarder);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH, owner, spender, depositAmount, mockERC20.nonces(owner), deadline
            )
        );

        bytes32 dataHash = _hashTypedData(_buildEIP712DomainSeparator(name, version, address(mockERC20)), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(users.signer.privateKey, dataHash);

        _dealMockERC20(owner, depositAmount);

        uint256 expectedMintAmount = ONBOARDER.mintAmount;
        assertEq(expectedMintAmount, onboarder.depositWithPermit(owner, spender, depositAmount, deadline, v, r, s));
        assertEq(token.balanceOf(owner), expectedMintAmount);
    }
}
