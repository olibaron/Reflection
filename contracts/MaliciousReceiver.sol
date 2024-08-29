// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MaliciousReceiver {
    receive() external payable {
        // Revert every time ETH is sent to this contract
        revert("Malicious receiver rejecting funds");
    }
}
