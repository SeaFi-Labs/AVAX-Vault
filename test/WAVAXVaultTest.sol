// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {WAVAXVault} from "../contracts/WAVAXVault.sol";
import {WAVAXVaultV2} from "./mocks/WAVAXVaultV2.sol";
import {MockTokenWAVAX} from "./mocks/MockTokenWAVAX.sol";

contract WAVAXVaultTest is Test {
    WAVAXVault vault;
    MockTokenWAVAX WAVAX;
    address owner;
    address nodeOp1 = address(0x9);

    event DepositedFromStaking(address indexed caller, uint256 amount);

    event GGPCapUpdated(uint256 newCap);

    error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);

    error OwnableUnauthorizedAccount(address account);

    function setUp() public {
        owner = address(this);
        WAVAX = new MockTokenWAVAX(owner);

        address proxy =
            Upgrades.deployUUPSProxy("WAVAXVault.sol", abi.encodeCall(WAVAXVault.initialize, (address(WAVAX), owner)));
        vault = WAVAXVault(proxy);

        vault.grantRole(vault.APPROVED_NODE_OPERATOR(), nodeOp1);
        WAVAX.approve(address(vault), type(uint256).max);

        WAVAX.transfer(nodeOp1, 100000e18);
        WAVAX.approve(address(vault), type(uint256).max);
        vm.prank(nodeOp1);
        WAVAX.approve(address(vault), type(uint256).max);
    }

    function testMaxMethods() public {
        uint256 maxDelta = 1e8;
        uint256 AVAXCap = vault.AVAXCap();

        assertEq(vault.maxDeposit(address(this)), AVAXCap, "initialMaxDeposit");
        assertEq(vault.maxMint(address(this)), AVAXCap, "initialMaxMint");
        assertEq(vault.maxWithdraw(address(this)), 0, "initialMaxWithdraw");
        assertEq(vault.maxRedeem(address(this)), 0, "initialMaxRedeem");

        vault.setAVAXCap(0);
        assertEq(vault.maxDeposit(address(this)), 0, "zeroCapMaxDeposit");
        assertEq(vault.maxMint(address(this)), 0, "zeroCapMaxMint");

        uint256 newCap = 100e18;
        vault.setAVAXCap(newCap);
        assertEq(vault.maxDeposit(address(this)), newCap, "updatedMaxDeposit");
        assertEq(vault.maxMint(address(this)), newCap, "updatedMaxMint");

        uint256 depositedAssets = newCap / 2;
        vault.deposit(depositedAssets, address(this));
        assertEq(vault.maxDeposit(address(this)), depositedAssets, "halfCapMaxDeposit");
        assertEq(vault.maxMint(address(this)), depositedAssets, "halfCapMaxMint");
        assertEq(vault.maxWithdraw(address(this)), depositedAssets, "halfCapMaxWithdraw");
        assertEq(vault.maxRedeem(address(this)), depositedAssets, "halfCapMaxRedeem");

        // double share value
        WAVAX.transfer(address(vault), depositedAssets);
        assertEq(vault.maxDeposit(address(this)), 0, "doubledValueMaxDeposit");
        assertEq(vault.maxMint(address(this)), 0, "doubledValueMaxMint");
        assertApproxEqAbs(vault.maxWithdraw(address(this)), depositedAssets * 2, maxDelta, "doubledValueMaxWithdraw");
        assertApproxEqAbs(vault.maxRedeem(address(this)), depositedAssets, maxDelta, "doubledValueMaxRedeem");

        // update values correctly when GGP goes for staking
        vault.stakeOnNode(depositedAssets, nodeOp1);
        assertEq(vault.maxDeposit(address(this)), 0, "stakedMaxDeposit");
        assertEq(vault.maxMint(address(this)), 0, "stakedMaxMint");
        assertApproxEqAbs(vault.maxWithdraw(address(this)), depositedAssets, maxDelta, "stakedMaxWithdraw");
        assertApproxEqAbs(vault.maxRedeem(address(this)), depositedAssets / 2, maxDelta, "stakedMaxRedeem");
    }

    function testOwnershipNonOwner() public {
        address randomUser = address(0x1337);
        bytes memory encodedCall = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, randomUser);
        vm.startPrank(randomUser);

        // Random person can't call stuff
        vm.expectRevert(encodedCall);
        vault.setAVAXCap(0);
        vm.expectRevert(encodedCall);
        vault.setTargetAPR(0);
        vm.expectRevert(encodedCall);
        vault.upgradeToAndCall(address(0x0), "0x");
        vm.expectRevert("Caller is not the owner or an approved node operator");

        vault.stakeOnNode(0, nodeOp1);
        vm.expectRevert("Caller is not the owner or an approved node operator");
        vault.depositFromStaking(0);

        vm.stopPrank();

        // Node Op can't call stuff
        bytes memory encodedCallNodeOp = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, nodeOp1);

        vm.startPrank(nodeOp1);
        vm.expectRevert(encodedCallNodeOp);
        vault.setAVAXCap(0);
        vm.expectRevert(encodedCallNodeOp);
        vault.setTargetAPR(0);
        vm.stopPrank();
    }

    function testOwnershipOwner() public {
        // owner can call all these methods
        assertEq(address(this), vault.owner());
        vault.setAVAXCap(0);
        vault.setTargetAPR(0);
        vault.stakeOnNode(0, nodeOp1);
        vault.depositFromStaking(0);

        // nodeOP can call all these methods
        vm.startPrank(nodeOp1);
        vault.stakeOnNode(0, nodeOp1);
        vault.depositFromStaking(0);
        vm.stopPrank();
    }

    function testInitalization() public {
        // TODO why was this owner owner owenr?
        vm.expectRevert();
        vault.initialize(owner, owner);
        address implementationAddress = Upgrades.getImplementationAddress(address(vault));
        WAVAXVault implementation = WAVAXVault(implementationAddress);
        vm.expectRevert();
        implementation.initialize(owner, owner);
    }

    // function testStakeAndDistributeRewards() public {
    //     assertEq(vault.totalAssets(), 0);
    //     vault.stakeAndDistributeRewards(nodeOp1);
    //     assertEq(vault.totalAssets(), 0, "rewards remain 0 when no staking asssets");
    //     vault.stakeAndDistributeRewards(nodeOp1);
    //     vault.stakeAndDistributeRewards(nodeOp1);
    //     vault.stakeAndDistributeRewards(nodeOp1);
    //     assertEq(vault.totalAssets(), 0, "calling multiple times doesnt change if stakingAssets is 0");

    //     uint256 originalDeposit = 100e18;
    //     vault.deposit(originalDeposit, address(this));
    //     vault.stakeAndDistributeRewards(nodeOp1);
    //     uint256 expectedStakeAmount = vault.previewRewardsAtStakedAmount(originalDeposit) + originalDeposit;
    //     assertEq(vault.stakingTotalAssets(), expectedStakeAmount, "confirm assets were staked + rewarded correctly");

    //     // calling again should cause it to increase rewards again
    //     vault.stakeAndDistributeRewards(nodeOp1);
    //     uint256 expectedStakeAmount2 = vault.previewRewardsAtStakedAmount(expectedStakeAmount) + expectedStakeAmount;
    //     assertEq(
    //         vault.stakingTotalAssets(),
    //         expectedStakeAmount2,
    //         "confirm assets were staked + rewarded correctly when calling 2x in a row (which shouldnt be done)"
    //     );

    //     // works even with GGP max supply
    // }

    // function testRewardsAtHighValues() public {
    //     uint256 halfMaxSupply = WAVAX.totalSupply() / 2;
    //     vault.setAVAXCap(halfMaxSupply * 2);
    //     vault.deposit(halfMaxSupply, address(this));
    //     vault.stakeAndDistributeRewards(nodeOp1);
    //     uint256 expectedRewards = vault.previewRewardsAtStakedAmount(halfMaxSupply);
    //     uint256 expectedStakeAmount = expectedRewards + halfMaxSupply;
    //     assertEq(vault.stakingTotalAssets(), expectedStakeAmount, "confirm assets were staked + rewarded correctly");
    // }

    function testPreviewRewardsChangesWithAPR() public {
        uint256 stakeAmount = 10000e18; // 10k GGP token
        uint256 maxDelta = 1e18;
        uint256 percent5 = 500; // 5% APR
        uint256 percent15 = 1500; // 15% APR
        uint256 percent50 = 5000; // 15% APR

        vault.setTargetAPR(percent5); // Set initial APR
        uint256 rewardsAt5 = vault.previewRewardsAtStakedAmount(stakeAmount);
        vault.setTargetAPR(percent15); // Change APR
        uint256 rewardsAt15 = vault.previewRewardsAtStakedAmount(stakeAmount);
        vault.setTargetAPR(percent50); // Change APR
        uint256 rewardsAt50 = vault.previewRewardsAtStakedAmount(stakeAmount);
        assertApproxEqAbs(rewardsAt5, 38e18, maxDelta);
        assertApproxEqAbs(rewardsAt15, 115e18, maxDelta);
        assertApproxEqAbs(rewardsAt50, 384e18, maxDelta);
    }

    function testCantOverpayVault() public {
        vm.startPrank(nodeOp1);
        vm.expectRevert("Cant deposit more than the stakingTotalAssets");
        vault.depositFromStaking(1e18);

        vault.depositFromStaking(0);

        uint256 depositAmount = 1000e18;
        vault.deposit(depositAmount, nodeOp1);
        vault.stakeOnNode(depositAmount, nodeOp1);

        vm.expectRevert("Cant deposit more than the stakingTotalAssets");
        vault.depositFromStaking(depositAmount + 1);

        vault.depositFromStaking(depositAmount);

        // nodeOP can deposit more assets with a transfer if needed
        uint256 manuallySendAmount = 100e18;
        WAVAX.transfer(address(vault), manuallySendAmount);
        assertEq(vault.getUnderlyingBalance(), depositAmount + manuallySendAmount);
        // console.log(vault.previewRedeem((1e18)), vault.getUnderlyingBalance());
        assertTrue(vault.previewRedeem(1e18) > 1e18, "vault value should increase if sending assets to vault");
    }

    function testCanUpgrade() public {
        address implAddressV1 = Upgrades.getImplementationAddress(address(vault));

        assertEq(vault.targetAPR(), 1405);
        Upgrades.upgradeProxy(address(vault), "WAVAXVaultV2.sol", abi.encodeCall(WAVAXVault.setTargetAPR, 2000));
        address implAddressV2 = Upgrades.getImplementationAddress(address(vault));

        WAVAXVaultV2 v2 = WAVAXVaultV2(address(vault));
        assertFalse(implAddressV2 == implAddressV1);
        assertEq(v2.newMethod(), "meow");
    }
}
