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

        address payable proxy = payable(
            Upgrades.deployUUPSProxy("WAVAXVault.sol", abi.encodeCall(WAVAXVault.initialize, (address(WAVAX), owner)))
        );
        vault = WAVAXVault(payable(proxy));

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
        vm.expectRevert();
        vault.initialize(owner, owner);
        address payable implementationAddress = payable(Upgrades.getImplementationAddress(address(vault)));
        WAVAXVault implementation = WAVAXVault(payable(implementationAddress));
        vm.expectRevert();
        implementation.initialize(owner, owner);
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
        assertTrue(vault.previewRedeem(1e18) > 1e18, "vault value should increase if sending assets to vault");
    }

    function testCanUpgrade() public {
        address implAddressV1 = Upgrades.getImplementationAddress(address(vault));

        assertEq(vault.targetAPR(), 1405);
        Upgrades.upgradeProxy(address(vault), "WAVAXVaultV2.sol", abi.encodeCall(WAVAXVault.setTargetAPR, 2000));
        address implAddressV2 = Upgrades.getImplementationAddress(address(vault));

        WAVAXVaultV2 v2 = WAVAXVaultV2(payable(address(vault)));
        assertFalse(implAddressV2 == implAddressV1);
        assertEq(v2.newMethod(), "meow");
    }
}
