// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./../contracts/WAVAXVault.sol";
import "./../contracts/v2/WAVAXVaultV2.sol";

import "forge-std/Script.sol";

// Run for anvil network only
contract AnvilScripts is Script {
    address owner = 0x73F9d1761eDd28BFEd67c7d5BbfEDf85A3783309;
    address rewardsSyncer = 0x804C8fC862c342c077fB04614E1C5E8E2C85b6b5;
    WAVAXVaultV2 vault = WAVAXVaultV2(payable(0x36213ca1483869c5616be738Bf8da7C9B34Ace8d));

    function run() public {
        vm.startBroadcast(owner);
        _grantRole();
        vm.stopBroadcast();
    }

    function _grantRole() public {
        vault.grantRole(vault.REWARDS_SYNCER(), rewardsSyncer);
    }

    function _upgrade() internal {
        WAVAXVaultV2 v2 = new WAVAXVaultV2();
        vault.upgradeToAndCall(address(v2), "");
    }
}
