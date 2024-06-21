// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {GnosisSafeProxyFactory} from
    "@safe-contracts/proxies/GnosisSafeProxyFactory.sol";
import {GnosisSafeProxy} from "@safe-contracts/proxies/GnosisSafeProxy.sol";
import {GnosisSafe} from "@safe-contracts/GnosisSafe.sol";
import {IProxyCreationCallback} from
    "@safe-contracts/proxies/IProxyCreationCallback.sol";

/// @title DeploySafeFactory
/// @custom:security-contact general@palmeradao.xyz
contract DeploySafeFactory is Script {
    GnosisSafeProxyFactory public proxyFactory;
    GnosisSafe public safeContract;
    GnosisSafeProxy safeProxy;

    // Deploys a GnosisSafeProxyFactory & GnosisSafe contract
    function run() public {
        vm.startBroadcast();
        proxyFactory = new GnosisSafeProxyFactory();
        safeContract = new GnosisSafe();
        vm.stopBroadcast();
    }

    function newSafeProxy(bytes memory initializer) public returns (address) {
        uint256 nonce = uint256(keccak256(initializer));
        safeProxy = proxyFactory.createProxyWithNonce(
            address(safeContract), initializer, nonce
        );
        return address(safeProxy);
    }
}
