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

        address payable proxy = payable(
            Upgrades.deployUUPSProxy(
                "WAVAXVault.sol", abi.encodeCall(WAVAXVault.initialize, (address(WAVAX), address(this)))
            )
        );
        vault = WAVAXVault(payable(proxy));

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

    function testDepositAVAX() public {
        uint256 depositAmount = 10 ether; // 10 AVAX
        uint256 initialVaultBalance = 0;
        uint256 initialUserShares = 0;

        // Fund the test address with AVAX
        vm.deal(address(this), depositAmount);

        // Call depositAVAX and verify shares returned
        uint256 shares = vault.depositAVAX{value: depositAmount}();
        uint256 expectedShares = depositAmount; // Assuming 1:1 ratio for AVAX to shares

        assertEq(shares, expectedShares, "Shares returned from depositAVAX should equal deposit amount");
        assertEq(
            vault.balanceOf(address(this)), initialUserShares + shares, "User shares should increase by deposit amount"
        );
        assertEq(
            vault.getUnderlyingBalance(),
            initialVaultBalance + depositAmount,
            "Vault's AVAX balance should increase by deposit amount"
        );
    }

    function testDepositAVAXRevertsWhenZeroValue() public {
        vm.expectRevert("shares must be greater than 0"); // Adjust revert message as per your contract
        vault.depositAVAX{value: 0}();
    }

    function testRedeemAVAX() public {
        address randomUser1 = address(0x777);
        vm.startPrank(randomUser1);
        uint256 depositAmount = 10 ether; // 10 AVAX

        // Fund the test address with AVAX
        vm.deal(randomUser1, depositAmount);

        // Deposit AVAX
        uint256 shares = vault.depositAVAX{value: depositAmount}();
        console.log("Shares: ", shares);
        uint256 initialVaultBalance = 0;
        uint256 initialUserBalance = 0;
        // Redeem the shares and verify assets returned
        uint256 assets = vault.redeemAVAX(shares);
        console.log("Assets: ", assets);

        uint256 expectedAssets = depositAmount; // Assuming 1:1 ratio for shares to AVAX

        assertEq(assets, expectedAssets, "Assets returned from redeemAVAX should equal deposit amount");
        assertEq(vault.balanceOf(randomUser1), 0, "User shares should be zero after redeeming all shares");
        assertEq(address(vault).balance, 0, "Vault's AVAX balance should decrease by redeemed amount");
        assertEq(randomUser1.balance, initialUserBalance + assets, "User balance should increase by redeemed amount");
        console.log("Assets2: ", assets);

        vm.stopPrank();
    }

    function testRedeemAVAXRevertsWhenNotEnoughShares() public {
        uint256 depositAmount = 10 ether; // 10 AVAX

        // Fund the test address with AVAX
        vm.deal(address(this), depositAmount);

        // Deposit AVAX
        uint256 shares = vault.depositAVAX{value: depositAmount}();

        vm.expectRevert();
        vault.redeemAVAX(shares + 1);
    }

    function testDepositAndRedeemAVAX() public {
        address randomUser1 = address(0x777);
        vm.startPrank(randomUser1);
        uint256 depositAmount = 5 ether; // 5 AVAX
        uint256 depositAmount2 = 3 ether; // 3 AVAX

        // Fund the test address with AVAX
        vm.deal(randomUser1, depositAmount + depositAmount2);

        uint256 initialUserBalance = randomUser1.balance;

        // First deposit
        uint256 shares1 = vault.depositAVAX{value: depositAmount}();
        assertEq(vault.balanceOf(randomUser1), shares1, "Shares should equal first deposit amount");

        // Second deposit
        uint256 shares2 = vault.depositAVAX{value: depositAmount2}();
        assertEq(vault.balanceOf(randomUser1), shares1 + shares2, "Total shares should equal sum of deposits");

        // Redeem all shares
        uint256 totalShares = shares1 + shares2;
        uint256 assetsRedeemed = vault.redeemAVAX(totalShares);
        assertEq(assetsRedeemed, depositAmount + depositAmount2, "Assets redeemed should match total deposits");
        assertEq(
            randomUser1.balance,
            initialUserBalance - (depositAmount + depositAmount2) + assetsRedeemed,
            "User balance should reflect redeemed AVAX"
        );
        assertEq(vault.balanceOf(randomUser1), 0, "User shares should be zero after redeeming all shares");
    }

    function testDepositAVAXDoesNotImpactRegularDeposit() public {
        uint256 tokenDepositAmount = 10 ether; // Token deposit
        uint256 avaxDepositAmount = 5 ether; // AVAX deposit

        // Fund the contract with AVAX and tokens
        vm.deal(address(this), avaxDepositAmount);

        // Regular deposit
        WAVAX.approve(address(vault), tokenDepositAmount);
        uint256 tokenShares = vault.deposit(tokenDepositAmount, address(this));
        assertEq(vault.balanceOf(address(this)), tokenShares, "Token shares should match deposit");

        // AVAX deposit
        uint256 avaxShares = vault.depositAVAX{value: avaxDepositAmount}();
        assertEq(vault.balanceOf(address(this)), tokenShares + avaxShares, "Total shares should include AVAX deposit");

        // Verify vault balance
        assertEq(
            vault.totalAssets(), tokenDepositAmount + avaxDepositAmount, "Total assets should reflect both deposits"
        );
    }

    function testRedeemAVAXDoesNotImpactRegularRedeem() public {
        uint256 tokenDepositAmount = 10 ether; // Token deposit
        uint256 avaxDepositAmount = 5 ether; // AVAX deposit
        address randomUser1 = address(0x777);
        WAVAX.transfer(randomUser1, tokenDepositAmount);
        vm.startPrank(randomUser1);

        // Fund the contract with AVAX and tokens
        vm.deal(randomUser1, avaxDepositAmount);

        // Perform deposits
        WAVAX.approve(address(vault), tokenDepositAmount);
        uint256 tokenShares = vault.deposit(tokenDepositAmount, randomUser1);
        uint256 avaxShares = vault.depositAVAX{value: avaxDepositAmount}();

        // Redeem token shares
        uint256 tokenAssets = vault.redeem(tokenShares, randomUser1, randomUser1);
        assertEq(tokenAssets, tokenDepositAmount, "Redeemed token assets should match deposit");

        // Redeem AVAX shares
        uint256 avaxAssets = vault.redeemAVAX(avaxShares);
        assertEq(avaxAssets, avaxDepositAmount, "Redeemed AVAX assets should match deposit");

        // Verify total assets are zero
        assertEq(vault.totalAssets(), 0, "Total assets should be zero after all redemptions");
    }

    function testDepositAVAXRevertsWhenCapExceeded() public {
        uint256 avaxCap = 10 ether;
        vault.setAVAXCap(avaxCap);

        vm.deal(address(this), avaxCap + 1 ether);
        vm.expectRevert();
        vault.depositAVAX{value: avaxCap + 1 ether}();
    }

    function testRedeemAVAXFailsIfNoShares() public {
        uint256 depositAmount = 10 ether;
        vm.deal(address(this), depositAmount);

        vm.expectRevert();
        vault.redeemAVAX(1 ether);
    }

    function testDepositAndRedeemAVAXMultipleUsers() public {
        address user1 = address(0x111);
        address user2 = address(0x222);

        uint256 user1Deposit = 7 ether;
        uint256 user2Deposit = 5 ether;

        // Fund users
        vm.deal(user1, user1Deposit);
        vm.deal(user2, user2Deposit);

        // User 1 deposits
        vm.startPrank(user1);
        uint256 user1Shares = vault.depositAVAX{value: user1Deposit}();
        assertEq(vault.balanceOf(user1), user1Shares, "User 1 shares should match deposit");
        vm.stopPrank();

        // User 2 deposits
        vm.startPrank(user2);
        uint256 user2Shares = vault.depositAVAX{value: user2Deposit}();
        assertEq(vault.balanceOf(user2), user2Shares, "User 2 shares should match deposit");
        vm.stopPrank();

        // Check total assets in vault
        assertEq(vault.totalAssets(), user1Deposit + user2Deposit, "Total assets should reflect both deposits");

        // Users redeem their shares
        vm.startPrank(user1);
        uint256 user1Assets = vault.redeemAVAX(user1Shares);
        assertEq(user1Assets, user1Deposit, "User 1 assets should match redeemed amount");
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 user2Assets = vault.redeemAVAX(user2Shares);
        assertEq(user2Assets, user2Deposit, "User 2 assets should match redeemed amount");
        vm.stopPrank();

        // Check final vault state
        assertEq(vault.totalAssets(), 0, "Total assets should be zero after all redemptions");
        assertEq(vault.balanceOf(user1), 0, "User 1 shares should be zero after redemption");
        assertEq(vault.balanceOf(user2), 0, "User 2 shares should be zero after redemption");
    }

    function testDepositAVAXWithLowCap() public {
        uint256 avaxCap = 5 ether;
        uint256 depositAmount = 10 ether;

        vault.setAVAXCap(avaxCap);
        vm.deal(address(this), depositAmount);

        vm.expectRevert();
        vault.depositAVAX{value: depositAmount}();

        uint256 validDeposit = avaxCap;
        uint256 shares = vault.depositAVAX{value: validDeposit}();
        assertEq(shares, validDeposit, "Shares should match valid deposit amount");
        assertEq(vault.totalAssets(), validDeposit, "Total assets should reflect valid deposit");
    }

    function testPartialRedeemAVAX() public {
        address randomUser1 = address(0x777);
        vm.startPrank(randomUser1);
        uint256 depositAmount = 10 ether;

        vm.deal(randomUser1, depositAmount);

        // Deposit AVAX
        uint256 shares = vault.depositAVAX{value: depositAmount}();

        // Redeem half of the shares
        uint256 halfShares = shares / 2;
        uint256 assets = vault.redeemAVAX(halfShares);
        uint256 expectedAssets = depositAmount / 2;

        assertEq(assets, expectedAssets, "Redeemed assets should match half of the deposit");
        assertEq(
            vault.balanceOf(randomUser1), shares - halfShares, "Remaining shares should match after partial redemption"
        );
    }
}
