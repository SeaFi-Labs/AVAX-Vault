// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/console.sol";

// [GGP] use the real WAVAX instead of this when deploying to prod

contract MockTokenWAVAX is ERC20("Wrapped AVAX", "AVAX") {
    using SafeERC20 for IERC20;

    event Deposit(address indexed from, uint256 amount);

    event Withdrawal(address indexed to, uint256 amount);

    constructor(address initialRecipient) {
        // Mint 18 million tokens (18,000,000 * 10^18 for 18 decimals)
        _mint(initialRecipient, 18_000_000 * 10 ** decimals());
    }

    function deposit() public payable virtual {
        console.log("wavax ran", msg.sender, msg.value);
        _mint(msg.sender, msg.value);
        console.log("wavax ran2", msg.sender, msg.value);

        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) public virtual {
        _burn(msg.sender, amount);

        emit Withdrawal(msg.sender, amount);

        // msg.sender.safeTransfer(amount);
    }

    receive() external payable virtual {
        deposit();
    }
}
