// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.20;

import {WAVAXVault} from "../../contracts/WAVAXVault.sol";

/// @custom:oz-upgrades-from WAVAXVault
contract WAVAXVaultV2 is WAVAXVault {
    function newMethod() public pure returns (string memory) {
        return "meow";
    }
}
