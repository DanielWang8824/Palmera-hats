// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import "../src/PalmeraRoles.sol";

/// @title Deploy PalmeraRoles
/// @custom:security-contact general@palmeradao.xyz
contract DeployKeyperRoles is Script {
    function run() public {
        // Solenv.config();
        address keyperModuleMock = address(0xBEEF);
        deploy(keyperModuleMock);
    }

    function deploy(address keyperModule) internal {
        vm.startBroadcast();
        PalmeraRoles roles = new PalmeraRoles(keyperModule);
        vm.stopBroadcast();
    }
}
