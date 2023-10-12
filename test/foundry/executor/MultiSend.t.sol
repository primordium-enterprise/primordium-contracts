// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import {Enum} from "contracts/common/Enum.sol";
import {MultiSend} from "contracts/executor/base/MultiSend.sol";
import {MultiSendEncoder} from "contracts/libraries/MultiSendEncoder.sol";

contract MultiSender is MultiSend {

    uint256 public x;
    address public a;

    event Added(uint256 amount);
    event Subtracted(uint256 amount);
    event AddressChanged(address newAddress);

    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) public {
        _execute(to, value, data, Enum.Operation.Call);
    }

    function add(uint256 addBy) external onlyExecutor {
        _add(addBy);
    }

    function _add(uint256 addBy) internal {
        x += addBy;
        emit Added(addBy);
    }

    function subtract(uint256 subBy) external onlyExecutor {
        _subtract(subBy);
    }

    function _subtract(uint256 subBy) internal {
        x -= subBy;
        emit Subtracted(subBy);
    }

    function addThenSubtract(uint256 addBy, uint256 subBy) external onlyExecutor {
        _add(addBy);
        _subtract(subBy);
    }

    function updateAddress(address newAddress) external onlyExecutor {
        a = newAddress;
        emit AddressChanged(newAddress);
    }

}

contract PaymentReceiver {

    function payMeWithRefund(uint256 amountToKeepHere) external payable {
        uint256 refund = msg.value - amountToKeepHere;
        (bool success,) = msg.sender.call{value: refund}("");
        if (!success) revert();
    }
}

contract MultiSendTest is Test {

    address payable multiSender = payable(address(new MultiSender()));
    address paymentReceiver = address(new PaymentReceiver());

    function setUp() public {
        vm.deal(multiSender, 10 ether);
    }

    function test_MultiSend() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _buildTransactions();

        (
            address to,
            uint256 value,
            bytes memory data
        ) = MultiSendEncoder.encodeMultiSend(multiSender, targets, values, calldatas);

        console.log(to);
        console.log(value);
        console.log(data.length);
        console.logBytes(data);

        MultiSender(payable(multiSender)).execute(to, value, data);

        assertEq(MultiSender(multiSender).x(), 20);
        assertEq(MultiSender(multiSender).a(), address(0x01));
        assertEq(multiSender.balance, 5 ether);

    }

    function test_MultiSendClassic() public {

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _buildTransactions();

        (
            address to,
            uint256 value,
            bytes memory data
        ) = _encodeMultiSendClassic(multiSender, targets, values, calldatas);

        console.log(data.length);
        console.logBytes(data);

        MultiSender(payable(multiSender)).execute(to, value, data);

        assertEq(MultiSender(multiSender).x(), 20);
        assertEq(MultiSender(multiSender).a(), address(0x01));
        assertEq(multiSender.balance, 5 ether);

    }

    function test_MultiSendEncoderIsEqual() public {

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _buildTransactions();

        (
            address to,
            uint256 value,
            bytes memory data
        ) = MultiSendEncoder.encodeMultiSend(multiSender, targets, values, calldatas);

        (
            address checkTo,
            uint256 checkValue,
            bytes memory checkData
        ) = _encodeMultiSendClassic(multiSender, targets, values, calldatas);

        assertEq(to, checkTo);
        assertEq(value, checkValue);
        assertEq(data.length, checkData.length);
        for (uint256 i = 0; i < data.length; i++) {
            if (data[i] != checkData[i]) {
                revert("Encoded data does not match");
            }
        }

    }

    function _buildTransactions() internal view returns (
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) {

        targets = new address[](5);
        values = new uint256[](5);
        calldatas = new bytes[](5);

        // First transaction, add(10)
        targets[0] = multiSender;
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(MultiSender.add.selector, 10);

        // Second transaction, sub(5)
        targets[1] = multiSender;
        values[1] = 0;
        calldatas[1] = abi.encodeWithSelector(MultiSender.subtract.selector, 5);

        // Third transaction, pay the PaymentReceiver (should receive refund of 5 ether back)
        targets[2] = paymentReceiver;
        values[2] = 10 ether;
        calldatas[2] = abi.encodeWithSelector(PaymentReceiver.payMeWithRefund.selector, 5 ether);

        // Fourth transaction, updateAddress(0x01)
        targets[3] = multiSender;
        values[3] = 0;
        calldatas[3] = abi.encodeWithSelector(MultiSender.updateAddress.selector, address(0x01));

        // Fifth transaction, addThenSubtract(20, 5)
        targets[4] = multiSender;
        values[4] = 0;
        calldatas[4] = abi.encodeWithSelector(MultiSender.addThenSubtract.selector, 20, 5);

    }

    function _encodeMultiSendClassic(
        address executor,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) internal pure returns (
        address to,
        uint256 value,
        bytes memory data
    ) {

        if (targets.length > 1) {
            to = executor;
            value = 0;
            data = hex"";
            for (uint256 i; i < targets.length;) {
                data = abi.encodePacked(
                    data,
                    abi.encodePacked(
                        uint8(0),
                        targets[i],
                        values[i],
                        uint256(calldatas[i].length),
                        calldatas[i]
                    )
                );
                unchecked { ++i; }
            }
            data = abi.encodeWithSelector(MultiSend.multiSend.selector, data);
        } else {
            to = targets[0];
            value = values[0];
            data = calldatas[0];
        }
    }
}