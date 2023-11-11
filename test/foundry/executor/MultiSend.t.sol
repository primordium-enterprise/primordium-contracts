// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import {Enum} from "contracts/common/Enum.sol";
import {MultiSend} from "contracts/executor/base/MultiSend.sol";
import {MultiSendEncoder} from "contracts/libraries/MultiSendEncoder.sol";

interface IMultiSenderEvents {

    event Added(uint256 amount);
    event Subtracted(uint256 amount);
    event AddressChanged(address newAddress);
    event BytesUpdated(bytes newBytes);

}

contract ExternalEncoder {

    function encodeMultiSendCalldata(
        address executor,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external pure returns (address to, uint256 value, bytes memory data) {
        return MultiSendEncoder.encodeMultiSendCalldata(executor, targets, values, calldatas);
    }

}

contract MultiSender is MultiSend, IMultiSenderEvents{

    uint256 public x;
    address public a;
    bytes public z;

    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) public {
        _execute(to, value, data, Enum.Operation.Call);
    }

    function add(uint256 addBy) external onlySelf {
        _add(addBy);
    }

    function _add(uint256 addBy) internal {
        x += addBy;
        emit Added(addBy);
    }

    function subtract(uint256 subBy) external onlySelf {
        _subtract(subBy);
    }

    function _subtract(uint256 subBy) internal {
        x -= subBy;
        emit Subtracted(subBy);
    }

    function addThenSubtract(uint256 addBy, uint256 subBy) external onlySelf {
        _add(addBy);
        _subtract(subBy);
    }

    function updateAddress(address newAddress) external onlySelf {
        a = newAddress;
        emit AddressChanged(newAddress);
    }

    function addToBytes(bytes memory addition1, bytes memory addition2) external onlySelf {
        for (uint256 i = 0; i < addition1.length; i++) {
            z.push(addition1[i]);
        }
        for (uint256 i = 0; i < addition2.length; i++) {
            z.push(addition2[i]);
        }
        emit BytesUpdated(z);
    }

}

contract PaymentReceiver {

    function payMeWithRefund(uint256 amountToKeepHere) external payable {
        uint256 refund = msg.value - amountToKeepHere;
        (bool success,) = msg.sender.call{value: refund}("");
        if (!success) revert();
    }
}

contract MultiSendTest is Test, IMultiSenderEvents {

    address externalEncoder = address(new ExternalEncoder());
    address payable multiSender = payable(address(new MultiSender()));
    address paymentReceiver = address(new PaymentReceiver());

    function setUp() public {
        vm.deal(multiSender, 10 ether);
    }

    function _executeMultiSend() internal {
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

        vm.recordLogs();
        MultiSender(payable(multiSender)).execute(to, value, data);
    }

    function _executeMultiSendCalldata() internal {

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = _buildTransactions();

        (
            address to,
            uint256 value,
            bytes memory data
        ) = ExternalEncoder(externalEncoder).encodeMultiSendCalldata(multiSender, targets, values, calldatas);

        vm.recordLogs();
        MultiSender(payable(multiSender)).execute(to, value, data);

    }

    function _executeMultiSendClassic() internal {

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

        vm.recordLogs();
        MultiSender(payable(multiSender)).execute(to, value, data);

    }

    function test_MultiSend() public {
        _executeMultiSend();
        _asserts();
    }

    function test_MultiSendCalldata() public {
        _executeMultiSendCalldata();
        _asserts();
    }

    function test_MultiSendClassic() public {
        _executeMultiSendClassic();
        _asserts();
    }

    function test_MultiSendEncodersAreEqual() public {

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
            address toCalldata,
            uint256 valueCalldata,
            bytes memory dataCalldata
        ) = ExternalEncoder(externalEncoder).encodeMultiSendCalldata(multiSender, targets, values, calldatas);

        (
            address checkTo,
            uint256 checkValue,
            bytes memory checkData
        ) = _encodeMultiSendClassic(multiSender, targets, values, calldatas);

        assertEq(to, toCalldata);
        assertEq(to, checkTo);

        assertEq(value, valueCalldata);
        assertEq(value, checkValue);

        assertEq(data, dataCalldata);
        assertEq(data, checkData);

    }

    function _buildTransactions() internal view returns (
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) {

        targets = new address[](6);
        values = new uint256[](6);
        calldatas = new bytes[](6);

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

        // Sixth transaction, addToBytes(bytes)
        targets[5] = multiSender;
        values[5] = 0;
        bytes memory addition1 = hex"010203";
        bytes memory addition2 = hex"01020304";
        calldatas[5] = abi.encodeWithSelector(MultiSender.addToBytes.selector, addition1, addition2);

    }

    function _asserts() internal {

        assertEq(MultiSender(multiSender).x(), 20);
        assertEq(MultiSender(multiSender).a(), address(0x01));
        assertEq(multiSender.balance, 5 ether);
        bytes memory z = MultiSender(multiSender).z();
        bytes memory _z = hex"01020301020304";
        for (uint256 i = 0; i < z.length; i++) {
            assertEq(z[i], _z[i]);
        }

        // Check the logs, order should be: Added, Subtracted, AddressChanged, Added, Subtracted, BytesUpdated
        bytes32[7] memory expectedTopics = [
            Added.selector,
            Subtracted.selector,
            AddressChanged.selector,
            Added.selector,
            Subtracted.selector,
            BytesUpdated.selector,
            bytes32(0x00)
        ];
        uint256 x;

        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == multiSender && logs[i].topics.length > 0) {
                // Skip the "CallExecuted" events
                if (logs[i].topics[0] == hex"7aa5ed2c76d4b9b3e8cbc2d86e798d468acf8cc22876dbfe0b62ea3180006c26") {
                    continue;
                }
                if (x < expectedTopics.length) {
                    if (logs[i].topics[0] == expectedTopics[x]) {
                        ++x;
                    }
                }
            }
        }

        assertEq(x, expectedTopics.length - 1, "Expected event emits not lining up.");
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