// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/console.sol";

contract MockTokenWAVAX is ERC20 {
    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);

    constructor(address initialRecipient) ERC20("Wrapped Native", "WNATIVE") {
        _mint(initialRecipient, 18_000_000 * 10 ** decimals());
    }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 _amount) external {
        _burn(msg.sender, _amount);
        emit Withdrawal(msg.sender, _amount);

        (bool success,) = msg.sender.call{value: _amount}("");
        if (!success) {
            revert("Withdraw failed");
        }
    }
}
