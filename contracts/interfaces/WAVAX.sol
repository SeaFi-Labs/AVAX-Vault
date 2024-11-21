// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

interface IWAVAX {
    function deposit() external payable;
    function withdraw(uint256) external;
}
