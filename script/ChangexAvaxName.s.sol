// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {WAVAXVaultV2} from "../contracts/v2/WAVAXVaultV2.sol";
import {WAVAXVaultV3} from "../contracts/v3/WAVAXVaultV3.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {WAVAX} from "../contracts/TokenMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ChangexAvaxName is Script {
    address proxyAddress = 0x36213ca1483869c5616be738Bf8da7C9B34Ace8d;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_SENDER"); // <- update in .env
        vm.startBroadcast(deployerPrivateKey);

        WAVAXVaultV3 newImplementationV3 = new WAVAXVaultV3();

        vm.stopBroadcast();
        console.log("New implementation deployed to:", address(newImplementationV3));
        console.log("Proxy upgraded at:", proxyAddress);
    }

    // Command:
    // $ forge script script/ChangexAvaxName.s.sol:ChangexAvaxName --rpc-url avax --broadcast

    // Verification
    // $ forge verify-contract <new implementation address> contracts/v3/WAVAXVaultV3.sol:WAVAXVaultV3 --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan' --etherscan-api-key "verifyContract" --num-of-optimizations 200 --compiler-version 0.8.20
}