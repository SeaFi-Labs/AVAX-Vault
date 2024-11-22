// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {WAVAXVault} from "../contracts/WAVAXVault.sol";
import {MockTokenWAVAX} from "./mocks/MockTokenWAVAX.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract WAVAXVaultTest2 is Test {
    WAVAXVault vault;
    MockTokenWAVAX WAVAX;
    address owner;
    address WAVAXVaultMultisig = address(0x69);

    event GGPCapUpdated(uint256 newCap);
    event DepositedFromStaking(address indexed caller, uint256 amount);

    error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);
    error OwnableUnauthorizedAccount(address account);

    function setUp() public {
        owner = address(this);
        WAVAX = new MockTokenWAVAX(owner);
        address proxy = Upgrades.deployUUPSProxy(
            "WAVAXVault.sol", abi.encodeCall(WAVAXVault.initialize, (address(WAVAX), WAVAXVaultMultisig))
        );
        vault = WAVAXVault(payable(proxy));
    }

    function testWalkThroughEntireScenario() public {
        // Setup roles and addresses
        address nodeOp1 = address(0x999);
        address nodeOp2 = address(0x888);
        address randomUser1 = address(0x777);
        address randomUser2 = address(0x666);
        address randomUser3 = address(0x555);

        // Transfer tokens to users
        WAVAX.transfer(randomUser1, 10000e18);
        WAVAX.transfer(randomUser2, 10000e18);

        // Test re-initialization should revert
        vm.expectRevert();
        vault.initialize(address(WAVAX), address(0x69));

        // Test roles assignment should revert for unauthorized users
        bytes32 nodeOpRole = vault.APPROVED_NODE_OPERATOR();
        bytes32 defaultAdminRole = vault.DEFAULT_ADMIN_ROLE();

        vm.expectRevert();
        vault.grantRole(nodeOpRole, address(0x69));

        vm.expectRevert();
        vault.grantRole(defaultAdminRole, address(0x69));

        // Check ownership and roles
        assertEq(vault.owner(), address(0x69), "Vault owner should be multisig address");
        assertEq(vault.hasRole(defaultAdminRole, address(0x69)), true, "Multisig should have default admin role");

        // Grant roles using multisig
        vm.startPrank(address(0x69));
        vault.grantRole(nodeOpRole, nodeOp1);
        vault.grantRole(nodeOpRole, nodeOp2);
        vm.stopPrank();

        // Deposit from randomUser1
        vm.startPrank(randomUser1);
        uint256 randomUser1InitialDeposit = 10e18;
        WAVAX.approve(address(vault), randomUser1InitialDeposit);
        vault.deposit(randomUser1InitialDeposit, randomUser1);
        assertEq(
            vault.balanceOf(randomUser1),
            randomUser1InitialDeposit,
            "User1's vault balance should match the initial deposit"
        );
        assertEq(vault.totalAssets(), randomUser1InitialDeposit, "Total vault assets should match User1's deposit");
        vm.stopPrank();

        // Deposit from randomUser2
        vm.startPrank(randomUser2);

        uint256 randomUser2InitialDeposit = 10000e18;
        vm.deal(randomUser2, randomUser2InitialDeposit);
        vault.depositAVAX{value: randomUser2InitialDeposit}();

        vm.stopPrank();
        uint256 totalDeposits = randomUser1InitialDeposit + randomUser2InitialDeposit;
        assertEq(vault.totalAssets(), totalDeposits, "Total vault assets should match sum of User1 and User2 deposits");

        // Withdraw from randomUser2
        vm.startPrank(randomUser2);
        uint256 randomUser2Withdrawal = 100e18;
        vault.withdraw(randomUser2Withdrawal, randomUser2, randomUser2);
        uint256 totalDepositsAfterWithdraw = totalDeposits - randomUser2Withdrawal;
        assertEq(
            vault.balanceOf(randomUser2),
            randomUser2InitialDeposit - randomUser2Withdrawal,
            "User2's vault balance should be reduced by the withdrawal amount"
        );
        assertEq(
            vault.totalAssets(),
            totalDepositsAfterWithdraw,
            "Total vault assets should be reduced by User2's withdrawal"
        );
        vm.stopPrank();

        // // Stake and distribute rewards
        vm.startPrank(address(0x69));
        uint256 amountToStake = vault.totalAssets();
        vault.stakeOnNode(amountToStake, nodeOp1);

        address _randomUser2 = randomUser2;

        assertEq(
            vault.maxMint(_randomUser2),
            vault.maxDeposit(_randomUser2),
            "Mint and Deposit should be the same before ratio changes"
        );

        // for stack to deep errors
        address _nodeOp1 = nodeOp1;

        vm.warp(block.timestamp + 30 days);
        uint256 BASIS_POINTS_DIVISOR = 10000;
        uint256 DAYS_IN_YEAR = 365;
        uint256 dailyRate = (vault.targetAPR() * 1e18) / DAYS_IN_YEAR; // Scale up by 1e18 to preserve decimals
        uint256 thirtyDayYield = (vault.totalAssets() * dailyRate * 30) / (BASIS_POINTS_DIVISOR * 1e18);

        // Calculate monthly yield
        assertApproxEqAbs(
            vault.getPendingRewards(), thirtyDayYield, 1e8, "Yield should be approx what id expect based on APR"
        );
        uint256 totalVaultWithRewards = vault.totalAssets() + vault.getPendingRewards();

        vault.updateRewards();
        // Assert that pending rewards are reset to 0 after updateRewards is called
        assertEq(vault.getPendingRewards(), 0, "Pending rewards should be 0 after updateRewards");

        // Assert that totalVaultWithRewards equals total assets after rewards are updated
        assertEq(
            totalVaultWithRewards,
            vault.totalAssets(),
            "Total vault with rewards should equal total assets after update"
        );
        vault.updateRewards();
        // Assert that pending rewards are reset to 0 after updateRewards is called
        assertEq(vault.getPendingRewards(), 0, "Pending rewards should be 0 after updateRewards");

        console.log(amountToStake, thirtyDayYield);
        assertApproxEqAbs(
            amountToStake + thirtyDayYield,
            vault.stakingTotalAssets(),
            1e8,
            "staking vault with rewards should equal total assets after update"
        );

        vm.stopPrank();

        // Check max redeem and withdraw for randomUser2
        uint256 maxRedeemUser2 = vault.maxRedeem(_randomUser2);
        uint256 maxWithdrawUser2 = vault.maxWithdraw(_randomUser2);
        assertApproxEqAbs(
            vault.previewWithdraw(maxWithdrawUser2),
            maxRedeemUser2,
            10,
            "Preview withdraw should approximately equal max redeem"
        );
        assertApproxEqAbs(
            vault.previewRedeem(maxRedeemUser2),
            maxWithdrawUser2,
            10,
            "Preview redeem should approximately equal max withdraw"
        );

        WAVAX.transfer(_nodeOp1, thirtyDayYield);

        vm.startPrank(_nodeOp1);

        // deposit rewards into the vault
        WAVAX.approve(address(vault), thirtyDayYield * 2);
        vault.depositFromStaking(thirtyDayYield);
        assertApproxEqAbs(vault.totalAssets(), amountToStake + thirtyDayYield, 100, "Doesn't change the total assets");
        assertApproxEqAbs(
            vault.getUnderlyingBalance(), thirtyDayYield, 100, "Correct amount of assets are in the vault"
        );
        assertApproxEqAbs(vault.stakingTotalAssets(), amountToStake, 100, "Correct amount of assets are being staked");

        // console.log(
        //     vault.maxMint(_randomUser2),
        //     vault.maxDeposit(_randomUser2),
        //     vault.maxRedeem(_randomUser2),
        //     vault.maxWithdraw(_randomUser2)
        // );
    }
}
