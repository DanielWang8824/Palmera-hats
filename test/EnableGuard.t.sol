// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "./helpers/GnosisSafeHelper.t.sol";
import {KeyperModule, Errors, Constants} from "../src/KeyperModule.sol";
import {KeyperGuard} from "../src/KeyperGuard.sol";
import {StorageAccessible} from "@safe-contracts/common/StorageAccessible.sol";

/// @title TestEnableModule
/// @custom:security-contact general@palmeradao.xyz
contract TestEnableGuard is Test {
    KeyperModule keyperModule;
    KeyperGuard keyperGuard;
    GnosisSafeHelper gnosisHelper;
    address gnosisSafeAddr;

    /// @notice Set up the environment for testing
    function setUp() public {
        // Init new safe
        gnosisHelper = new GnosisSafeHelper();
        gnosisSafeAddr = gnosisHelper.setupSafeEnv();
        // Init KeyperModule
        address masterCopy = gnosisHelper.gnosisMasterCopy();
        address safeFactory = address(gnosisHelper.safeFactory());
        address rolesAuthority = address(0xBEEF);
        uint256 maxTreeDepth = 50;
        keyperModule = new KeyperModule(
            masterCopy, safeFactory, rolesAuthority, maxTreeDepth
        );
        keyperGuard = new KeyperGuard(address(keyperModule));
        gnosisHelper.setKeyperModule(address(keyperModule));
        gnosisHelper.setKeyperGuard(address(keyperGuard));
    }

    /// @notice Test enabling the KeyperModule
    function testEnableKeyperModule() public {
        bool result = gnosisHelper.enableModuleTx(gnosisSafeAddr);
        assertEq(result, true);
        // Verify module has been enabled
        bool isKeyperModuleEnabled =
            gnosisHelper.gnosisSafe().isModuleEnabled(address(keyperModule));
        assertEq(isKeyperModuleEnabled, true);
    }

    /// @notice Test enabling the KeyperGuard
    function testEnableKeyperGuard() public {
        bool result = gnosisHelper.enableGuardTx(gnosisSafeAddr);
        assertEq(result, true);
        // Verify guard has been enabled
        address guardAddress = abi.decode(
            StorageAccessible(gnosisSafeAddr).getStorageAt(
                uint256(Constants.GUARD_STORAGE_SLOT), 2
            ),
            (address)
        );
        assertEq(guardAddress, address(keyperGuard));
    }
}
