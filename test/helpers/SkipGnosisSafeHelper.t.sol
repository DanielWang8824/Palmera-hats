// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.15;

import "./GnosisSafeHelper.t.sol";
import "./KeyperModuleHelper.t.sol";
import {KeyperModule} from "../../src/KeyperModule.sol";

/// @notice Helper contract handling deployment Gnosis Safe contracts
/// @custom:security-contact general@palmeradao.xyz
contract SkipGnosisSafeHelper is GnosisSafeHelper, KeyperModuleHelper {
    GnosisSafeProxyFactory public proxyFactory;
    GnosisSafe public gnosisSafeContract;
    GnosisSafeProxy safeProxy;
    uint256 nonce;

    // Create new gnosis safe test environment
    // Deploy main safe contracts (GnosisSafeProxyFactory, GnosisSafe mastercopy)
    // Init signers
    // Permit create a specific numbers of owners
    // Deploy a new safe proxy
    function setupSeveralSafeEnv(uint256 initOwners)
        public
        override
        returns (address)
    {
        start();
        gnosisMasterCopy = address(gnosisSafeContract);
        salt = Random.randint();
        bytes memory emptyData = abi.encodePacked(salt);
        address gnosisSafeProxy = newSafeProxy(emptyData);
        gnosisSafe = GnosisSafe(payable(gnosisSafeProxy));
        initOnwers(initOwners);

        // Setup gnosis safe with 3 owners, 1 threshold
        address[] memory owners = new address[](3);
        owners[0] = vm.addr(privateKeyOwners[0]);
        owners[1] = vm.addr(privateKeyOwners[1]);
        owners[2] = vm.addr(privateKeyOwners[2]);
        // Update privateKeyOwners used
        updateCount(3);

        gnosisSafe.setup(
            owners,
            uint256(1),
            address(0x0),
            emptyData,
            address(0x0),
            address(0x0),
            uint256(0),
            payable(address(0x0))
        );

        return address(gnosisSafe);
    }

    /// @notice Setup the environment for the test
    function start() public {
        proxyFactory =
            GnosisSafeProxyFactory(vm.envAddress("PROXY_FACTORY_ADDRESS"));
        gnosisSafeContract =
            GnosisSafe(payable(vm.envAddress("MASTER_COPY_ADDRESS")));
    }

    /// function to set the KeyperModule address
    /// @param keyperModule address of the KeyperModule
    function setKeyperModule(address keyperModule) public override {
        keyperModuleAddr = keyperModule;
        keyper = KeyperModule(keyperModuleAddr);
    }

    /// function to create a new Keyper Safe
    /// @param numberOwners amount of owners to initialize
    /// @param threshold amount of signatures required to execute a transaction
    /// @return address of the new Keyper Safe
    function newKeyperSafe(uint256 numberOwners, uint256 threshold)
        public
        override
        returns (address)
    {
        require(
            privateKeyOwners.length >= numberOwners,
            "not enough initialized owners"
        );
        require(
            countUsed + numberOwners <= privateKeyOwners.length,
            "No private keys available"
        );
        require(keyperModuleAddr != address(0), "Keyper module not set");
        address[] memory owners = new address[](numberOwners);
        for (uint256 i = 0; i < numberOwners; i++) {
            owners[i] = vm.addr(privateKeyOwners[i + countUsed]);
            countUsed++;
        }
        bytes memory emptyData = abi.encodePacked(Random.randint());
        bytes memory initializer = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,
            threshold,
            address(0x0),
            emptyData,
            address(0x0),
            address(0x0),
            uint256(0),
            payable(address(0x0))
        );

        address gnosisSafeProxy = newSafeProxy(initializer);
        gnosisSafe = GnosisSafe(payable(address(gnosisSafeProxy)));

        // Enable module
        bool result = enableModuleTx(address(gnosisSafe));
        require(result == true, "failed enable module");

        // Enable Guard
        result = enableGuardTx(address(gnosisSafe));
        require(result == true, "failed enable guard");
        return address(gnosisSafe);
    }

    /// function to create a new Safe Proxy
    /// @param initializer bytes data to initialize the Safe
    /// @return address of the new Safe Proxy
    function newSafeProxy(bytes memory initializer) public returns (address) {
        safeProxy = proxyFactory.createProxyWithNonce(
            address(gnosisSafeContract), initializer, nonce
        );
        nonce++;
        return address(safeProxy);
    }
}
