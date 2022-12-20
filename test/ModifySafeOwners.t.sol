// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SigningUtils.sol";
import "./helpers/GnosisSafeHelper.t.sol";
import "./helpers/KeyperModuleHelper.t.sol";
import "./helpers/ReentrancyAttackHelper.t.sol";
import "./helpers/KeyperSafeBuilder.t.sol";
import "./helpers/DeployHelper.t.sol";
import {Constants} from "../libraries/Constants.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {KeyperModule, IGnosisSafe} from "../src/KeyperModule.sol";
import {KeyperRoles} from "../src/KeyperRoles.sol";
import {DenyHelper} from "../src/DenyHelper.sol";
import {CREATE3Factory} from "@create3/CREATE3Factory.sol";
import {Attacker} from "../src/ReentrancyAttack.sol";
import {console} from "forge-std/console.sol";

contract ModifySafeOwners is DeployHelper, SigningUtils {
    function setUp() public {
        DeployHelper.deployAllContracts();
    }

    // ! ********************* addOwnerWithThreshold Test ***********************

    // Caller Type: EOA
    // Caller Role: SAFE_LEAD_MODIFY_OWNERS_ONLY of safeGroupA1
    // TargerSafe: safeGroupA1
    // TargetSafe Type: safe
    function testCan_AddOwnerWithThreshold_SAFE_LEAD_MODIFY_OWNERS_ONLY_as_EOA_is_TARGETS_LEAD(
    ) public {
        (uint256 rootId, uint256 groupIdA1) =
            keyperSafeBuilder.setupRootOrgAndOneGroup(orgName, groupA1Name);

        address rootAddr = keyperModule.getGroupSafeAddress(rootId);
        address groupA1Addr = keyperModule.getGroupSafeAddress(groupIdA1);
        address userLeadModifyOwnersOnly = address(0x123);

        vm.startPrank(rootAddr);
        keyperModule.setRole(
            DataTypes.Role.SAFE_LEAD_MODIFY_OWNERS_ONLY,
            userLeadModifyOwnersOnly,
            groupIdA1,
            true
        );
        vm.stopPrank();

        gnosisHelper.updateSafeInterface(groupA1Addr);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        bytes32 orgHash = keyperModule.getOrgHashBySafe(groupA1Addr);

        vm.startPrank(userLeadModifyOwnersOnly);
        address newOwner = address(0xaaaf);
        keyperModule.addOwnerWithThreshold(
            newOwner, threshold + 1, groupA1Addr, orgHash
        );

        assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold + 1);
        assertEq(gnosisHelper.gnosisSafe().isOwner(newOwner), true);
    }

    // Caller Info: SAFE_LEAD_MODIFY_OWNERS_ONLY(role), SAFE(type), groupSafe(hierachie)
    // TargetSafe Type: Child from same hierachical tree
    function testCan_AddOwnerWithThreshold_SAFE_LEAD_MODIFY_OWNERS_ONLY_as_SAFE_is_TARGETS_LEAD(
    ) public {
        (uint256 rootIdA, uint256 groupIdA1,, uint256 groupIdB1) =
        keyperSafeBuilder.setupTwoRootOrgWithOneGroupEach(
            orgName, groupA1Name, root2Name, groupBName
        );

        address rootAddrA = keyperModule.getGroupSafeAddress(rootIdA);
        address groupBAddr = keyperModule.getGroupSafeAddress(groupIdB1);
        address groupAAddr = keyperModule.getGroupSafeAddress(groupIdA1);
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddrA);

        vm.startPrank(rootAddrA);
        keyperModule.setRole(
            DataTypes.Role.SAFE_LEAD_MODIFY_OWNERS_ONLY,
            groupBAddr,
            groupIdA1,
            true
        );
        vm.stopPrank();
        assertEq(keyperModule.isSafeLead(groupIdA1, groupBAddr), true);

        // Get groupA signers info
        gnosisHelper.updateSafeInterface(groupAAddr);
        address[] memory groupA1Owners = gnosisHelper.gnosisSafe().getOwners();
        address newOwner = address(0xDEF);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        assertEq(gnosisHelper.gnosisSafe().isOwner(groupA1Owners[1]), true);

        // GroupB AddOwnerWithThreshold from groupA
        gnosisHelper.updateSafeInterface(groupBAddr);
        bool result = gnosisHelper.addOwnerWithThresholdTx(
            newOwner, threshold, groupAAddr, orgHash
        );
        assertEq(result, true);

        gnosisHelper.updateSafeInterface(groupAAddr);
        assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold);
        assertEq(
            gnosisHelper.gnosisSafe().getOwners().length,
            groupA1Owners.length + 1
        );
        assertEq(gnosisHelper.gnosisSafe().isOwner(newOwner), true);
    }

    function testCan_AddOwnerWithThreshold_SUPER_SAFE_as_SAFE_is_TARGETS_SUPER_SAFE(
    ) public {
        (, uint256 groupIdA1, uint256 childIdA) = keyperSafeBuilder
            .setupOrgThreeTiersTree(orgName, groupA1Name, subGroupA1Name);

        address groupAAddr = keyperModule.getGroupSafeAddress(groupIdA1);
        address childAAddr = keyperModule.getGroupSafeAddress(childIdA);

        bytes32 orgHash = keyperModule.getOrgHashBySafe(groupAAddr);

        // Get groupA signers info
        gnosisHelper.updateSafeInterface(childAAddr);
        address[] memory childA1Owners = gnosisHelper.gnosisSafe().getOwners();
        address newOwner = address(0xDEF);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        assertEq(gnosisHelper.gnosisSafe().isOwner(childA1Owners[1]), true);

        // GroupB AddOwnerWithThreshold from groupA
        gnosisHelper.updateSafeInterface(groupAAddr);
        bool result = gnosisHelper.addOwnerWithThresholdTx(
            newOwner, threshold, childAAddr, orgHash
        );
        assertEq(result, true);

        gnosisHelper.updateSafeInterface(childAAddr);
        assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold);
        assertEq(
            gnosisHelper.gnosisSafe().getOwners().length,
            childA1Owners.length + 1
        );
        assertEq(gnosisHelper.gnosisSafe().isOwner(newOwner), true);
    }

    function testCan_AddOwnerWithThreshold_ROOT_SAFE_as_SAFE_is_TARGETS_ROOT_SAFE(
    ) public {
        (uint256 rootIdA, uint256 groupIdA1,) = keyperSafeBuilder
            .setupOrgThreeTiersTree(orgName, groupA1Name, subGroupA1Name);

        address rootAddrA = keyperModule.getGroupSafeAddress(rootIdA);
        address groupAAddr = keyperModule.getGroupSafeAddress(groupIdA1);

        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddrA);

        // Get groupA signers info
        gnosisHelper.updateSafeInterface(groupAAddr);
        address[] memory groupA1Owners = gnosisHelper.gnosisSafe().getOwners();
        address newOwner = address(0xDEF);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        assertEq(gnosisHelper.gnosisSafe().isOwner(groupA1Owners[1]), true);

        // GroupB AddOwnerWithThreshold from groupA
        gnosisHelper.updateSafeInterface(rootAddrA);
        bool result = gnosisHelper.addOwnerWithThresholdTx(
            newOwner, threshold, groupAAddr, orgHash
        );
        assertEq(result, true);

        gnosisHelper.updateSafeInterface(groupAAddr);
        assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold);
        assertEq(
            gnosisHelper.gnosisSafe().getOwners().length,
            groupA1Owners.length + 1
        );
        assertEq(gnosisHelper.gnosisSafe().isOwner(newOwner), true);
    }

    function testRevertRootSafeToAttemptTo_AddOwnerWithThreshold_SUPER_SAFE_as_SAFE_is_TARGETS_SUPER_SAFE(
    ) public {
        (, uint256 groupIdA1,, uint256 groupIdB1,,) = keyperSafeBuilder
            .setupTwoRootOrgWithOneGroupAndOneChildEach(
            orgName,
            groupA1Name,
            root2Name,
            groupBName,
            subGroupA1Name,
            "subGroupB1"
        );

        address groupAAddr = keyperModule.getGroupSafeAddress(groupIdA1);
        address groupBAddr = keyperModule.getGroupSafeAddress(groupIdB1);

        bytes32 orgHash = keyperModule.getOrgHashBySafe(groupAAddr);

        // Get groupA signers info
        gnosisHelper.updateSafeInterface(groupAAddr);
        address[] memory groupA1Owners = gnosisHelper.gnosisSafe().getOwners();
        address newOwner = address(0xDEF);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        assertEq(gnosisHelper.gnosisSafe().isOwner(groupA1Owners[1]), true);

        // GroupB AddOwnerWithThreshold from groupA
        vm.startPrank(groupBAddr);
        vm.expectRevert(Errors.NotAuthorizedAddOwnerWithThreshold.selector);
        keyperModule.addOwnerWithThreshold(
            newOwner, threshold, groupAAddr, orgHash
        );
        vm.stopPrank();
    }

    function testRevertRootSafeToAttemptTo_AddOwnerWithThreshold_ROOT_SAFE_as_SAFE_is_TARGETS_ROOT_SAFE(
    ) public {
        (uint256 rootIdA,, uint256 rootIdB,) = keyperSafeBuilder
            .setupTwoRootOrgWithOneGroupEach(
            orgName, groupA1Name, root2Name, groupBName
        );

        address rootAddrA = keyperModule.getGroupSafeAddress(rootIdA);
        address rootAddrB = keyperModule.getGroupSafeAddress(rootIdB);

        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddrA);

        // Get groupA signers info
        gnosisHelper.updateSafeInterface(rootAddrA);
        address[] memory rootAOwners = gnosisHelper.gnosisSafe().getOwners();
        address newOwner = address(0xDEF);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        assertEq(gnosisHelper.gnosisSafe().isOwner(rootAOwners[1]), true);

        // GroupB AddOwnerWithThreshold from groupA
        vm.startPrank(rootAddrB);
        vm.expectRevert(Errors.NotAuthorizedAddOwnerWithThreshold.selector);
        keyperModule.addOwnerWithThreshold(
            newOwner, threshold, rootAddrA, orgHash
        );
        vm.stopPrank();
    }

    // Caller: rightCaller
    // Caller Type: EOA
    // Caller Role: SAFE_LEAD of org
    // TargerSafe: SAFE
    // TargetSafe Type: Safe Lead
    function testCan_AddOwnerWithThreshold_SAFE_LEAD_as_SAFE_is_TARGETS_LEAD()
        public
    {
        (uint256 rootIdA, uint256 groupIdA1,, uint256 groupIdB1) =
        keyperSafeBuilder.setupTwoRootOrgWithOneGroupEach(
            orgName, groupA1Name, root2Name, groupBName
        );

        address rootAddrA = keyperModule.getGroupSafeAddress(rootIdA);
        address groupBAddr = keyperModule.getGroupSafeAddress(groupIdB1);
        address groupAAddr = keyperModule.getGroupSafeAddress(groupIdA1);
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddrA);

        vm.startPrank(rootAddrA);
        keyperModule.setRole(
            DataTypes.Role.SAFE_LEAD, groupBAddr, groupIdA1, true
        );
        vm.stopPrank();
        assertEq(keyperModule.isSafeLead(groupIdA1, groupBAddr), true);

        // Get groupA signers info
        gnosisHelper.updateSafeInterface(groupAAddr);
        address[] memory groupA1Owners = gnosisHelper.gnosisSafe().getOwners();
        address newOwner = address(0xDEF);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        assertEq(gnosisHelper.gnosisSafe().isOwner(groupA1Owners[1]), true);

        // GroupB AddOwnerWithThreshold from groupA
        gnosisHelper.updateSafeInterface(groupBAddr);
        bool result = gnosisHelper.addOwnerWithThresholdTx(
            newOwner, threshold, groupAAddr, orgHash
        );
        assertEq(result, true);

        gnosisHelper.updateSafeInterface(groupAAddr);
        assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold);
        assertEq(
            gnosisHelper.gnosisSafe().getOwners().length,
            groupA1Owners.length + 1
        );
        assertEq(gnosisHelper.gnosisSafe().isOwner(newOwner), true);
    }

    // Caller: rightCaller
    // Caller Type: EOA
    // Caller Role: SAFE_LEAD of org
    // TargerSafe: groupAAddr
    // TargetSafe Type: Super Safe
    function testCan_AddOwnerWithThreshold_SAFE_LEAD_as_EOA_is_TARGETS_LEAD()
        public
    {
        (uint256 rootIdA, uint256 groupIdA1,,) = keyperSafeBuilder
            .setupTwoRootOrgWithOneGroupEach(
            orgName, groupA1Name, root2Name, groupBName
        );

        address rootAddrA = keyperModule.getGroupSafeAddress(rootIdA);
        address rightCaller = address(0x123);
        address groupAAddr = keyperModule.getGroupSafeAddress(groupIdA1);
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddrA);

        vm.startPrank(rootAddrA);
        keyperModule.setRole(
            DataTypes.Role.SAFE_LEAD, rightCaller, groupIdA1, true
        );
        vm.stopPrank();
        assertEq(keyperModule.isSafeLead(groupIdA1, rightCaller), true);

        // Get groupA signers info
        gnosisHelper.updateSafeInterface(groupAAddr);
        address[] memory groupA1Owners = gnosisHelper.gnosisSafe().getOwners();
        address newOwner = address(0xDEF);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        assertEq(gnosisHelper.gnosisSafe().isOwner(groupA1Owners[1]), true);

        vm.startPrank(rightCaller);
        keyperModule.addOwnerWithThreshold(
            newOwner, threshold, groupAAddr, orgHash
        );
        vm.stopPrank();

        gnosisHelper.updateSafeInterface(groupAAddr);
        assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold);
        assertEq(
            gnosisHelper.gnosisSafe().getOwners().length,
            groupA1Owners.length + 1
        );
        assertEq(gnosisHelper.gnosisSafe().isOwner(newOwner), true);
    }

    // Revert OwnerAlreadyExists() addOwnerWithThreshold (Attempting to add an existing owner)
    // Caller: safeLead
    // Caller Type: EOA
    // Caller Role: SAFE_LEAD of org
    // TargerSafe: rootAddr
    // TargetSafe Type: rootSafe
    function testRevertOwnerAlreadyExistsAddOwnerWithThreshold() public {
        (uint256 rootId,) =
            keyperSafeBuilder.setupRootOrgAndOneGroup(orgName, groupA1Name);

        address rootAddr = keyperModule.getGroupSafeAddress(rootId);
        address safeLead = address(0x123);

        vm.startPrank(rootAddr);
        keyperModule.setRole(DataTypes.Role.SAFE_LEAD, safeLead, rootId, true);
        vm.stopPrank();

        assertEq(keyperModule.isSafeLead(rootId, safeLead), true);

        gnosisHelper.updateSafeInterface(rootAddr);
        address[] memory owners = gnosisHelper.gnosisSafe().getOwners();
        address newOwner;

        for (uint256 i = 0; i < owners.length; i++) {
            newOwner = owners[i];
        }

        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddr);

        vm.startPrank(safeLead);
        vm.expectRevert(Errors.OwnerAlreadyExists.selector);
        keyperModule.addOwnerWithThreshold(
            newOwner, threshold + 1, rootAddr, orgHash
        );
    }

    // Revert InvalidAddressProvided() addOwnerWithThreshold (Attempting to add an zero Address owner)
    // Caller: rootAddr
    // Caller Type: SAFE
    // Caller Role: ROOT_LEAD of org
    // TargerSafe: rootAddr
    // TargetSafe Type: rootSafe
    function testRevertZeroAddressAddOwnerWithThreshold() public {
        (uint256 rootId,) =
            keyperSafeBuilder.setupRootOrgAndOneGroup(orgName, groupA1Name);

        address rootAddr = keyperModule.getGroupSafeAddress(rootId);

        gnosisHelper.updateSafeInterface(rootAddr);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddr);

        vm.startPrank(rootAddr);
        vm.expectRevert(Errors.InvalidAddressProvided.selector);
        keyperModule.addOwnerWithThreshold(
            zeroAddress, threshold + 1, rootAddr, orgHash
        );

        vm.expectRevert(Errors.InvalidAddressProvided.selector);
        keyperModule.addOwnerWithThreshold(
            sentinel, threshold + 1, rootAddr, orgHash
        );
        vm.stopPrank();
    }

    // Revert ZeroAddressProvided removeOwner
    // Caller: fakeCaller
    // Caller Type: SAFE
    // Caller Role: ROOT_SAFE of org
    // TargerSafe: groupAAddr
    // TargetSafe Type: Super Safe
    function testRevertZeroAddressProvidedRemoveOwner() public {
        (uint256 rootIdA, uint256 groupIdA1,,) = keyperSafeBuilder
            .setupTwoRootOrgWithOneGroupEach(
            orgName, groupA1Name, root2Name, groupBName
        );

        address fakeCaller = keyperModule.getGroupSafeAddress(rootIdA);
        bytes32 orgHash = keyperModule.getOrgHashBySafe(fakeCaller);

        address groupAAddr = keyperModule.getGroupSafeAddress(groupIdA1);

        // Get groupA signers info
        gnosisHelper.updateSafeInterface(groupAAddr);
        address[] memory groupA1Owners = gnosisHelper.gnosisSafe().getOwners();
        address prevOwner = groupA1Owners[0];
        address ownerToRemove = groupA1Owners[1];
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        vm.startPrank(fakeCaller);
        vm.expectRevert(Errors.ZeroAddressProvided.selector);
        keyperModule.removeOwner(
            zeroAddress, ownerToRemove, threshold, groupAAddr, orgHash
        );

        vm.expectRevert(Errors.ZeroAddressProvided.selector);
        keyperModule.removeOwner(
            prevOwner, zeroAddress, threshold, groupAAddr, orgHash
        );

        vm.expectRevert(Errors.ZeroAddressProvided.selector);
        keyperModule.removeOwner(
            sentinel, ownerToRemove, threshold, groupAAddr, orgHash
        );

        vm.expectRevert(Errors.ZeroAddressProvided.selector);
        keyperModule.removeOwner(
            prevOwner, sentinel, threshold, groupAAddr, orgHash
        );
        vm.stopPrank();
    }

    // Revert InvalidThreshold() addOwnerWithThreshold
    // Caller: safeLead
    // Caller Type: EOA
    // Caller Role: SAFE_LEAD of org
    // TargerSafe: rootAddr
    function testRevertInvalidThresholdAddOwnerWithThreshold() public {
        (uint256 rootId,) =
            keyperSafeBuilder.setupRootOrgAndOneGroup(orgName, groupA1Name);

        address rootAddr = keyperModule.getGroupSafeAddress(rootId);
        address safeLead = address(0x123);

        vm.startPrank(rootAddr);
        keyperModule.setRole(DataTypes.Role.SAFE_LEAD, safeLead, rootId, true);
        vm.stopPrank();

        // (When threshold < 1)
        address newOwner = address(0xf1f1f1);
        uint256 zeroThreshold = 0;
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddr);

        vm.startPrank(safeLead);
        vm.expectRevert(Errors.TxExecutionModuleFaild.selector); // safe Contract Internal Error GS202 "Threshold needs to be greater than 0"
        keyperModule.addOwnerWithThreshold(
            newOwner, zeroThreshold, rootAddr, orgHash
        );

        // When threshold > max current threshold
        uint256 wrongThreshold =
            gnosisHelper.gnosisSafe().getOwners().length + 2;

        vm.expectRevert(Errors.TxExecutionModuleFaild.selector); // safe Contract Internal Error GS201 "Threshold cannot exceed owner count"
        keyperModule.addOwnerWithThreshold(
            newOwner, wrongThreshold, rootAddr, orgHash
        );
    }

    // Revert SafeNotRegistered() addOwnerWithThreshold (Attempting to target safe not Registered like group)
    // Caller: fakeCaller
    // Caller Type: SAFE
    // Caller Role: ROOT_LEAD of org
    // TargerSafe: rootAddr
    // TargetSafe Type: rootSafe
    function testRevertSafeNotRegisteredAddOwnerWithThreshold_SAFE_Caller()
        public
    {
        (uint256 rootId,) =
            keyperSafeBuilder.setupRootOrgAndOneGroup(orgName, groupA1Name);

        address rootAddr = keyperModule.getGroupSafeAddress(rootId);

        address fakeCaller = gnosisHelper.newKeyperSafe(4, 2);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddr);
        address newOwner = gnosisHelper.newKeyperSafe(4, 2);

        vm.startPrank(fakeCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.SafeNotRegistered.selector, fakeCaller
            )
        );
        keyperModule.addOwnerWithThreshold(
            newOwner, threshold + 1, fakeCaller, orgHash
        );
        vm.stopPrank();
    }

    // Revert SafeNotRegistered() addOwnerWithThreshold (Attempting to target safe not Registered like group)
    // Caller: fakeCaller
    // Caller Type: EOA
    // Caller Role: ROOT_LEAD of org
    // TargerSafe: rootAddr
    // TargetSafe Type: rootSafe
    function testRevertSafeNotRegisteredAddOwnerWithThreshold_EOA_Caller()
        public
    {
        (uint256 rootId,) =
            keyperSafeBuilder.setupRootOrgAndOneGroup(orgName, groupA1Name);

        address rootAddr = keyperModule.getGroupSafeAddress(rootId);

        gnosisHelper.newKeyperSafe(4, 2);
        address fakeCaller = address(0x123);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddr);
        address newOwner = gnosisHelper.newKeyperSafe(4, 2);

        vm.startPrank(fakeCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidGnosisSafe.selector, fakeCaller
            )
        );
        keyperModule.addOwnerWithThreshold(
            newOwner, threshold + 1, fakeCaller, orgHash
        );
        vm.stopPrank();
    }

    // Revert SafeNotRegistered() removeOwner (Attempting to target safe not Registered like group)
    // Caller: fakeCaller
    // Caller Type: SAFE
    // Caller Role: ROOT_LEAD of org
    // TargerSafe: rootAddr
    // TargetSafe Type: rootSafe
    function testRevertSafeNotRegisteredRemoveOwner_SAFE_Caller() public {
        (uint256 rootId,) =
            keyperSafeBuilder.setupRootOrgAndOneGroup(orgName, groupA1Name);

        address rootAddr = keyperModule.getGroupSafeAddress(rootId);

        address fakeCaller = gnosisHelper.newKeyperSafe(4, 2);
        address[] memory owners = gnosisHelper.gnosisSafe().getOwners();
        address prevOwner = owners[0];
        address ownerToRemove = owners[1];
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddr);

        vm.startPrank(fakeCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.SafeNotRegistered.selector, fakeCaller
            )
        );
        keyperModule.removeOwner(
            prevOwner, ownerToRemove, threshold - 1, fakeCaller, orgHash
        );
        vm.stopPrank();
    }

    // Revert SafeNotRegistered() removeOwner (Attempting to target safe not Registered like group)
    // Caller: fakeCaller
    // Caller Type: EOA
    // Caller Role: ROOT_LEAD of org
    // TargerSafe: rootAddr
    // TargetSafe Type: rootSafe
    function testRevertSafeNotRegisteredRemoveOwner_EOA_Caller() public {
        (uint256 rootId,) =
            keyperSafeBuilder.setupRootOrgAndOneGroup(orgName, groupA1Name);

        address rootAddr = keyperModule.getGroupSafeAddress(rootId);

        gnosisHelper.newKeyperSafe(4, 2);
        address fakeCaller = address(0x123);
        address[] memory owners = gnosisHelper.gnosisSafe().getOwners();
        address prevOwner = owners[0];
        address ownerToRemove = owners[1];
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddr);

        vm.startPrank(fakeCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidGnosisSafe.selector, fakeCaller
            )
        );
        keyperModule.removeOwner(
            prevOwner, ownerToRemove, threshold - 1, fakeCaller, orgHash
        );
        vm.stopPrank();
    }

    // Revert NotAuthorizedAsNotSafeLead() addOwnerWithThreshold (Attempting to add an owner from an external org)
    // Caller: org2Addr
    // Caller Type: rootSafe
    // Caller Role: ROOT_SAFE for org2
    // TargerSafe: rootAddr
    // TargetSafe Type: rootSafe
    function testRevertRootSafesAttemptToAddToExternalSafeOrg() public {
        (uint256 rootIdA,, uint256 rootIdB,) = keyperSafeBuilder
            .setupTwoRootOrgWithOneGroupEach(
            orgName, groupA1Name, root2Name, groupBName
        );

        address rootAddr = keyperModule.getGroupSafeAddress(rootIdA);
        address rootBAddr = keyperModule.getGroupSafeAddress(rootIdB);

        address newOwnerOnOrgA = address(0xF1F1);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddr);
        vm.expectRevert(Errors.NotAuthorizedAddOwnerWithThreshold.selector);

        vm.startPrank(rootBAddr);
        keyperModule.addOwnerWithThreshold(
            newOwnerOnOrgA, threshold, rootAddr, orgHash
        );
    }

    //     // ! ********************* removeOwner Test ***********************************

    // Caller: userLeadEOA
    // Caller Type: EOA
    // Caller Role: SAFE_LEAD for org1
    // Caller Info: SAFE_LEAD(role), EOA(type)
    // TargetSafe Type: SAFE
    function testCan_RemoveOwner_SAFE_LEAD_as_EOA_is_TARGETS_LEAD() public {
        (uint256 rootId, uint256 groupIdA1) =
            keyperSafeBuilder.setupRootOrgAndOneGroup(orgName, groupA1Name);

        address rootAddr = keyperModule.getGroupSafeAddress(rootId);
        address groupA1Addr = keyperModule.getGroupSafeAddress(groupIdA1);

        address userLeadEOA = address(0x123);

        vm.startPrank(rootAddr);
        keyperModule.setRole(
            DataTypes.Role.SAFE_LEAD, userLeadEOA, groupIdA1, true
        );
        vm.stopPrank();

        gnosisHelper.updateSafeInterface(groupA1Addr);
        address[] memory ownersList = gnosisHelper.gnosisSafe().getOwners();

        address prevOwner = ownersList[0];
        address owner = ownersList[1];
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();
        bytes32 orgHash = keyperModule.getOrgHashBySafe(groupA1Addr);

        vm.startPrank(userLeadEOA);
        keyperModule.removeOwner(
            prevOwner, owner, threshold, groupA1Addr, orgHash
        );

        address[] memory postRemoveOwnersList =
            gnosisHelper.gnosisSafe().getOwners();

        assertEq(postRemoveOwnersList.length, ownersList.length - 1);
        assertEq(gnosisHelper.gnosisSafe().isOwner(owner), false);
        assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold);
    }

    // Caller: groupA2Addr
    // Caller Type: SAFE
    // Caller Role: SAFE_LEAD for org1
    // Caller Info: SAFE_LEAD(role), SAFE(type), groupSafe(hierachie)
    // TargetSafe Type: SAFE
    function testCan_RemoveOwner_SAFE_LEAD_as_SAFE_is_TARGETS_LEAD() public {
        (uint256 rootId, uint256 groupIdA1, uint256 groupIdA2) =
        keyperSafeBuilder.setupRootWithTwoGroups(
            orgName, groupA1Name, groupA2Name
        );

        address rootAddr = keyperModule.getGroupSafeAddress(rootId);
        address groupA1Addr = keyperModule.getGroupSafeAddress(groupIdA1);
        address groupA2Addr = keyperModule.getGroupSafeAddress(groupIdA2);

        vm.startPrank(rootAddr);
        keyperModule.setRole(
            DataTypes.Role.SAFE_LEAD, groupA2Addr, groupIdA1, true
        );
        vm.stopPrank();

        gnosisHelper.updateSafeInterface(groupA1Addr);
        address[] memory ownersList = gnosisHelper.gnosisSafe().getOwners();

        address prevOwner = ownersList[0];
        address owner = ownersList[1];
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();
        bytes32 orgHash = keyperModule.getOrgHashBySafe(groupA1Addr);

        gnosisHelper.updateSafeInterface(groupA2Addr);
        gnosisHelper.removeOwnerTx(
            prevOwner, owner, threshold, groupA1Addr, orgHash
        );
        gnosisHelper.updateSafeInterface(groupA1Addr);
        address[] memory postRemoveOwnersList =
            gnosisHelper.gnosisSafe().getOwners();

        assertEq(postRemoveOwnersList.length, ownersList.length - 1);
        assertEq(gnosisHelper.gnosisSafe().isOwner(owner), false);
        assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold);
    }

    // Caller: groupBAddr
    // Caller Type: SAFE
    // Caller Role: SAFE_LEAD for org2
    // Caller Info: SAFE_LEAD(role), SAFE(type), groupSafe(hierachie)
    // TargetSafe Type: SAFE from different tree
    function testCan_RemoveOwner_SAFE_LEAD_as_SAFE_is_TARGETS_LEAD_DifferentTree(
    ) public {
        (uint256 rootIdA, uint256 groupIdA1,, uint256 groupIdB1) =
        keyperSafeBuilder.setupTwoRootOrgWithOneGroupEach(
            orgName, groupA1Name, root2Name, groupBName
        );

        address rootAddrA = keyperModule.getGroupSafeAddress(rootIdA);
        address groupBAddr = keyperModule.getGroupSafeAddress(groupIdB1);
        address groupAAddr = keyperModule.getGroupSafeAddress(groupIdA1);
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddrA);

        vm.startPrank(rootAddrA);
        keyperModule.setRole(
            DataTypes.Role.SAFE_LEAD, groupBAddr, groupIdA1, true
        );
        vm.stopPrank();

        // Get groupA signers info
        gnosisHelper.updateSafeInterface(groupAAddr);
        address[] memory groupA1Owners = gnosisHelper.gnosisSafe().getOwners();
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        // GroupB RemoveOwner from groupA
        gnosisHelper.updateSafeInterface(groupBAddr);
        bool result = gnosisHelper.removeOwnerTx(
            groupA1Owners[0], groupA1Owners[1], threshold, groupAAddr, orgHash
        );
        assertEq(result, true);
        assertEq(gnosisHelper.gnosisSafe().isOwner(groupA1Owners[1]), false);
    }
    // Caller: groupAAddr
    // Caller Type: SAFE
    // Caller Role: SUPER_SAFE for org1
    // Caller Info: SUPER_SAFE(role), SAFE(type), groupSafe(hierachie)
    // TargetSafe Type: SAFE from the same tree (Right TARGETS SUPER SAFE)

    function testCan_RemoveOwner_SUPER_SAFE_as_SAFE_is_TARGETS_SUPER_SAFE()
        public
    {
        (, uint256 groupIdA1, uint256 childIdA) = keyperSafeBuilder
            .setupOrgThreeTiersTree(orgName, groupA1Name, subGroupA1Name);

        address groupAAddr = keyperModule.getGroupSafeAddress(groupIdA1);
        address childAAddr = keyperModule.getGroupSafeAddress(childIdA);

        bytes32 orgHash = keyperModule.getOrgHashBySafe(groupAAddr);

        gnosisHelper.updateSafeInterface(childAAddr);
        address[] memory ownersList = gnosisHelper.gnosisSafe().getOwners();

        address prevOwner = ownersList[0];
        address owner = ownersList[1];
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        gnosisHelper.updateSafeInterface(groupAAddr);
        gnosisHelper.removeOwnerTx(
            prevOwner, owner, threshold, childAAddr, orgHash
        );
        gnosisHelper.updateSafeInterface(childAAddr);
        address[] memory postRemoveOwnersList =
            gnosisHelper.gnosisSafe().getOwners();

        assertEq(postRemoveOwnersList.length, ownersList.length - 1);
        assertEq(gnosisHelper.gnosisSafe().isOwner(owner), false);
        assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold);
    }

    // Caller: groupAAddr
    // Caller Type: SAFE
    // Caller Role: ROOT_SAFE for org1
    // Caller Info: ROOT_SAFE(role), SAFE(type), groupSafe(hierachie)
    // TargetSafe Type: SAFE from the same tree (Right TARGETS ROOT SAFE)
    function testCan_RemoveOwner_ROOT_SAFE_as_SAFE_is_TARGETS_ROOT_SAFE()
        public
    {
        (uint256 rootIdA, uint256 groupIdA1,) = keyperSafeBuilder
            .setupOrgThreeTiersTree(orgName, groupA1Name, subGroupA1Name);

        address rootAddrA = keyperModule.getGroupSafeAddress(rootIdA);
        address groupAAddr = keyperModule.getGroupSafeAddress(groupIdA1);

        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddrA);

        gnosisHelper.updateSafeInterface(groupAAddr);
        address[] memory ownersList = gnosisHelper.gnosisSafe().getOwners();

        address prevOwner = ownersList[0];
        address owner = ownersList[1];
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        gnosisHelper.updateSafeInterface(rootAddrA);
        gnosisHelper.removeOwnerTx(
            prevOwner, owner, threshold, groupAAddr, orgHash
        );

        gnosisHelper.updateSafeInterface(groupAAddr);
        address[] memory postRemoveOwnersList =
            gnosisHelper.gnosisSafe().getOwners();

        assertEq(postRemoveOwnersList.length, ownersList.length - 1);
        assertEq(gnosisHelper.gnosisSafe().isOwner(owner), false);
        assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold);
    }

    // Revert Super Safe to attempt to remove owner SUPER_SAFE as SAFE is TARGETS SUPER SAFE
    // Caller: groupAAddr
    // Caller Type: SAFE
    // Caller Role: SUPER_SAFE for org1
    // Caller Info: SUPER_SAFE(role), SAFE(type), groupSafe(hierachie)
    // TargetSafe Type: SAFE from the same tree (Right TARGETS SUPER SAFE)
    function testRevertRootSafeToAttemptTo_removeOwner_SUPER_SAFE_as_SAFE_is_TARGETS_SUPER_SAFE(
    ) public {
        (, uint256 groupIdA1,, uint256 groupIdB1,,) = keyperSafeBuilder
            .setupTwoRootOrgWithOneGroupAndOneChildEach(
            orgName,
            groupA1Name,
            root2Name,
            groupBName,
            subGroupA1Name,
            "subGroupB1"
        );

        address groupAAddr = keyperModule.getGroupSafeAddress(groupIdA1);
        address groupBAddr = keyperModule.getGroupSafeAddress(groupIdB1);

        bytes32 orgHash = keyperModule.getOrgHashBySafe(groupAAddr);

        // Get groupA signers info
        gnosisHelper.updateSafeInterface(groupAAddr);
        address[] memory groupA1Owners = gnosisHelper.gnosisSafe().getOwners();
        address prevOwner = groupA1Owners[1];
        address removeOwner = groupA1Owners[2];
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        assertEq(gnosisHelper.gnosisSafe().isOwner(groupA1Owners[1]), true);

        // GroupB AddOwnerWithThreshold from groupA
        vm.startPrank(groupBAddr);
        vm.expectRevert(Errors.NotAuthorizedRemoveOwner.selector);
        keyperModule.removeOwner(
            prevOwner, removeOwner, threshold, groupAAddr, orgHash
        );
        vm.stopPrank();
    }

    // Revert Root Safe to attempt to remove owner SUPER_SAFE as SAFE is TARGETS SUPER SAFE
    // Caller: groupAAddr
    // Caller Type: SAFE
    // Caller Role: SUPER_SAFE for org1
    // Caller Info: SUPER_SAFE(role), SAFE(type), groupSafe(hierachie)
    // TargetSafe Type: SAFE from the same tree (Right TARGETS SUPER SAFE)
    function testRevertRootSafeToAttemptTo_removeOwner_ROOT_SAFE_as_SAFE_is_TARGETS_ROOT_SAFE(
    ) public {
        (uint256 rootIdA,, uint256 rootIdB,) = keyperSafeBuilder
            .setupTwoRootOrgWithOneGroupEach(
            orgName, groupA1Name, root2Name, groupBName
        );

        address rootAddrA = keyperModule.getGroupSafeAddress(rootIdA);
        address rootAddrB = keyperModule.getGroupSafeAddress(rootIdB);

        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddrA);

        // Get groupA signers info
        gnosisHelper.updateSafeInterface(rootAddrA);
        address[] memory rootAOwners = gnosisHelper.gnosisSafe().getOwners();
        address prevOwner = rootAOwners[1];
        address removeOwner = rootAOwners[2];
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        assertEq(gnosisHelper.gnosisSafe().isOwner(rootAOwners[1]), true);

        // GroupB AddOwnerWithThreshold from groupA
        vm.startPrank(rootAddrB);
        vm.expectRevert(Errors.NotAuthorizedRemoveOwner.selector);
        keyperModule.removeOwner(
            prevOwner, removeOwner, threshold, rootAddrA, orgHash
        );
        vm.stopPrank();
    }

    // Caller: groupBAddr
    // Caller Type: SAFE
    // Caller Role: SAFE_LEAD_MODIFY_OWNERS_ONLY for org1
    // Caller Info: SAFE_LEAD_MODIFY_OWNERS_ONLY(role), SAFE(type), groupSafe(hierachie)
    // TargetSafe Type: SAFE from the same tree (Right TARGETS LEAD)
    function testCan_RemoveOwner_SAFE_LEAD_MODIFY_OWNERS_ONLY_as_SAFE_is_TARGETS_LEAD(
    ) public {
        (uint256 rootIdA, uint256 groupIdA1,, uint256 groupIdB1) =
        keyperSafeBuilder.setupTwoRootOrgWithOneGroupEach(
            orgName, groupA1Name, root2Name, groupBName
        );

        address rootAddrA = keyperModule.getGroupSafeAddress(rootIdA);
        address groupBAddr = keyperModule.getGroupSafeAddress(groupIdB1);
        address groupAAddr = keyperModule.getGroupSafeAddress(groupIdA1);
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddrA);

        vm.startPrank(rootAddrA);
        keyperModule.setRole(
            DataTypes.Role.SAFE_LEAD_MODIFY_OWNERS_ONLY,
            groupBAddr,
            groupIdA1,
            true
        );
        vm.stopPrank();
        assertEq(keyperModule.isSafeLead(groupIdA1, groupBAddr), true);

        // Get groupA signers info
        gnosisHelper.updateSafeInterface(groupAAddr);
        address[] memory groupA1Owners = gnosisHelper.gnosisSafe().getOwners();
        address prevOwner = groupA1Owners[1];
        address removeOwner = groupA1Owners[2];
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        assertEq(gnosisHelper.gnosisSafe().isOwner(groupA1Owners[1]), true);

        // GroupB AddOwnerWithThreshold from groupA
        gnosisHelper.updateSafeInterface(groupBAddr);
        bool result = gnosisHelper.removeOwnerTx(
            prevOwner, removeOwner, threshold, groupAAddr, orgHash
        );
        assertEq(result, true);

        gnosisHelper.updateSafeInterface(groupAAddr);
        assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold);
        assertEq(
            gnosisHelper.gnosisSafe().getOwners().length,
            groupA1Owners.length - 1
        );
        assertEq(gnosisHelper.gnosisSafe().isOwner(removeOwner), false);
    }

    // Caller: userLeadModifyOwnersOnly
    // Caller Type: EOA
    // Caller Role: SAFE_LEAD_MODIFY_OWNERS_ONLY for org1
    // Caller Info: SAFE_LEAD_MODIFY_OWNERS_ONLY(role), SAFE(type), groupSafe(hierachie)
    // TargetSafe Type: EOA from the same tree (Right TARGETS LEAD)
    function testCan_RemoveOwner_SAFE_LEAD_MODIFY_OWNERS_ONLY_as_EOA_is_TARGETS_LEAD(
    ) public {
        (uint256 rootId, uint256 groupIdA1) =
            keyperSafeBuilder.setupRootOrgAndOneGroup(orgName, groupA1Name);

        address rootAddr = keyperModule.getGroupSafeAddress(rootId);
        address groupA1Addr = keyperModule.getGroupSafeAddress(groupIdA1);
        address userLeadModifyOwnersOnly = address(0x123);

        address[] memory groupA1Owners = gnosisHelper.gnosisSafe().getOwners();
        address prevOwner = groupA1Owners[1];
        address removeOwner = groupA1Owners[2];

        vm.startPrank(rootAddr);
        keyperModule.setRole(
            DataTypes.Role.SAFE_LEAD_MODIFY_OWNERS_ONLY,
            userLeadModifyOwnersOnly,
            groupIdA1,
            true
        );
        vm.stopPrank();

        gnosisHelper.updateSafeInterface(groupA1Addr);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        bytes32 orgHash = keyperModule.getOrgHashBySafe(groupA1Addr);

        vm.startPrank(userLeadModifyOwnersOnly);
        keyperModule.removeOwner(
            prevOwner, removeOwner, threshold - 1, groupA1Addr, orgHash
        );

        assertEq(gnosisHelper.gnosisSafe().getThreshold(), threshold - 1);
        assertEq(gnosisHelper.gnosisSafe().isOwner(removeOwner), false);
    }

    // Revert NotAuthorizedAsNotSafeLead() removeOwner (Attempting to remove an owner from an external org)
    // Caller: org2Addr
    // Caller Type: rootSafe
    // Caller Role: ROOT_SAFE of org2
    // TargerSafe: rootAddr
    // TargetSafe Type: rootSafe
    function testRevertRootSafesToAttemptToRemoveFromExternalOrg() public {
        (uint256 rootIdA,, uint256 rootIdB,) = keyperSafeBuilder
            .setupTwoRootOrgWithOneGroupEach(
            orgName, groupA1Name, root2Name, groupBName
        );

        address rootAddr = keyperModule.getGroupSafeAddress(rootIdA);
        address rootBAddr = keyperModule.getGroupSafeAddress(rootIdB);

        address prevOwnerToRemoveOnOrgA =
            gnosisHelper.gnosisSafe().getOwners()[0];
        address ownerToRemove = gnosisHelper.gnosisSafe().getOwners()[1];
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddr);

        vm.expectRevert(Errors.NotAuthorizedRemoveOwner.selector);

        vm.startPrank(rootBAddr);
        keyperModule.removeOwner(
            prevOwnerToRemoveOnOrgA, ownerToRemove, threshold, rootAddr, orgHash
        );
    }

    // Revert OwnerNotFound() removeOwner (attempting to remove an owner that is not exist as an owner of the safe)
    // Caller: safeLead
    // Caller Type: EOA
    // Caller Role: SAFE_LEAD of org
    // TargerSafe: rootAddr
    // TargetSafe Type: rootSafe
    function testRevertOwnerNotFoundRemoveOwner() public {
        bool result = gnosisHelper.registerOrgTx(orgName);
        keyperSafes[orgName] = address(gnosisHelper.gnosisSafe());
        vm.label(keyperSafes[orgName], orgName);

        assertEq(result, true);

        address rootAddr = keyperSafes[orgName];
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddr);
        uint256 rootId = keyperModule.getGroupIdBySafe(orgHash, rootAddr);
        address safeLead = address(0x123);

        vm.startPrank(rootAddr);
        keyperModule.setRole(DataTypes.Role.SAFE_LEAD, safeLead, rootId, true);
        vm.stopPrank();

        address[] memory ownersList = gnosisHelper.gnosisSafe().getOwners();

        address prevOwner = ownersList[0];
        address wrongOwnerToRemove = address(0xabdcf);
        uint256 threshold = gnosisHelper.gnosisSafe().getThreshold();

        assertEq(ownersList.length, 3);

        vm.expectRevert(Errors.OwnerNotFound.selector);

        vm.startPrank(safeLead);

        keyperModule.removeOwner(
            prevOwner, wrongOwnerToRemove, threshold, rootAddr, orgHash
        );
    }
}
