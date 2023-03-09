// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import "@solenv/Solenv.sol";
import {Constants} from "../libraries/Constants.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";

contract DeployLibraries is Script {
    function run() public {
        vm.startBroadcast();
        // Deploy Constants Libraries
        address constantsAddr = deployCode("Constants.sol");
        console.log("Constants deployed at: ", constantsAddr);
        // Deploy DataTypes Libraries
        address dataTypesAddr = deployCode("DataTypes.sol");
        console.log("DataTypes deployed at: ", dataTypesAddr);
        // Deploy Errors Libraries
        address errorsAddr = deployCode("Errors.sol");
        console.log("Errors deployed at: ", errorsAddr);
        // Deploy Events Libraries
        address eventsAddr = deployCode("Events.sol");
        console.log("Events deployed at: ", eventsAddr);
        vm.stopBroadcast();
    }
}
