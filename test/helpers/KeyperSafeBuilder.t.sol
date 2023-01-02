// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "./GnosisSafeHelper.t.sol";
import {KeyperModule} from "../../src/KeyperModule.sol";
import {console} from "forge-std/console.sol";

contract KeyperSafeBuilder is Test {
    GnosisSafeHelper public gnosisHelper;
    KeyperModule public keyperModule;

    mapping(string => address) public keyperSafes;

    function setUpParams(
        KeyperModule keyperModuleArg,
        GnosisSafeHelper gnosisHelperArg
    ) public {
        keyperModule = keyperModuleArg;
        gnosisHelper = gnosisHelperArg;
    }

    // Just deploy a root org and a Group
    //           RootOrg
    //              |
    //           groupA1
    function setupRootOrgAndOneGroup(
        string memory orgNameArg,
        string memory groupA1NameArg
    ) public returns (uint256 rootId, uint256 groupIdA1) {
        // Register Org through safe tx
        address rootAddr = gnosisHelper.newKeyperSafe(4, 2);
        bool result = gnosisHelper.registerOrgTx(orgNameArg);
        // Get org Id
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddr);
        rootId = keyperModule.getGroupIdBySafe(orgHash, rootAddr);

        address groupSafe = gnosisHelper.newKeyperSafe(4, 2);
        // Create group through safe tx
        result = gnosisHelper.createAddGroupTx(rootId, groupA1NameArg);
        groupIdA1 = keyperModule.getGroupIdBySafe(orgHash, groupSafe);

        vm.deal(rootAddr, 100 gwei);
        vm.deal(groupSafe, 100 gwei);

        return (rootId, groupIdA1);
    }

    // Deploy 1 org with 2 group at same level
    //           RootA
    //         |         |
    //     groupA1    groupA2
    function setupRootWithTwoGroups(
        string memory orgNameArg,
        string memory groupA1NameArg,
        string memory groupA2NameArg
    ) public returns (uint256 rootIdA, uint256 groupIdA1, uint256 groupIdA2) {
        (rootIdA, groupIdA1) =
            setupRootOrgAndOneGroup(orgNameArg, groupA1NameArg);
        (,,, address rootAddr,,) = keyperModule.getGroupInfo(rootIdA);

        // Create groupA2
        address groupA2 = gnosisHelper.newKeyperSafe(4, 2);

        // Create group through safe tx
        gnosisHelper.createAddGroupTx(rootIdA, groupA2NameArg);
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddr);
        groupIdA2 = keyperModule.getGroupIdBySafe(orgHash, groupA2);
        vm.deal(groupA2, 100 gwei);

        return (rootIdA, groupIdA1, groupIdA2);
    }

    // Deploy 1 org with 2 root safe with 1 group each
    //           RootA      RootB
    //              |         |
    //           groupA1    groupB1
    function setupTwoRootOrgWithOneGroupEach(
        string memory orgNameArg,
        string memory groupA1NameArg,
        string memory rootBNameArg,
        string memory groupB1NameArg
    )
        public
        returns (
            uint256 rootIdA,
            uint256 groupIdA1,
            uint256 rootIdB,
            uint256 groupIdB1
        )
    {
        (rootIdA, groupIdA1) =
            setupRootOrgAndOneGroup(orgNameArg, groupA1NameArg);
        (,,, address rootAddr,,) = keyperModule.getGroupInfo(rootIdA);

        // Create Another Safe like Root Safe
        address rootBAddr = gnosisHelper.newKeyperSafe(3, 2);
        // update safe of gonsis helper
        gnosisHelper.updateSafeInterface(rootAddr);
        // Create Root Safe Group
        bool result = gnosisHelper.createRootSafeTx(rootBAddr, rootBNameArg);
        bytes32 orgHash = keyperModule.getOrgHashBySafe(rootAddr);
        rootIdB = keyperModule.getGroupIdBySafe(orgHash, rootBAddr);
        vm.deal(rootBAddr, 100 gwei);

        // Create groupB for rootB
        address groupSafeB = gnosisHelper.newKeyperSafe(4, 2);

        // Create group through safe tx
        result = gnosisHelper.createAddGroupTx(rootIdB, groupB1NameArg);
        groupIdB1 = keyperModule.getGroupIdBySafe(orgHash, groupSafeB);
        vm.deal(groupSafeB, 100 gwei);

        return (rootIdA, groupIdA1, rootIdB, groupIdB1);
    }

    // Deploy 2 org with 2 root safe with 1 group each
    //           RootA         RootB
    //              |            |
    //           groupA1      groupB1
    //              |            |
    //        childGroupA1  childGroupA1
    function setupTwoRootOrgWithOneGroupAndOneChildEach(
        string memory orgNameArg,
        string memory groupA1NameArg,
        string memory rootBNameArg,
        string memory groupB1NameArg,
        string memory childGroupA1NameArg,
        string memory childGroupB1NameArg
    )
        public
        returns (
            uint256 rootIdA,
            uint256 groupIdA1,
            uint256 rootIdB,
            uint256 groupIdB1,
            uint256 childGroupIdA1,
            uint256 childGroupIdB1
        )
    {
        (rootIdA, groupIdA1, rootIdB, groupIdB1) =
        setupTwoRootOrgWithOneGroupEach(
            orgNameArg, groupA1NameArg, rootBNameArg, groupB1NameArg
        );
        bytes32 orgHash = keyperModule.getOrgByGroup(rootIdA);

        // Create childGroupA1
        address childGroupA1 = gnosisHelper.newKeyperSafe(4, 2);
        gnosisHelper.createAddGroupTx(groupIdA1, childGroupA1NameArg);
        childGroupIdA1 = keyperModule.getGroupIdBySafe(orgHash, childGroupA1);
        vm.deal(childGroupA1, 100 gwei);

        // Create childGroupB1
        address childGroupB1 = gnosisHelper.newKeyperSafe(4, 2);
        gnosisHelper.createAddGroupTx(groupIdB1, childGroupB1NameArg);
        childGroupIdB1 = keyperModule.getGroupIdBySafe(orgHash, childGroupB1);
        vm.deal(childGroupB1, 100 gwei);

        return (
            rootIdA,
            groupIdA1,
            rootIdB,
            groupIdB1,
            childGroupIdA1,
            childGroupIdB1
        );
    }

    // Deploy 3 keyperSafes : following structure
    //           RootOrg
    //              |
    //         safeGroupA1
    //              |
    //        safeSubGroupA1
    function setupOrgThreeTiersTree(
        string memory orgNameArg,
        string memory groupA1NameArg,
        string memory subGroupA1NameArg
    )
        public
        returns (uint256 rootId, uint256 groupIdA1, uint256 subGroupIdA1)
    {
        // Create root & groupA1
        (rootId, groupIdA1) =
            setupRootOrgAndOneGroup(orgNameArg, groupA1NameArg);
        address safeSubGroupA1 = gnosisHelper.newKeyperSafe(2, 1);

        // Create subgroupA1
        gnosisHelper.createAddGroupTx(groupIdA1, subGroupA1NameArg);
        bytes32 orgHash = keyperModule.getOrgByGroup(groupIdA1);
        // Get subgroupA1 Id
        subGroupIdA1 = keyperModule.getGroupIdBySafe(orgHash, safeSubGroupA1);
        return (rootId, groupIdA1, subGroupIdA1);
    }

    // Deploy 4 keyperSafes : following structure
    //           RootOrg
    //              |
    //         safeGroupA1
    //              |
    //        safeSubGroupA1
    //              |
    //      safeSubSubGroupA1
    function setupOrgFourTiersTree(
        string memory orgNameArg,
        string memory groupA1NameArg,
        string memory subGroupA1NameArg,
        string memory subSubGroupA1NameArg
    )
        public
        returns (
            uint256 rootId,
            uint256 groupIdA1,
            uint256 subGroupIdA1,
            uint256 subSubGroupIdA1
        )
    {
        (rootId, groupIdA1, subGroupIdA1) = setupOrgThreeTiersTree(
            orgNameArg, groupA1NameArg, subGroupA1NameArg
        );

        address safeSubSubGroupA1 = gnosisHelper.newKeyperSafe(2, 1);

        gnosisHelper.createAddGroupTx(subGroupIdA1, subSubGroupA1NameArg);
        bytes32 orgHash = keyperModule.getOrgByGroup(groupIdA1);
        // Get subgroupA1 Id
        subSubGroupIdA1 =
            keyperModule.getGroupIdBySafe(orgHash, safeSubSubGroupA1);

        return (rootId, groupIdA1, subGroupIdA1, subSubGroupIdA1);
    }

    // Deploy 4 keyperSafes : following structure
    //           RootOrg
    //          |      |
    //      groupA1   GroupB
    //        |
    //  subGroupA1
    //      |
    //  SubSubGroupA1
    function setUpBaseOrgTree(
        string memory orgNameArg,
        string memory groupA1NameArg,
        string memory groupBNameArg,
        string memory subGroupA1NameArg,
        string memory subSubGroupA1NameArg
    )
        public
        returns (
            uint256 rootId,
            uint256 groupIdA1,
            uint256 groupIdB,
            uint256 subGroupIdA1,
            uint256 subSubGroupIdA1
        )
    {
        (rootId, groupIdA1, subGroupIdA1, subSubGroupIdA1) =
        setupOrgFourTiersTree(
            orgNameArg, groupA1NameArg, subGroupA1NameArg, subSubGroupA1NameArg
        );

        address safeGroupB = gnosisHelper.newKeyperSafe(2, 1);
        gnosisHelper.createAddGroupTx(rootId, groupBNameArg);
        bytes32 orgHash = keyperModule.getOrgByGroup(groupIdA1);
        // Get groupIdB Id
        groupIdB = keyperModule.getGroupIdBySafe(orgHash, safeGroupB);

        return (rootId, groupIdA1, groupIdB, subGroupIdA1, subSubGroupIdA1);
    }
}
