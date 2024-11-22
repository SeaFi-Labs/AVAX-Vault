// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {WAVAXVault} from "../contracts/WAVAXVault.sol";
import {MockTokenWAVAX} from "./mocks/MockTokenWAVAX.sol";

contract AVAXVaultTest is Test {
    WAVAXVault vault;
    MockTokenWAVAX WAVAX;
    address owner;
    address nodeOp1 = address(0x9);

    event AVAXCapUpdated(uint256 newCap);
    event DepositedFromStaking(address indexed caller, uint256 amount);

    error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);

    error OwnableUnauthorizedAccount(address account);

    function setUp() public {
        owner = address(this);
        WAVAX = new MockTokenWAVAX(address(this));

        address proxy = Upgrades.deployUUPSProxy(
            "WAVAXVault.sol", abi.encodeCall(WAVAXVault.initialize, (address(WAVAX), address(this)))
        );
        vault = WAVAXVault(proxy);

        vault.grantRole(vault.APPROVED_NODE_OPERATOR(), nodeOp1);
        WAVAX.approve(address(vault), type(uint256).max);

        WAVAX.transfer(nodeOp1, 100000e18);
        WAVAX.approve(address(vault), type(uint256).max);
        vm.prank(nodeOp1);
        WAVAX.approve(address(vault), type(uint256).max);
    }

    function testStakeOnNode() public {
        uint256 amount = 10e18; // 10 AVAX for simplicity

        vault.deposit(amount, msg.sender);
        assertEq(vault.balanceOf(msg.sender), amount, "Depositor gets correct amount of shares");
        vault.stakeOnNode(amount, nodeOp1);

        assertEq(vault.stakingTotalAssets(), amount, "The staking total assets should be updated");
        assertEq(vault.totalAssets(), amount, "The total assets should be equal to deposits");
    }

    function testTotalAssetsCalculation() public {
        uint256 assetsToDeposit = 1000e18; // Simulated staked amount
        assertEq(vault.stakingTotalAssets(), 0, "The staking total assets should be updated");
        assertEq(vault.totalAssets(), 0, "The total assets should be equal to deposits");
        assertEq(vault.getUnderlyingBalance(), 0, "The total assets should be equal to deposits");

        vault.deposit(assetsToDeposit, msg.sender);
        assertEq(vault.stakingTotalAssets(), 0, "The staking total assets should be updated");
        assertEq(vault.totalAssets(), assetsToDeposit, "The total assets should be equal to deposits");
        assertEq(vault.getUnderlyingBalance(), assetsToDeposit, "The total assets should be equal to deposits");

        vault.stakeOnNode(assetsToDeposit / 2, nodeOp1);
        assertEq(vault.stakingTotalAssets(), assetsToDeposit / 2, "The staking total assets should be updated");
        assertEq(vault.totalAssets(), assetsToDeposit, "The total assets should be equal to deposits");
        assertEq(vault.getUnderlyingBalance(), assetsToDeposit / 2, "The total assets should be equal to deposits");

        vault.depositFromStaking(assetsToDeposit / 2);
        assertEq(vault.stakingTotalAssets(), 0, "The staking total assets should be updated");
        assertEq(vault.totalAssets(), assetsToDeposit, "The total assets should be equal to deposits");
        assertEq(vault.getUnderlyingBalance(), assetsToDeposit, "The total assets should be equal to deposits");
    }

    function testInitialization() public {
        assertEq(vault.stakingTotalAssets(), 0, "Staking total assets should initially be 0");
        assertEq(vault.AVAXCap(), 20000e18, "Asset cap should be correctly set to 33000e18");

        // Verify the initial owner is correctly set
        assertEq(vault.owner(), owner, "The initial owner should be correctly set");

        // Check that the initial owner has the DEFAULT_ADMIN_ROLE
        bytes32 defaultAdminRole = vault.DEFAULT_ADMIN_ROLE();
        assertTrue(vault.hasRole(defaultAdminRole, owner), "The initial owner should have the DEFAULT_ADMIN_ROLE");
    }

    function testsetAVAXCapSuccess() public {
        uint256 newAVAXCap = 20000e18; // Define a new asset cap different from the initial one

        // Expect the AVAXCapUpdated event to be emitted with the new asset cap value
        vm.expectEmit(true, true, true, true);
        emit AVAXCapUpdated(newAVAXCap);

        // Attempt to set the new asset cap as the owner
        vault.setAVAXCap(newAVAXCap);
        // Verify the asset cap was successfully updated
        assertEq(vault.AVAXCap(), newAVAXCap, "Asset cap should be updated to the new value");
    }

    function testsetAVAXCapFailureNonOwner() public {
        uint256 newAVAXCap = 20000e18; // Define a new asset cap
        address nonOwner = address(0x1); // Assume this address is not the owner

        // Set the next caller to be a non-owner
        vm.prank(nonOwner);

        // Attempt to set the new asset cap as a non-owner and expect it to revert
        // Adjust the revert message to match the actual error message in your contract
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, nonOwner));
        vault.setAVAXCap(newAVAXCap);
    }

    function testDepositFromStakingFailureUnauthorized() public {
        uint256 depositAmount = 100e18; // Example amount
        address unauthorized = address(0x2); // Example unauthorized address

        vm.startPrank(unauthorized);
        vm.expectRevert("Caller is not the owner or an approved node operator"); // Adjust based on your actual revert message
        vault.depositFromStaking(depositAmount);
        vm.stopPrank();
    }

    function testMaxDepositUnderNormalConditions() public {
        uint256 AVAXCap = 33000e18; // Set the asset cap to 33,000 tokens for this test
        uint256 depositedAssets = 10000e18; // Simulate depositing 10,000 tokens
        vault.setAVAXCap(AVAXCap);
        vault.deposit(depositedAssets, address(this)); // Assume deposit function updates total assets correctly

        uint256 expectedMaxDeposit = AVAXCap - depositedAssets;
        assertEq(
            vault.maxDeposit(address(this)),
            expectedMaxDeposit,
            "Max deposit should match the expected value under normal conditions"
        );
    }

    function testMaxDepositWhenVaultIsFull() public {
        uint256 AVAXCap = 33000e18; // Asset cap is 33,000 tokens
        vault.setAVAXCap(AVAXCap);
        vault.deposit(AVAXCap, address(this)); // Assume the vault is now full

        uint256 expectedMaxDeposit = 0;
        assertEq(vault.maxDeposit(address(this)), expectedMaxDeposit, "Max deposit should be 0 when the vault is full");
    }

    function testMaxDepositExceedsAVAXCap() public {
        uint256 AVAXCap = 33000e18; // Asset cap is 33,000 tokens
        uint256 depositedAssets = 32000e18; // Simulate depositing 32,000 tokens, close to the cap
        vault.setAVAXCap(AVAXCap);
        vault.deposit(depositedAssets, address(this)); // Assume deposit function updates total assets correctly

        uint256 expectedMaxDeposit = AVAXCap - depositedAssets;
        assertEq(
            vault.maxDeposit(address(this)), expectedMaxDeposit, "Max deposit should not allow exceeding the asset cap"
        );
    }

    function testMaxDepositWithZeroAVAXCap() public {
        uint256 AVAXCap = 0; // Set the asset cap to 0
        vault.setAVAXCap(AVAXCap);

        uint256 expectedMaxDeposit = 0;
        assertEq(vault.maxDeposit(address(this)), expectedMaxDeposit, "Max deposit should be 0 with a zero asset cap");
    }

    function testMaxDepositWithNoAssetsInVault() public {
        uint256 AVAXCap = 33000e18; // Set a non-zero asset cap
        vault.setAVAXCap(AVAXCap);

        uint256 expectedMaxDeposit = AVAXCap; // With no assets in vault, max deposit should equal the asset cap
        assertEq(
            vault.maxDeposit(address(this)),
            expectedMaxDeposit,
            "Max deposit should equal the asset cap with no assets in vault"
        );
    }

    function testMaxDepositAfterWithdrawals() public {
        uint256 AVAXCap = 33000e18;
        uint256 initialDeposit = 20000e18;
        uint256 withdrawalAmount = 5000e18; // Simulate a withdrawal reducing the total assets
        vault.setAVAXCap(AVAXCap);
        vault.deposit(initialDeposit, address(this)); // Assume deposit function updates total assets correctly
        vault.withdraw(withdrawalAmount, address(this), address(this)); // Assume withdrawal function updates total assets correctly

        uint256 expectedMaxDeposit = AVAXCap - (initialDeposit - withdrawalAmount);
        assertEq(
            vault.maxDeposit(address(this)),
            expectedMaxDeposit,
            "Max deposit should be adjusted correctly after withdrawals"
        );

        uint256 oneMoreThanMaxDeposit = vault.maxDeposit(address(this)) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626ExceededMaxDeposit.selector, address(this), oneMoreThanMaxDeposit, expectedMaxDeposit
            )
        );

        vault.deposit(oneMoreThanMaxDeposit, address(this)); // Assume deposit function updates total assets correctly
    }

    function testMaxDepositWithChangingAVAXCap() public {
        uint256 initialAVAXCap = 33000e18;
        uint256 newAVAXCap = 50000e18; // Increase the asset cap
        uint256 depositedAssets = 10000e18;
        vault.setAVAXCap(initialAVAXCap);
        vault.deposit(depositedAssets, address(this)); // Assume deposit function updates total assets correctly

        // Increase the asset cap
        vault.setAVAXCap(newAVAXCap);

        uint256 expectedMaxDeposit = newAVAXCap - depositedAssets;
        assertEq(vault.maxDeposit(address(this)), expectedMaxDeposit, "Max deposit should reflect the new asset cap");
    }

    function testMaxMintScenariosWithExpectedValues() public {
        uint256 AVAXCap = 33000e18; // Set the asset cap
        vault.setAVAXCap(AVAXCap);

        // Assuming the minting calculation is directly related to the asset cap and current total assets
        // For simplicity, let's assume 1 token deposited = 1 share minted (1:1 ratio)

        // Test with no assets in vault
        uint256 expectedMaxMintNoAssets = AVAXCap; // Since no assets, maxMint should allow up to the asset cap
        uint256 maxMintNoAssets = vault.maxMint(address(this));
        assertEq(maxMintNoAssets, expectedMaxMintNoAssets, "Max mint should equal asset cap with no assets in vault");

        // Deposit assets and test under normal conditions
        uint256 initialDeposit = 10000e18;
        vault.deposit(initialDeposit, address(this));
        uint256 expectedMaxMintNormal = AVAXCap - initialDeposit; // Adjusted for deposited assets
        uint256 maxMintNormal = vault.maxMint(address(this));
        assertEq(maxMintNormal, expectedMaxMintNormal, "Max mint should adjust based on deposited assets");

        // Withdraw assets and test maxMint adjustment
        uint256 withdrawalAmount = 5000e18;
        vault.withdraw(withdrawalAmount, address(this), address(this));
        uint256 expectedMaxMintAfterWithdrawal = expectedMaxMintNormal + withdrawalAmount; // Increase by the withdrawn amount
        uint256 maxMintAfterWithdrawal = vault.maxMint(address(this));
        assertEq(maxMintAfterWithdrawal, expectedMaxMintAfterWithdrawal, "Max mint should increase after withdrawals");

        // Deposit more assets to fill the vault to its cap
        uint256 additionalDepositToFill = AVAXCap - initialDeposit + withdrawalAmount;
        vault.deposit(additionalDepositToFill, address(this));
        uint256 maxMintFullVault = vault.maxMint(address(this));
        assertEq(maxMintFullVault, 0, "Max mint should be 0 when vault is full");

        // Withdraw to below the cap and check maxMint adjustment
        vault.withdraw(withdrawalAmount, address(this), address(this));
        uint256 expectedMaxMintAfterSecondWithdrawal = withdrawalAmount; // Should allow minting up to the amount withdrawn to be below cap
        uint256 maxMintAfterSecondWithdrawal = vault.maxMint(address(this));
        assertEq(
            maxMintAfterSecondWithdrawal,
            expectedMaxMintAfterSecondWithdrawal,
            "Max mint should adjust correctly after second withdrawal"
        );
    }

    function testMaxMethods() public {
        uint256 maxDelta = 1e8;

        uint256 AVAXCap = vault.AVAXCap();
        assertEq(vault.maxDeposit(address(this)), AVAXCap, "a");
        assertEq(vault.maxMint(address(this)), AVAXCap, "a");
        assertEq(vault.maxWithdraw(address(this)), 0, "a");
        assertEq(vault.maxRedeem(address(this)), 0, "a");

        vault.setAVAXCap(0);
        assertEq(vault.maxDeposit(address(this)), 0, "a");
        assertEq(vault.maxMint(address(this)), 0, "a");

        uint256 newCap = 100e18;
        vault.setAVAXCap(newCap);
        assertEq(vault.maxDeposit(address(this)), newCap, "a");
        assertEq(vault.maxMint(address(this)), newCap, "a");

        uint256 depositedAssets = newCap / 2;
        vault.deposit(depositedAssets, address(this));
        assertEq(vault.maxDeposit(address(this)), depositedAssets, "a");
        assertEq(vault.maxMint(address(this)), depositedAssets, "a");
        assertEq(vault.maxWithdraw(address(this)), depositedAssets, "a");
        assertEq(vault.maxRedeem(address(this)), depositedAssets, "a");

        // double share value
        WAVAX.transfer(address(vault), depositedAssets);
        assertEq(vault.maxDeposit(address(this)), 0, "a");
        assertEq(vault.maxMint(address(this)), 0, "a");
        assertApproxEqAbs(vault.maxWithdraw(address(this)), depositedAssets * 2, maxDelta, "a");
        assertApproxEqAbs(vault.maxRedeem(address(this)), depositedAssets, maxDelta, "a");

        // update values correctly when AVAX goes for staking
        vault.stakeOnNode(depositedAssets, nodeOp1);
        assertEq(vault.maxDeposit(address(this)), 0, "a");
        assertEq(vault.maxMint(address(this)), 0, "a");
        assertApproxEqAbs(vault.maxWithdraw(address(this)), depositedAssets, maxDelta, "a");
        assertApproxEqAbs(vault.maxRedeem(address(this)), depositedAssets / 2, maxDelta, "a");
    }

    function testCalculateAPYFromAPR() public {
        vault.setTargetAPR(1837); // Set the target APR to 18.37%
        uint256 expectedAPYFor1837 = 2001; // Expected APY in basis points (example value)
        uint256 calculatedAPYFor1837 = vault.calculateAPYFromAPR();
        assertEq(calculatedAPYFor1837, expectedAPYFor1837, "APY calculation for APR 1837 does not match expected value");
    }
}
