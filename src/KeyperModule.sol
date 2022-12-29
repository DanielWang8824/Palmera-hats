// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.15;

import {Enum} from "@safe-contracts/common/Enum.sol";
import {GnosisSafeMath} from "@safe-contracts/external/GnosisSafeMath.sol";
import {IGnosisSafe, IGnosisSafeProxy} from "./GnosisSafeInterfaces.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {DenyHelper, Address} from "./DenyHelper.sol";
import {ReentrancyGuard} from "@openzeppelin/security/ReentrancyGuard.sol";
import {Errors} from "../libraries/Errors.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {Constants} from "../libraries/Constants.sol";
import {Events} from "../libraries/Events.sol";

/// @title Keyper Module
/// @custom:security-contact general@palmeradao.xyz
contract KeyperModule is Auth, ReentrancyGuard, DenyHelper {
    using GnosisSafeMath for uint256;
    using Address for address;

    /// @dev Definition of Safe module
    string public constant NAME = "Keyper Module";
    string public constant VERSION = "0.2.0";
    /// @dev Control Nonce of the module
    uint256 public nonce;
    /// @dev indexId of the group
    uint256 public indexId;
    /// @dev Max Depth Tree Limit
    uint256 public maxDepthTreeLimit;
    /// @dev Safe contracts
    address public immutable masterCopy;
    address public immutable proxyFactory;
    /// @dev RoleAuthority
    address public rolesAuthority;
    /// @dev Array of Orgs (based on Hash(DAO's name) of the Org)
    bytes32[] private orgHash;
    /// @dev Index of Group
    /// bytes32: Hash(DAO's name) -> uint256: ID's Groups
    mapping(bytes32 => uint256[]) public indexGroup;
    /// @dev Depth Tree Limit
    /// bytes32: Hash(DAO's name) -> uint256: Depth Tree Limit
    mapping(bytes32 => uint256) public depthTreeLimit;
    /// @dev Hash(DAO's name) -> Groups
    /// bytes32: Hash(DAO's name).   uint256:GroupId.   Group: Group Info
    mapping(bytes32 => mapping(uint256 => DataTypes.Group)) public groups;

    /// @dev Modifier for Validate if Org/Group Exist or SuperSafeNotRegistered Not
    /// @param group ID of the group
    modifier GroupRegistered(uint256 group) {
        if (groups[getOrgByGroup(group)][group].safe == address(0)) {
            revert Errors.GroupNotRegistered(group);
        }
        _;
    }

    /// @dev Modifier for Validate if safe caller is Registered
    /// @param safe Safe address
    modifier SafeRegistered(address safe) {
        if (
            (safe == address(0)) || safe == Constants.SENTINEL_ADDRESS
                || !isSafe(safe)
        ) {
            revert Errors.InvalidGnosisSafe(safe);
        } else if (!isSafeRegistered(safe)) {
            revert Errors.SafeNotRegistered(safe);
        }
        _;
    }

    /// @dev Modifier for Validate if the address is a Gnosis Safe Multisig Wallet
    /// @param safe Address of the Gnosis Safe Multisig Wallet
    modifier IsGnosisSafe(address safe) {
        if (
            safe == address(0) || safe == Constants.SENTINEL_ADDRESS
                || !isSafe(safe)
        ) {
            revert Errors.InvalidGnosisSafe(safe);
        }
        _;
    }

    /// @dev Modifier for Validate if the address is a Gnosis Safe Multisig Wallet and Root Safe
    /// @param safe Address of the Gnosis Safe Multisig Wallet
    modifier IsRootSafe(address safe) {
        if (
            (safe == address(0)) || safe == Constants.SENTINEL_ADDRESS
                || !isSafe(safe)
        ) {
            revert Errors.InvalidGnosisSafe(safe);
        } else if (!isSafeRegistered(safe)) {
            revert Errors.SafeNotRegistered(safe);
        } else if (
            groups[getOrgHashBySafe(safe)][getGroupIdBySafe(
                getOrgHashBySafe(safe), safe
            )].tier != DataTypes.Tier.ROOT
        ) {
            revert Errors.InvalidGnosisRootSafe(safe);
        }
        _;
    }

    constructor(
        address masterCopyAddress,
        address proxyFactoryAddress,
        address authorityAddress,
        uint256 maxDepthTreeLimitInitial
    ) Auth(address(0), Authority(authorityAddress)) {
        if (
            masterCopyAddress == address(0) || proxyFactoryAddress == address(0)
                || authorityAddress == address(0)
        ) revert Errors.ZeroAddressProvided();

        if (
            !masterCopyAddress.isContract() || !proxyFactoryAddress.isContract()
        ) revert Errors.InvalidAddressProvided();

        masterCopy = masterCopyAddress;
        proxyFactory = proxyFactoryAddress;
        rolesAuthority = authorityAddress;
        /// Index of Groups starts in 1 Always
        indexId = 1;
        maxDepthTreeLimit = maxDepthTreeLimitInitial;
    }

    /// @dev Function to create Gnosis Safe Multisig Wallet with our module enabled
    /// @param owners Array of owners of the Gnosis Safe Multisig Wallet
    /// @param threshold Threshold of the Gnosis Safe Multisig Wallet
    /// @return safe Address of Safe created with the module enabled
    function createSafeProxy(address[] memory owners, uint256 threshold)
        external
        returns (address safe)
    {
        bytes memory internalEnableModuleData = abi.encodeWithSignature(
            "internalEnableModule(address)", address(this)
        );

        bytes memory data = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,
            threshold,
            this,
            internalEnableModuleData,
            Constants.FALLBACK_HANDLER,
            address(0x0),
            uint256(0),
            payable(address(0x0))
        );

        IGnosisSafeProxy gnosisSafeProxy = IGnosisSafeProxy(proxyFactory);
        try gnosisSafeProxy.createProxy(masterCopy, data) returns (
            address newSafe
        ) {
            return newSafe;
        } catch {
            revert Errors.CreateSafeProxyFailed();
        }
    }

    /// @notice Calls execTransaction of the safe with custom checks on owners rights
    /// @param org ID's Organization
    /// @param targetSafe Safe target address
    /// @param to Address to which the transaction is being sent
    /// @param value Value (ETH) that is being sent with the transaction
    /// @param data Data payload of the transaction
    /// @param operation kind of operation (call or delegatecall)
    /// @param signatures Packed signatures data (v, r, s)
    /// @return result true if transaction was successful.
    function execTransactionOnBehalf(
        bytes32 org,
        address targetSafe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        bytes memory signatures
    )
        external
        payable
        nonReentrant
        SafeRegistered(targetSafe)
        Denied(org, to)
        requiresAuth
        returns (bool result)
    {
        address caller = _msgSender();
        if (isSafe(caller)) {
            // Check if caller is a lead or superSafe of the target safe (checking with isTreeMember because is the same method!!)
            if (hasNotPermissionOverTarget(caller, org, targetSafe)) {
                revert Errors.NotAuthorizedExecOnBehalf();
            }
            // Caller is a safe then check caller's safe signatures.
            bytes memory keyperTxHashData = encodeTransactionData(
                /// Keyper Info
                caller,
                targetSafe,
                /// Transaction info
                to,
                value,
                data,
                operation,
                /// Signature info
                nonce
            );

            IGnosisSafe gnosisLeadSafe = IGnosisSafe(caller);
            gnosisLeadSafe.checkSignatures(
                keccak256(keyperTxHashData), keyperTxHashData, signatures
            );
        } else {
            // Caller is EAO (lead) : check if it has the rights over the target safe
            if (!isSafeLead(getGroupIdBySafe(org, targetSafe), caller)) {
                revert Errors.NotAuthorizedAsNotSafeLead();
            }
        }

        /// Increase nonce and execute transaction.
        nonce++;
        /// Execute transaction from target safe
        IGnosisSafe gnosisTargetSafe = IGnosisSafe(targetSafe);
        result = gnosisTargetSafe.execTransactionFromModule(
            to, value, data, operation
        );

        if (!result) revert Errors.TxOnBehalfExecutedFailed();
        emit Events.TxOnBehalfExecuted(org, caller, targetSafe, result);
    }

    /// @dev Function for enable Keyper module in a Gnosis Safe Multisig Wallet
    /// @param module Address of Keyper module
    function internalEnableModule(address module)
        external
        validAddress(module)
    {
        this.enableModule(module);
    }

    /// @dev Non-executed code, function called by the new safe
    /// @param module Address of Keyper module
    function enableModule(address module) external validAddress(module) {
        emit Events.ModuleEnabled(address(this), module);
    }

    /// @notice This function will allow Safe Lead & Safe Lead modify only roles
    /// @notice to to add owner and set a threshold without passing by normal multisig check
    /// @dev For instance addOwnerWithThreshold can be called by Safe Lead & Safe Lead modify only roles
    /// @param ownerAdded Address of the owner to be added
    /// @param threshold Threshold of the Gnosis Safe Multisig Wallet
    /// @param targetSafe Address of the Gnosis Safe Multisig Wallet
    /// @param org Hash(DAO's name)
    function addOwnerWithThreshold(
        address ownerAdded,
        uint256 threshold,
        address targetSafe,
        bytes32 org
    )
        external
        validAddress(ownerAdded)
        SafeRegistered(targetSafe)
        requiresAuth
    {
        address caller = _msgSender();
        if (hasNotPermissionOverTarget(caller, org, targetSafe)) {
            revert Errors.NotAuthorizedAddOwnerWithThreshold();
        }

        IGnosisSafe gnosisTargetSafe = IGnosisSafe(targetSafe);
        /// If the owner is already an owner
        if (gnosisTargetSafe.isOwner(ownerAdded)) {
            revert Errors.OwnerAlreadyExists();
        }

        bytes memory data = abi.encodeWithSelector(
            IGnosisSafe.addOwnerWithThreshold.selector, ownerAdded, threshold
        );
        /// Execute transaction from target safe
        bool result = gnosisTargetSafe.execTransactionFromModule(
            targetSafe, uint256(0), data, Enum.Operation.Call
        );
        if (!result) revert Errors.TxExecutionModuleFaild();
    }

    /// @notice This function will allow User Lead/Super/Root to remove an owner
    /// @dev For instance of Remove Owner of Gnosis Safe, the user lead/super/root can remove an owner without passing by normal multisig check signature
    /// @param prevOwner Address of the previous owner
    /// @param ownerRemoved Address of the owner to be removed
    /// @param threshold Threshold of the Gnosis Safe Multisig Wallet
    /// @param targetSafe Address of the Gnosis Safe Multisig Wallet
    /// @param org Hash(DAO's name)
    function removeOwner(
        address prevOwner,
        address ownerRemoved,
        uint256 threshold,
        address targetSafe,
        bytes32 org
    ) external SafeRegistered(targetSafe) requiresAuth {
        address caller = _msgSender();
        if (
            prevOwner == address(0) || ownerRemoved == address(0)
                || prevOwner == Constants.SENTINEL_ADDRESS
                || ownerRemoved == Constants.SENTINEL_ADDRESS
        ) {
            revert Errors.ZeroAddressProvided();
        }

        if (hasNotPermissionOverTarget(caller, org, targetSafe)) {
            revert Errors.NotAuthorizedRemoveOwner();
        }
        IGnosisSafe gnosisTargetSafe = IGnosisSafe(targetSafe);
        /// if Owner Not found
        if (!gnosisTargetSafe.isOwner(ownerRemoved)) {
            revert Errors.OwnerNotFound();
        }

        bytes memory data = abi.encodeWithSelector(
            IGnosisSafe.removeOwner.selector, prevOwner, ownerRemoved, threshold
        );

        /// Execute transaction from target safe
        bool result = gnosisTargetSafe.execTransactionFromModule(
            targetSafe, uint256(0), data, Enum.Operation.Call
        );
        if (!result) revert Errors.TxExecutionModuleFaild();
    }

    /// @notice This function checks that caller has permission (as Root/Super/Lead safe) of the target safe
    /// @param caller Caller's address
    /// @param org Hash(DAO's name)
    /// @param targetSafe Address of the target Gnosis Safe Multisig Wallet
    function hasNotPermissionOverTarget(
        address caller,
        bytes32 org,
        address targetSafe
    ) internal view returns (bool hasPermission) {
        hasPermission = !isRootSafeOf(caller, getGroupIdBySafe(org, targetSafe))
            && !isSuperSafe(
                getGroupIdBySafe(org, caller), getGroupIdBySafe(org, targetSafe)
            ) && !isSafeLead(getGroupIdBySafe(org, targetSafe), caller);
        return hasPermission;
    }

    /// @notice Give user roles
    /// @dev Call must come from the root safe
    /// @param role Role to be assigned
    /// @param user User that will have specific role (Can be EAO or safe)
    /// @param group Safe group which will have the user permissions on
    /// @param enabled Enable or disable the role
    function setRole(
        DataTypes.Role role,
        address user,
        uint256 group,
        bool enabled
    ) external validAddress(user) IsRootSafe(_msgSender()) requiresAuth {
        address caller = _msgSender();
        if (
            role == DataTypes.Role.ROOT_SAFE
                || role == DataTypes.Role.SUPER_SAFE
        ) {
            revert Errors.SetRoleForbidden(role);
        }
        if (!isRootSafeOf(caller, group)) {
            revert Errors.NotAuthorizedSetRoleAnotherTree();
        }
        DataTypes.Group storage safeGroup =
            groups[getOrgHashBySafe(caller)][group];
        // Check if group is part of the caller org
        if (
            role == DataTypes.Role.SAFE_LEAD
                || role == DataTypes.Role.SAFE_LEAD_EXEC_ON_BEHALF_ONLY
                || role == DataTypes.Role.SAFE_LEAD_MODIFY_OWNERS_ONLY
        ) {
            // Update group/org lead
            safeGroup.lead = user;
        }
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        _authority.setUserRole(user, uint8(role), enabled);
    }

    /// @notice Register an organization
    /// @dev Call has to be done from a safe transaction
    /// @param daoName String with of the org (This name will be hashed into smart contract)
    function registerOrg(string calldata daoName)
        external
        IsGnosisSafe(_msgSender())
        returns (uint256 groupId)
    {
        bytes32 name = keccak256(abi.encodePacked(daoName));
        address caller = _msgSender();
        groupId = _createOrgOrRoot(daoName, caller, caller);
        orgHash.push(name);
        // Setting level by Default
        depthTreeLimit[name] = 8;

        emit Events.OrganizationCreated(caller, name, daoName);
        return groupId;
    }

    /// @notice Call has to be done from another root safe to the organization
    /// @dev Call has to be done from a safe transaction
    /// @param newRootSafe Address of new Root Safe
    /// @param name string name of the group
    function createRootSafeGroup(address newRootSafe, string calldata name)
        external
        IsGnosisSafe(newRootSafe)
        IsRootSafe(_msgSender())
        requiresAuth
        returns (uint256 groupId)
    {
        address caller = _msgSender();
        bytes32 org = getOrgHashBySafe(caller);
        uint256 newIndex = indexId;
        groupId = _createOrgOrRoot(name, caller, newRootSafe);
        // Setting level by default
        depthTreeLimit[org] = 8;

        emit Events.RootSafeGroupCreated(
            org, newIndex, caller, newRootSafe, name
            );
    }

    /// @notice Add a group to an organization/group
    /// @dev Call coming from the group safe
    /// @param superSafe address of the superSafe
    /// @param name string name of the group
    function addGroup(uint256 superSafe, string memory name)
        external
        GroupRegistered(superSafe)
        IsGnosisSafe(_msgSender())
        returns (uint256 groupId)
    {
        // check the name of group is not empty
        if (bytes(name).length == 0) revert Errors.EmptyName();
        bytes32 org = getOrgByGroup(superSafe);
        address caller = _msgSender();
        if (isSafeRegistered(caller)) {
            revert Errors.SafeAlreadyRegistered(caller);
        }
        // check to verify if the caller is already exist in the org
        if (isTreeMember(superSafe, getGroupIdBySafe(org, caller))) {
            revert Errors.GroupAlreadyRegistered();
        }
        // check if the superSafe Reached Depth Tree Limit
        if (isLimitLevel(superSafe)) revert Errors.TreeDepthLimitReached();
        /// Create a new group
        DataTypes.Group storage newGroup = groups[org][indexId];
        /// Add to org root/group
        DataTypes.Group storage superSafeOrgGroup = groups[org][superSafe];
        /// Add child to superSafe
        groupId = indexId;
        superSafeOrgGroup.child.push(groupId);

        newGroup.safe = caller;
        newGroup.name = name;
        newGroup.superSafe = superSafe;
        indexGroup[org].push(groupId);
        indexId++;
        /// Give Role SuperSafe
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        if (
            (
                !_authority.doesUserHaveRole(
                    superSafeOrgGroup.safe, uint8(DataTypes.Role.SUPER_SAFE)
                )
            ) && (superSafeOrgGroup.child.length > 0)
        ) {
            _authority.setUserRole(
                superSafeOrgGroup.safe, uint8(DataTypes.Role.SUPER_SAFE), true
            );
        }

        emit Events.GroupCreated(
            org, groupId, newGroup.lead, caller, superSafe, name
            );
        return groupId;
    }

    /// @notice Remove group and reasign all child to the superSafe
    /// @dev All actions will be driven based on the caller of the method, and args
    /// @param group address of the group to be removed
    function removeGroup(uint256 group)
        external
        SafeRegistered(_msgSender())
        requiresAuth
    {
        address caller = _msgSender();
        bytes32 org = getOrgHashBySafe(caller);
        uint256 rootSafe = getGroupIdBySafe(org, caller);
        /// RootSafe usecase : Check if the group is part of caller's org
        if (
            (groups[org][rootSafe].tier == DataTypes.Tier.ROOT)
                && (!isTreeMember(rootSafe, group))
        ) {
            revert Errors.NotAuthorizedRemoveGroupFromOtherTree();
        }
        // SuperSafe usecase : Check caller is superSafe of the group
        if (!isSuperSafe(rootSafe, group)) {
            revert Errors.NotAuthorizedAsNotSuperSafe();
        }
        DataTypes.Group memory _group = groups[org][group];

        // superSafe is either an org or a group
        DataTypes.Group storage superSafe = groups[org][_group.superSafe];

        /// Remove child from superSafe
        for (uint256 i = 0; i < superSafe.child.length; i++) {
            if (superSafe.child[i] == group) {
                superSafe.child[i] = superSafe.child[superSafe.child.length - 1];
                superSafe.child.pop();
                break;
            }
        }
        // Handle child from removed group
        for (uint256 i = 0; i < _group.child.length; i++) {
            // Add removed group child to superSafe
            superSafe.child.push(_group.child[i]);
            DataTypes.Group storage childrenGroup = groups[org][_group.child[i]];
            // Update children group superSafe reference
            childrenGroup.superSafe = _group.superSafe;
        }

        // Revoke roles to group
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        _authority.setUserRole(
            _group.safe, uint8(DataTypes.Role.SUPER_SAFE), false
        );
        // Disable safe lead role
        disableSafeLeadRoles(_group.safe);

        // Store the name before to delete the Group
        emit Events.GroupRemoved(
            org, group, superSafe.safe, caller, _group.superSafe, _group.name
            );
        removeIndexGroup(org, group);
        delete groups[org][group];
    }

    /// @notice update superSafe of a group
    /// @dev Update the superSafe of a group with a new superSafe, Call must come from the root safe
    /// @param group address of the group to be updated
    /// @param newSuper address of the new superSafe
    function updateSuper(uint256 group, uint256 newSuper)
        public
        IsRootSafe(_msgSender())
        GroupRegistered(newSuper)
        requiresAuth
    {
        bytes32 org = getOrgByGroup(group);
        address caller = _msgSender();
        /// RootSafe usecase : Check if the group is Member of the Tree of the caller (rootSafe)
        if (!isRootSafeOf(caller, group)) {
            revert Errors.NotAuthorizedUpdateNonChildrenGroup();
        }
        /// Check if the new Super Safe is Reached Depth Tree Limit
        if (isLimitLevel(newSuper)) revert Errors.TreeDepthLimitReached();
        DataTypes.Group storage _group = groups[org][group];
        /// SuperSafe is either an Org or a Group
        DataTypes.Group storage oldSuper = groups[org][_group.superSafe];

        /// Remove child from superSafe
        for (uint256 i = 0; i < oldSuper.child.length; i++) {
            if (oldSuper.child[i] == group) {
                oldSuper.child[i] = oldSuper.child[oldSuper.child.length - 1];
                oldSuper.child.pop();
                break;
            }
        }
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        /// Revoke SuperSafe and SafeLead if don't have any child, and is not organization
        if (oldSuper.child.length == 0) {
            _authority.setUserRole(
                oldSuper.safe, uint8(DataTypes.Role.SUPER_SAFE), false
            );
            /// TODO: verify if the oldSuper need or not the Safe Lead role (after MVP)
        }

        /// Update group superSafe
        _group.superSafe = newSuper;
        DataTypes.Group storage newSuperGroup = groups[org][newSuper];
        /// Add group to new superSafe
        /// Give Role SuperSafe if not have it
        if (
            !_authority.doesUserHaveRole(
                newSuperGroup.safe, uint8(DataTypes.Role.SUPER_SAFE)
            )
        ) {
            _authority.setUserRole(
                newSuperGroup.safe, uint8(DataTypes.Role.SUPER_SAFE), true
            );
        }
        newSuperGroup.child.push(group);
        emit Events.GroupSuperUpdated(
            org,
            group,
            _group.lead,
            caller,
            getGroupIdBySafe(org, oldSuper.safe),
            newSuper
            );
    }

    /// @dev Method to update Depth Tree Limit
    /// @param newLimit new Depth Tree Limit
    function updateDepthTreeLimit(uint256 newLimit)
        external
        IsRootSafe(_msgSender())
        requiresAuth
    {
        address caller = _msgSender();
        bytes32 org = getOrgHashBySafe(caller);
        uint256 rootSafe = getGroupIdBySafe(org, caller);
        if ((newLimit > maxDepthTreeLimit) || (newLimit <= depthTreeLimit[org]))
        {
            revert Errors.InvalidLimit();
        }
        emit Events.NewLimitLevel(
            org, rootSafe, caller, depthTreeLimit[org], newLimit
            );
        depthTreeLimit[org] = newLimit;
    }

    /// List of the Methods of DenyHelpers
    /// Any changes in this five methods, must be validate into the abstract contract DenyHelper

    /// @dev Funtion to Add Wallet to the List based on Approach of Safe Contract - Owner Manager
    /// @param users Array of Address of the Wallet to be added to the List
    function addToList(address[] memory users)
        external
        IsRootSafe(_msgSender())
        requiresAuth
    {
        if (users.length == 0) revert Errors.ZeroAddressProvided();
        bytes32 org = getOrgHashBySafe(_msgSender());
        if (!allowFeature[org] && !denyFeature[org]) {
            revert Errors.DenyHelpersDisabled();
        }
        address currentWallet = Constants.SENTINEL_ADDRESS;
        for (uint256 i = 0; i < users.length; i++) {
            address wallet = users[i];
            if (
                wallet == address(0) || wallet == Constants.SENTINEL_ADDRESS
                    || wallet == address(this) || currentWallet == wallet
            ) revert Errors.InvalidAddressProvided();
            // Avoid duplicate wallet
            if (listed[org][wallet] != address(0)) {
                revert Errors.UserAlreadyOnList();
            }
            // Add wallet to List
            listed[org][currentWallet] = wallet;
            currentWallet = wallet;
        }
        listed[org][currentWallet] = Constants.SENTINEL_ADDRESS;
        listCount[org] += users.length;
        emit Events.AddedToList(users);
    }

    /// @dev Function to Drop Wallet from the List  based on Approach of Safe Contract - Owner Manager
    /// @param user Array of Address of the Wallet to be dropped of the List
    function dropFromList(address user)
        external
        validAddress(user)
        IsRootSafe(_msgSender())
        requiresAuth
    {
        bytes32 org = getOrgHashBySafe(_msgSender());
        if (!allowFeature[org] && !denyFeature[org]) {
            revert Errors.DenyHelpersDisabled();
        }
        if (listCount[org] == 0) revert Errors.ListEmpty();
        if (!isListed(org, user)) revert Errors.InvalidAddressProvided();
        address prevUser = getPrevUser(org, user);
        listed[org][prevUser] = listed[org][user];
        listed[org][user] = address(0);
        listCount[org] = listCount[org] > 1 ? listCount[org].sub(1) : 0;
        emit Events.DroppedFromList(user);
    }

    /// @dev Method to Enable Allowlist
    function enableAllowlist() external IsRootSafe(_msgSender()) requiresAuth {
        bytes32 org = getOrgHashBySafe(_msgSender());
        allowFeature[org] = true;
        denyFeature[org] = false;
    }

    /// @dev Method to Enable Allowlist
    function enableDenylist() external IsRootSafe(_msgSender()) requiresAuth {
        bytes32 org = getOrgHashBySafe(_msgSender());
        allowFeature[org] = false;
        denyFeature[org] = true;
    }

    /// @dev Method to Disable All
    function disableDenyHelper()
        external
        IsRootSafe(_msgSender())
        requiresAuth
    {
        bytes32 org = getOrgHashBySafe(_msgSender());
        allowFeature[org] = false;
        denyFeature[org] = false;
    }

    // List of Helpers

    /// @notice Get all the information about a group
    /// @dev Method for getting all info of a group
    /// @param group uint256 of the group
    /// @return all the information about a group
    function getGroupInfo(uint256 group)
        public
        view
        GroupRegistered(group)
        returns (
            DataTypes.Tier,
            string memory,
            address,
            address,
            uint256[] memory,
            uint256
        )
    {
        bytes32 org = getOrgByGroup(group);
        return (
            groups[org][group].tier,
            groups[org][group].name,
            groups[org][group].lead,
            groups[org][group].safe,
            groups[org][group].child,
            groups[org][group].superSafe
        );
    }

    /// @notice check if the organisation is registered
    /// @param org address
    /// @return bool
    function isOrgRegistered(bytes32 org) public view returns (bool) {
        if (indexGroup[org].length == 0 || org == bytes32(0)) return false;
        return true;
    }

    /// @notice Check if the address, is a rootSafe of the group within an organization
    /// @param group ID's of the child group/safe
    /// @param root address of Root Safe of the group
    /// @return bool
    function isRootSafeOf(address root, uint256 group)
        public
        view
        GroupRegistered(group)
        returns (bool)
    {
        if (root == address(0) || group == 0) return false;
        bytes32 org = getOrgByGroup(group);
        uint256 rootSafe = getGroupIdBySafe(org, root);
        if (rootSafe == 0) return false;
        return (
            (groups[org][rootSafe].tier == DataTypes.Tier.ROOT)
                && (isTreeMember(rootSafe, group))
        );
    }

    /// @notice Check if the group is a superSafe of another group
    /// @param superSafe ID's of the superSafe
    /// @param group ID's of the group
    /// @return bool
    function isTreeMember(uint256 superSafe, uint256 group)
        public
        view
        returns (bool)
    {
        if (superSafe == 0 || group == 0) return false;
        bytes32 org = getOrgByGroup(superSafe);
        DataTypes.Group memory childGroup = groups[org][group];
        if (childGroup.safe == address(0)) return false;
        /// TODO: verify if is not redundant
        if (groups[org][superSafe].safe == address(0)) return false;
        /// TODO: verify is open a back door
        if (childGroup.safe == groups[org][superSafe].safe) return true;
        uint256 currentSuperSafe = childGroup.superSafe;
        /// TODO: probably more efficient to just create a superSafes mapping instead of this iterations
        while (currentSuperSafe != 0) {
            if (currentSuperSafe == superSafe) return true;
            childGroup = groups[org][currentSuperSafe];
            currentSuperSafe = childGroup.superSafe;
        }
        return false;
    }

    /// @dev Method to validate if is Depth Tree Limit
    /// @param superSafe ID's of Safe
    /// @return bool
    function isLimitLevel(uint256 superSafe) public view returns (bool) {
        bytes32 org = getOrgByGroup(superSafe);
        DataTypes.Group memory childGroup = groups[org][superSafe];
        uint256 currentSuperSafe = childGroup.superSafe;
        for (uint256 i = 1; i < depthTreeLimit[org]; i++) {
            if (currentSuperSafe == 0) return false;
            childGroup = groups[org][currentSuperSafe];
            currentSuperSafe = childGroup.superSafe;
        }
        return true;
    }

    /// @dev Method to Validate is ID Group a SuperSafe of a Group
    /// @param group ID's of the group
    /// @param superSafe ID's of the Safe
    /// @return bool
    function isSuperSafe(uint256 superSafe, uint256 group)
        public
        view
        returns (bool)
    {
        if (superSafe == 0 || group == 0) return false;
        bytes32 org = getOrgByGroup(superSafe);
        DataTypes.Group memory childGroup = groups[org][group];
        if (childGroup.safe == address(0)) return false;
        uint256 currentSuperSafe = childGroup.superSafe;
        return (currentSuperSafe == superSafe);
    }

    function isSafeRegistered(address safe) public view returns (bool) {
        if ((safe == address(0)) || safe == Constants.SENTINEL_ADDRESS) {
            return false;
        }
        if (getOrgHashBySafe(safe) == bytes32(0)) return false;
        if (getGroupIdBySafe(getOrgHashBySafe(safe), safe) == 0) return false;
        return true;
    }

    /// @notice Get the safe address of a group
    /// @dev Method for getting the safe address of a group
    /// @param group uint256 of the group
    /// @return safe address
    function getGroupSafeAddress(uint256 group)
        public
        view
        GroupRegistered(group)
        returns (address)
    {
        bytes32 org = getOrgByGroup(group);
        return groups[org][group].safe;
    }

    /// @dev Method to get Org by Safe
    /// @param safe address of Safe
    /// @return Org Hashed Name
    function getOrgHashBySafe(address safe) public view returns (bytes32) {
        for (uint256 i = 0; i < orgHash.length; i++) {
            if (getGroupIdBySafe(orgHash[i], safe) != 0) {
                return orgHash[i];
            }
        }
        return bytes32(0);
    }

    /// @dev Method to get Group ID by safe address
    /// @param org bytes32 hashed name of the Organization
    /// @param safe Safe address
    /// @return Group ID
    function getGroupIdBySafe(bytes32 org, address safe)
        public
        view
        returns (uint256)
    {
        if (!isOrgRegistered(org)) {
            revert Errors.OrgNotRegistered(org);
        }
        /// Check if the Safe address is into an Group mapping
        for (uint256 i = 0; i < indexGroup[org].length; i++) {
            if (groups[org][indexGroup[org][i]].safe == safe) {
                return indexGroup[org][i];
            }
        }
        return 0;
    }

    /// @notice call to get the orgHash based on group id
    /// @dev Method to get the hashed orgHash based on group id
    /// @param group uint256 of the group
    /// @return orgGroup Hash (Dao's Name)
    function getOrgByGroup(uint256 group)
        public
        view
        returns (bytes32 orgGroup)
    {
        if ((group == 0) || (group > indexId)) revert Errors.InvalidGroupId();
        for (uint256 i = 0; i < orgHash.length; i++) {
            if (groups[orgHash[i]][group].safe != address(0)) {
                orgGroup = orgHash[i];
            }
        }
        if (orgGroup == bytes32(0)) revert Errors.GroupNotRegistered(group);
    }

    /// @notice Check if a user is an safe lead of a group/org
    /// @param group address of the group
    /// @param user address of the user that is a lead or not
    /// @return bool
    function isSafeLead(uint256 group, address user)
        public
        view
        returns (bool)
    {
        bytes32 org = getOrgByGroup(group);
        DataTypes.Group memory _group = groups[org][group];
        if (_group.safe == address(0)) return false;
        if (_group.lead == user) {
            return true;
        }
        return false;
    }

    /// @notice Method to Validate if address is a Gnosis Safe Multisig Wallet
    /// @dev This method is used to validate if the address is a Gnosis Safe Multisig Wallet
    /// @param safe Address to validate
    /// @return bool
    function isSafe(address safe) public view returns (bool) {
        /// Check if the address is a Gnosis Safe Multisig Wallet
        if (safe.isContract()) {
            /// Check if the address is a Gnosis Safe Multisig Wallet
            bytes memory payload = abi.encodeWithSignature("getThreshold()");
            (bool success, bytes memory returnData) = safe.staticcall(payload);
            if (!success) return false;
            /// Check if the address is a Gnosis Safe Multisig Wallet
            uint256 threshold = abi.decode(returnData, (uint256));
            if (threshold == 0) return false;
            return true;
        } else {
            return false;
        }
    }

    /// @dev Method to get the domain separator for Keyper Module
    /// @return Hash of the domain separator
    function domainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(Constants.DOMAIN_SEPARATOR_TYPEHASH, getChainId(), this)
        );
    }

    /// @dev Returns the chain id used by this contract.
    /// @return The Chain ID
    function getChainId() public view returns (uint256) {
        uint256 id;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }

    /// @dev Method to get the Encoded Packed Data for Keyper Transaction
    /// @param caller address of the caller
    /// @param safe address of the Safe
    /// @param to address of the receiver
    /// @param value value of the transaction
    /// @param data data of the transaction
    /// @param operation operation of the transaction
    /// @param _nonce nonce of the transaction
    /// @return Hash of the encoded data
    function encodeTransactionData(
        address caller,
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 _nonce
    ) public view returns (bytes memory) {
        bytes32 keyperTxHash = keccak256(
            abi.encode(
                Constants.KEYPER_TX_TYPEHASH,
                caller,
                safe,
                to,
                value,
                keccak256(data),
                operation,
                _nonce
            )
        );
        return abi.encodePacked(
            bytes1(0x19), bytes1(0x01), domainSeparator(), keyperTxHash
        );
    }

    /// @dev Method to get the Hash Encoded Packed Data for Keyper Transaction
    /// @param caller address of the caller
    /// @param safe address of the Safe
    /// @param to address of the receiver
    /// @param value value of the transaction
    /// @param data data of the transaction
    /// @param operation operation of the transaction
    /// @param _nonce nonce of the transaction
    /// @return Hash of the encoded packed data
    function getTransactionHash(
        address caller,
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 _nonce
    ) public view returns (bytes32) {
        return keccak256(
            encodeTransactionData(
                caller, safe, to, value, data, operation, _nonce
            )
        );
    }

    /// @notice disable safe lead roles
    /// @dev Associated roles: SAFE_LEAD || SAFE_LEAD_EXEC_ON_BEHALF_ONLY || SAFE_LEAD_MODIFY_OWNERS_ONLY
    /// @param user Address of the user to disable roles
    function disableSafeLeadRoles(address user) private {
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        if (_authority.doesUserHaveRole(user, uint8(DataTypes.Role.SAFE_LEAD)))
        {
            _authority.setUserRole(user, uint8(DataTypes.Role.SAFE_LEAD), false);
        } else if (
            _authority.doesUserHaveRole(
                user, uint8(DataTypes.Role.SAFE_LEAD_EXEC_ON_BEHALF_ONLY)
            )
        ) {
            _authority.setUserRole(
                user, uint8(DataTypes.Role.SAFE_LEAD_EXEC_ON_BEHALF_ONLY), false
            );
        } else if (
            _authority.doesUserHaveRole(
                user, uint8(DataTypes.Role.SAFE_LEAD_MODIFY_OWNERS_ONLY)
            )
        ) {
            _authority.setUserRole(
                user, uint8(DataTypes.Role.SAFE_LEAD_MODIFY_OWNERS_ONLY), false
            );
        }
    }

    /// @notice Private method to remove indexId from mapping of indexes into organizations
    /// @param org ID's of the organization
    /// @param group uint256 of the group
    function removeIndexGroup(bytes32 org, uint256 group) private {
        for (uint256 i = 0; i < indexGroup[org].length; i++) {
            if (indexGroup[org][i] == group) {
                indexGroup[org][i] = indexGroup[org][indexGroup[org].length - 1];
                indexGroup[org].pop();
                break;
            }
        }
    }

    /// @notice Refactoring method for Create Org or RootSafe
    /// @dev Method Internal for Create Org or RootSafe
    /// @param name String Name of the Organization
    /// @param caller Safe Caller to Create Org or RootSafe
    /// @param newRootSafe Safe Address to Create Org or RootSafe
    function _createOrgOrRoot(
        string memory name,
        address caller,
        address newRootSafe
    ) private returns (uint256 groupId) {
        if (bytes(name).length == 0) {
            revert Errors.EmptyName();
        }
        bytes32 org = caller == newRootSafe
            ? bytes32(keccak256(abi.encodePacked(name)))
            : getOrgHashBySafe(caller);
        if (isOrgRegistered(org) && caller == newRootSafe) {
            revert Errors.OrgAlreadyRegistered(org);
        }
        if (isSafeRegistered(newRootSafe)) {
            revert Errors.SafeAlreadyRegistered(newRootSafe);
        }
        groupId = indexId;
        groups[org][groupId] = DataTypes.Group({
            tier: DataTypes.Tier.ROOT,
            name: name,
            lead: address(0),
            safe: newRootSafe,
            child: new uint256[](0),
            superSafe: 0
        });
        indexGroup[org].push(groupId);
        indexId++;

        /// Assign SUPER_SAFE Role + SAFE_ROOT Role
        RolesAuthority _authority = RolesAuthority(rolesAuthority);
        _authority.setUserRole(
            newRootSafe, uint8(DataTypes.Role.ROOT_SAFE), true
        );
        _authority.setUserRole(
            newRootSafe, uint8(DataTypes.Role.SUPER_SAFE), true
        );
    }
}
