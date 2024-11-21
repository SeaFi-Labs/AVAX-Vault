// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WAVAXVault} from "../contracts/WAVAXVault.sol";
import {MockTokenWAVAX} from "../test/mocks/MockTokenWAVAX.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "forge-std/Script.sol";

contract MyScript is Script {
    MockTokenWAVAX public ggpToken;
    WAVAXVault vault;

    function run() external {
        address devAddress4 = 0xcafea1A2c9F4Af0Aaf1d5C4913cb8BA4bf0F9842;
        address devAddress1 = 0x853Fce5539C4DDCF2F539D3DE1e94F3F5b94Fa43;
        address devAddress2 = 0xc13eDA6bFF669b3858650bc34Dd8802eF93D31E9;
        address devAddress3 = 0x232F3d6Ce02758aA4c592f115c995A34ADeAbE36;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ggpToken = new MockTokenWAVAX(devAddress4);
        Upgrades.deployUUPSProxy(
            "WAVAXVault.sol", abi.encodeCall(WAVAXVault.initialize, (address(ggpToken), devAddress4))
        );

        ggpToken.transfer(devAddress1, 10000e18);
        ggpToken.transfer(devAddress2, 10000e18);
        ggpToken.transfer(devAddress3, 10000e18);

        vm.stopBroadcast();
    }
}
