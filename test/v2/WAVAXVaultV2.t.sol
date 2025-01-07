// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {WAVAXVaultV2} from "../../contracts/v2/WAVAXVaultV2.sol";
import {MockTokenWAVAX} from "../mocks/MockTokenWAVAX.sol";

contract WAVAXVaultTest is Test {
    WAVAXVaultV2 vault;
    MockTokenWAVAX WAVAX;
    address owner;
    address nodeOp1 = address(0x9);
    address rewardsSyncer = makeAddr("rewardsSyncer");

    event DepositedFromStaking(address indexed caller, uint256 amount);

    event GGPCapUpdated(uint256 newCap);

    error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);

    error OwnableUnauthorizedAccount(address account);

    function setUp() public {
        owner = address(this);
        WAVAX = new MockTokenWAVAX(owner);

        address payable proxy = payable(
            Upgrades.deployUUPSProxy(
                "WAVAXVaultV2.sol", abi.encodeCall(WAVAXVaultV2.initialize, (address(WAVAX), owner))
            )
        );
        vault = WAVAXVaultV2(payable(proxy));

        vault.grantRole(vault.APPROVED_NODE_OPERATOR(), nodeOp1);
        WAVAX.approve(address(vault), type(uint256).max);

        WAVAX.transfer(nodeOp1, 100000e18);
        WAVAX.approve(address(vault), type(uint256).max);
        vm.prank(nodeOp1);
        WAVAX.approve(address(vault), type(uint256).max);
    }

    function testFuzz_OnlyOwnerApprovedNodeOperatorOrNodeSyncerCanUpdadeRewards(address anyone) public {
        vm.prank(anyone);
        if (anyone == owner || anyone == nodeOp1 || anyone == rewardsSyncer) {
            vault.updateRewards();
        } else {
            vm.expectRevert(bytes("Unauthorized rewards updater account"));
            vault.updateRewards();
        }
    }
}
