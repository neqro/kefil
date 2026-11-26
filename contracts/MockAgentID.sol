// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @dev Test-only stand-in for the Agent ID contract.
contract MockAgentID {
    mapping(address => uint256) public balanceOf;
    function set(address a, uint256 b) external { balanceOf[a] = b; }
}
