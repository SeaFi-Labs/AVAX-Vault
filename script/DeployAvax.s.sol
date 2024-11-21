// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WAVAXVault} from "../contracts/WAVAXVault.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "forge-std/Script.sol";

contract MyScript is Script {
    WAVAXVault vault;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address WAVAXMainnet = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
        address multisigAVAXVault = 0x73F9d1761eDd28BFEd67c7d5BbfEDf85A3783309;
        vm.startBroadcast(deployerPrivateKey);

        Upgrades.deployUUPSProxy(
            "AVAXVault.sol", abi.encodeCall(WAVAXVault.initialize, (WAVAXMainnet, multisigAVAXVault))
        );
        // vault = AVAXVault(proxy);

        // must be called from the safe
        // vault.grantRole(vault.APPROVED_NODE_OPERATOR(), originalNodeOp);

        vm.stopBroadcast();
    }
}
