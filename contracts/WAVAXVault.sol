// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.20;

import "forge-std/console.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IWAVAX} from "./interfaces/WAVAX.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title WAVAXVault
/// @notice This contract implements a vault for staking WAVAX tokens, offering functionalities to stake tokens,
///         distribute rewards, and manage deposits from staking with a focus on access control and upgradeability.
/// @dev The contract uses OpenZeppelin's upgradeable contract patterns, including ERC4626 for tokenized vault,
///      UUPS for upgradeability, Ownable2Step for ownership management, and AccessControl for role-based permissions.
contract WAVAXVault is
    Initializable,
    Ownable2StepUpgradeable,
    ERC4626Upgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;
    using Address for address;

    bytes32 public constant APPROVED_NODE_OPERATOR = keccak256("APPROVED_NODE_OPERATOR");

    event AVAXCapUpdated(uint256 newMax);
    event TargetAPRUpdated(uint256 newTargetAPR);
    event WithdrawnForStaking(address indexed caller, uint256 assets);
    event DepositedFromStaking(address indexed caller, uint256 amount);

    // address public WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    IWAVAX public WAVAX;
    uint256 public stakingTotalAssets;
    uint256 public AVAXCap;
    uint256 public targetAPR;
    uint256 public lastRewardUpdate; // Timestamp of the last reward update

    /// @notice Restricts functions to the contract owner or approved node operators only.
    modifier onlyOwnerOrApprovedNodeOperator() {
        require(
            owner() == _msgSender() || hasRole(APPROVED_NODE_OPERATOR, _msgSender()),
            "Caller is not the owner or an approved node operator"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the vault with necessary parameters and settings.
    /// @dev Sets up ERC20 token details, initializes inherited contracts, sets the initial owner, AVAXCap, and targetAPR.
    /// @param _initialOwner The address that will be granted initial ownership of the vault.
    function initialize(address _wavax, address _initialOwner) external initializer {
        __ERC20_init("SeaFi AVAX Vault", "xAVAX");
        __ERC4626_init(IERC20(_wavax));
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __AccessControl_init();
        _transferOwnership(_initialOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);
        AVAXCap = 20000e18; // Starting asset cap
        targetAPR = 1405; // Starting target APR
        stakingTotalAssets = 0;
        WAVAX = IWAVAX(_wavax);
        lastRewardUpdate = block.timestamp;
    }

    /// @notice Sets the maximum cap for WAVAX deposits in the vault.
    /// @param WAVAXDepositLimit The new deposit limit for the vault.
    function setAVAXCap(uint256 WAVAXDepositLimit) external onlyOwner {
        AVAXCap = WAVAXDepositLimit;
        emit AVAXCapUpdated(AVAXCap);
    }

    /// @notice Sets the target APR for the vault's staking rewards.
    /// @param target The new target APR as a percentage in basis points.
    function setTargetAPR(uint256 target) external onlyOwner {
        targetAPR = target;
        emit TargetAPRUpdated(targetAPR);
    }

    function depositAVAX() public payable returns (uint256 shares) {
        uint256 assets = msg.value;

        uint256 maxAssets = maxDeposit(_msgSender());
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(_msgSender(), assets, maxAssets);
        }
        // Check for rounding error since we round down in previewDeposit.
        if ((shares = previewDeposit(assets)) == 0) {
            revert("shares must be greater than 0");
        }

        emit Deposit(_msgSender(), _msgSender(), assets, shares);

        WAVAX.deposit{value: assets}();
        _mint(_msgSender(), shares);

        return shares;
    }

    function redeemAVAX(uint256 shares) public returns (uint256 assets) {
        uint256 maxShares = maxRedeem(_msgSender());
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(_msgSender(), shares, maxShares);
        }
        // Check for rounding error since we round down in previewRedeem.
        if ((assets = previewRedeem(shares)) == 0) {
            revert("no redeem");
        }
        _burn(_msgSender(), shares);

        WAVAX.withdraw(assets);

        Address.sendValue(payable(_msgSender()), assets);
        emit Withdraw(_msgSender(), _msgSender(), _msgSender(), assets, shares);

        return assets;
    }

    /// @notice Stakes a specified amount on behalf of a node operator.
    /// @param amount The amount of WAVAX tokens to stake.
    /// @param nodeOp The address of the node operator on whose behalf the staking is done.
    function stakeOnNode(uint256 amount, address nodeOp) external onlyOwnerOrApprovedNodeOperator {
        _updateRewards();
        _stakeOnNode(amount, nodeOp);
    }

    function updateRewards() external onlyOwnerOrApprovedNodeOperator {
        _updateRewards();
    }
    /// @notice Allows depositing tokens back into the vault from staking, adjusting the staking total assets accordingly.
    /// @param amount The amount of WAVAX tokens to deposit back into the vault from staking.

    function depositFromStaking(uint256 amount) external onlyOwnerOrApprovedNodeOperator {
        if (amount > stakingTotalAssets) {
            revert("Cant deposit more than the stakingTotalAssets");
        }
        stakingTotalAssets -= amount;
        _updateRewards();
        emit DepositedFromStaking(_msgSender(), amount);
        IERC20(asset()).safeTransferFrom(_msgSender(), address(this), amount);
    }

    /// @notice Returns the total assets under management, including both staked and vault-held assets.
    /// @return The total assets under management in the vault.
    function totalAssets() public view override returns (uint256) {
        return stakingTotalAssets + getUnderlyingBalance();
    }

    function getPendingRewards() public view returns (uint256) {
        if (block.timestamp > lastRewardUpdate) {
            uint256 timeElapsed = block.timestamp - lastRewardUpdate;
            uint256 newRewards = (totalAssets() * targetAPR * timeElapsed) / (10000 * 365 days);
            return newRewards;
        }
        return 0;
    }

    /// @notice Calculates the maximum deposit amount for a given address, respecting the AVAXCap.
    /// @return The maximum amount that can be deposited by the receiver.
    function maxDeposit(address) public view override returns (uint256) {
        uint256 total = totalAssets();
        return AVAXCap > total ? AVAXCap - total : 0;
    }

    /// @notice Calculates the maximum amount of shares that can be minted for a given address based on the AVAXCap.
    /// @param receiver The address for which the maximum mintable shares are calculated.
    /// @return The maximum number of shares that can be minted for the receiver.
    function maxMint(address receiver) public view override returns (uint256) {
        uint256 maxDepositAmount = maxDeposit(receiver);
        return convertToShares(maxDepositAmount);
    }

    /// @notice Calculates the maximum amount of underlying assets that can be withdrawn by the owner based on their share balance.
    /// @param shareOwner The address of the shares shareOwner.
    /// @return The maximum amount of underlying assets that can be withdrawn.
    function maxWithdraw(address shareOwner) public view override returns (uint256) {
        uint256 assetsOwnedByOwner = convertToAssets(balanceOf(shareOwner));
        uint256 amountInVault = getUnderlyingBalance();
        if (amountInVault > assetsOwnedByOwner) return assetsOwnedByOwner;
        return amountInVault;
    }

    /// @notice Calculates the maximum amount of shares that can be redeemed by the owner without exceeding the available balance.
    /// @param shareOwner The address of the shares shareOwner.
    /// @return The maximum amount of shares that can be redeemed.
    function maxRedeem(address shareOwner) public view override returns (uint256) {
        uint256 maxWithdrawAmount = maxWithdraw(shareOwner);
        return convertToShares(maxWithdrawAmount);
    }

    /// @notice Calculates the rewards based on the current staked amount.
    /// @return The amount of rewards generated based on the current staked assets.
    function getRewardsBasedOnCurrentStakedAmount() public view returns (uint256) {
        return previewRewardsAtStakedAmount(stakingTotalAssets);
    }

    /// @notice Previews the rewards for a given stake amount based on the target APR.
    /// @param stakeAmount The amount of WAVAX tokens staked.
    /// @return The calculated rewards for the given staked amount.
    function previewRewardsAtStakedAmount(uint256 stakeAmount) public view returns (uint256) {
        return (targetAPR * stakeAmount) / 10000 / 13;
    }

    /// @notice Calculates the APY from the target APR considering compounding effects.
    /// @return The calculated APY as a percentage in basis points.
    function calculateAPYFromAPR() public view returns (uint256) {
        uint256 compoundingPeriods = 13; // Assuming compounding every 28 days
        uint256 aprFraction = targetAPR * 1e14; // Convert APR from basis points to a fraction
        uint256 oneScaled = 1e18; // Scale factor for precision
        uint256 compoundBase = oneScaled + aprFraction / compoundingPeriods;
        uint256 apyScaled = oneScaled;
        for (uint256 i = 0; i < compoundingPeriods; i++) {
            apyScaled = (apyScaled * compoundBase) / oneScaled;
        }
        return (apyScaled - oneScaled) / 1e14; // Convert back to basis points
    }

    /// @notice Retrieves the balance of the underlying WAVAX tokens held by the vault.
    /// @return The balance of WAVAX tokens held in the vault.
    function getUnderlyingBalance() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @dev Internal function to stake WAVAX tokens on a node.
    /// @param amount The amount of WAVAX tokens to stake.
    /// @param nodeOp The address of the node operator.
    function _stakeOnNode(uint256 amount, address nodeOp) internal {
        _checkRole(APPROVED_NODE_OPERATOR, nodeOp);
        stakingTotalAssets += amount;
        IERC20(asset()).safeTransfer(nodeOp, amount); // TODO MAKE SURE THIS IS GOOD
        emit WithdrawnForStaking(nodeOp, amount);
    }

    function _updateRewards() internal {
        uint256 newRewards = getPendingRewards();
        stakingTotalAssets += newRewards; // Increase total assets
        lastRewardUpdate = block.timestamp;
    }

    /// @dev Ensures that only the owner can authorize upgrades to the contract.
    /// @param newImplementation The address of the new contract implementation.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice only accept AVAX via fallback from the WAVAX contract
    receive() external payable {
        require(_msgSender() == address(WAVAX));
    }
}
