// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.15;

import {Enum} from "@safe-contracts/common/Enum.sol";
import {GnosisSafeMath} from "@safe-contracts/external/GnosisSafeMath.sol";
import {IGnosisSafe, IGnosisSafeProxy} from "./GnosisSafeInterfaces.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Constants} from "./Constants.sol";
import {DenyHelper} from "./DenyHelper.sol";
import {console} from "forge-std/console.sol";
import {KeyperRoles} from "./KeyperRoles.sol";

contract KeyperModule is Auth, Constants, DenyHelper {
    using GnosisSafeMath for uint256;
    /// @dev Definition of Safe module

    string public constant NAME = "Keyper Module";
    string public constant VERSION = "0.2.0";
    /// @dev Control Nonce of the module
    uint256 public nonce;
    /// @dev Safe contracts
    address public immutable masterCopy;
    address public immutable proxyFactory;
    address internal constant SENTINEL_OWNERS = address(0x1);
    /// @dev RoleAuthority
    address public rolesAuthority;
    /// @devStruct for Group

    struct Group {
        string name;
        address admin;
        address safe;
        address[] childs;
        address parent;
    }
    /// @dev Orgs -> Groups

    mapping(address => mapping(address => Group)) public groups;
    /// @dev Orgs info
    mapping(address => Group) public orgs;
    /// @dev Events

    event OrganisationCreated(address indexed org, string name);

    event GroupCreated(
        address indexed org,
        address indexed group,
        string name,
        address indexed admin,
        address parent
    );

    event TxOnBehalfExecuted(
        address indexed org,
        address indexed executor,
        address indexed target,
        bool result
    );

    event ModuleEnabled(address indexed safe, address indexed module);

    /// @dev Errors
    error OrgNotRegistered();
    error GroupNotRegistered();
    error ParentNotRegistered();
    error AdminNotRegistered();
    error NotAuthorized();
    error NotAuthorizedExecOnBehalf();
    error NotAuthorizedAsNotSafeLead();
    error OwnerNotFound();
    error OwnerAlreadyExists();
    error CreateSafeProxyFailed();
    error ZeroAddress();
    error InvalidThreshold();
    error TxExecutionModuleFaild();

    /// @dev Modifier for Validate if Org Exist or Not
    modifier OrgRegistered(address org) {
        if (org == address(0) || orgs[org].safe == address(0)) {
            revert OrgNotRegistered();
        }
        _;
    }

    constructor(
        address masterCopyAddress,
        address proxyFactoryAddress,
        address authority
    ) Auth(address(0), Authority(authority)) {
        if (
            masterCopyAddress == address(0) || proxyFactoryAddress == address(0)
                || authority == address(0)
        ) revert ZeroAddress();

        masterCopy = masterCopyAddress;
        proxyFactory = proxyFactoryAddress;
        rolesAuthority = authority;
    }

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
            FALLBACK_HANDLER,
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
            revert CreateSafeProxyFailed();
        }
    }

    /// @notice Calls execTransaction of the safe with custom checks on owners rights
    /// @param org Organisation
    /// @param targetSafe Safe target address
    /// @param to data
    function execTransactionOnBehalf(
        address org,
        address targetSafe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        bytes memory signatures
    ) external payable requiresAuth returns (bool success) {
        if (org == address(0) || targetSafe == address(0) || to == address(0)) {
            revert ZeroAddress();
        }

        address caller = _msgSender();
        /// Check _msgSender() is an admin of the target safe
        if (!isAdmin(caller, targetSafe) && !isParent(org, caller, targetSafe))
        {
            revert NotAuthorizedExecOnBehalf();
        }
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
        /// Increase nonce and execute transaction.
        nonce++;
        /// TODO not sure about caller => Maybe just check admin address
        // TODO add usecase for safe lead => Caller can be an EOA account,
        // so first we need to check if safe, if yes load gnosis interface + call owners...,
        // if not then just execute the tx after checking signature
        /// Init safe interface to get parent owners/threshold
        IGnosisSafe gnosisAdminSafe = IGnosisSafe(caller);
        gnosisAdminSafe.checkSignatures(
            keccak256(keyperTxHashData), keyperTxHashData, signatures
        );
        /// Execute transaction from target safe
        IGnosisSafe gnosisTargetSafe = IGnosisSafe(targetSafe);
        bool result = gnosisTargetSafe.execTransactionFromModule(
            to, value, data, operation
        );
        emit TxOnBehalfExecuted(org, caller, targetSafe, result);
        return result;
    }

    function internalEnableModule(address module)
        external
        validAddress(module)
    {
        this.enableModule(module);
    }

    /// @dev Non-executed code, function called by the new safe
    function enableModule(address module) external validAddress(module) {
        emit ModuleEnabled(address(this), module);
    }

    /// @notice This function will allow Safe Lead & Safe Lead mody only roles to to add owner and set a threshold without passing by normal multisig check
    /// @dev For instance role
    /// TODO add modifier for check that targetSafe is a Safe / Check orgRegister
    function addOwnerWithThreshold(
        address owner,
        uint256 threshold,
        address targetSafe,
        address org
    ) public requiresAuth {
        /// Check _msgSender() is an user admin of the target safe
        if (!isSafeLead(org, targetSafe, _msgSender())) {
            revert NotAuthorizedAsNotSafeLead();
        }

        /// If the owner is already an owner
        if (isSafeOwner(IGnosisSafe(targetSafe), owner)) {
            revert OwnerAlreadyExists();
        }

        /// if threshold is invalid
        if (
            threshold < 1
                || threshold > (IGnosisSafe(targetSafe).getOwners().length.add(1))
        ) {
            revert InvalidThreshold();
        }

        bytes memory data = abi.encodeWithSelector(
            IGnosisSafe.addOwnerWithThreshold.selector, owner, threshold
        );
        IGnosisSafe gnosisTargetSafe = IGnosisSafe(targetSafe);
        /// Execute transaction from target safe
        bool result = gnosisTargetSafe.execTransactionFromModule(
            targetSafe, uint256(0), data, Enum.Operation.Call
        );
        if (!result) revert TxExecutionModuleFaild();
    }

    /// @notice This function will allow UserAdmin to remove an owner
    /// @dev For instance role
    function removeOwner(
        address prevOwner,
        address owner,
        uint256 threshold,
        address targetSafe,
        address org
    ) public requiresAuth {
        if (
            prevOwner == address(0) || targetSafe == address(0)
                || owner == address(0) || org == address(0)
        ) revert ZeroAddress();
        /// Check _msgSender() is an user admin of the target safe
        if (!isSafeLead(org, targetSafe, _msgSender())) {
            revert NotAuthorizedAsNotSafeLead();
        }

        /// if Owner Not found
        if (!isSafeOwner(IGnosisSafe(targetSafe), owner)) {
            revert OwnerNotFound();
        }

        IGnosisSafe gnosisTargetSafe = IGnosisSafe(targetSafe);

        bytes memory data = abi.encodeWithSelector(
            IGnosisSafe.removeOwner.selector, prevOwner, owner, threshold
        );

        /// Execute transaction from target safe
        bool result = gnosisTargetSafe.execTransactionFromModule(
            targetSafe, uint256(0), data, Enum.Operation.Call
        );
        if (!result) revert TxExecutionModuleFaild();
    }

    /// @notice Give user roles
    /// @dev Call must come from the root safe
    /// @param role Role to be assigned
    /// @param user User that will have specific role
    /// @param group Safe group which will have the user permissions on
    function setRole(uint8 role, address user, address group, bool enabled)
        external
        validAddress(user)
        requiresAuth
    {
        if (
            role == SAFE_LEAD || role == SAFE_LEAD_EXEC_ON_BEHALF_ONLY
                || role == SAFE_LEAD_MODIFY_OWNERS_ONLY
        ) {
            /// Check if group is part of the org
            if (groups[_msgSender()][group].safe == address(0)) {
                revert ParentNotRegistered();
            }
            /// Update group admin
            Group storage safeGroup = groups[_msgSender()][group];
            safeGroup.admin = user;
        }
        // TODO check other cases when we need to update org
        RolesAuthority authority = RolesAuthority(rolesAuthority);
        authority.setUserRole(user, role, enabled);
    }

    function getOrg(address _org)
        public
        view
        OrgRegistered(_org)
        returns (string memory, address, address, address)
    {
        return (
            orgs[_org].name,
            orgs[_org].admin,
            orgs[_org].safe,
            orgs[_org].parent
        );
    }

    /// @notice Register an organisatin
    /// @dev Call has to be done from a safe transaction
    /// @param name of the org
    function registerOrg(string memory name) public {
        /// TODO: Add check to verify call is coming from a safe
        address caller = _msgSender();
        Group storage rootOrg = orgs[caller];
        rootOrg.admin = caller;
        rootOrg.name = name;
        rootOrg.safe = caller;

        /// Assign SAFE_LEAD Role + SAFE_ROOT Role
        RolesAuthority authority = RolesAuthority(rolesAuthority);
        authority.setUserRole(caller, ROOT_SAFE, true);
        authority.setUserRole(caller, SAFE_LEAD, true);

        emit OrganisationCreated(caller, name);
    }

    /// @notice Add a group to an organisation/group
    /// @dev Call coming from the group safe
    /// @param org address of the organisation
    /// @param parent address of the parent
    /// @param name name of the group
    function addGroup(address org, address parent, string memory name)
        public
        OrgRegistered(org)
        validAddress(parent)
    {
        address caller = _msgSender();
        Group storage newGroup = groups[org][caller];
        /// Add to org root
        if (parent == org) {
            ///  By default Admin of the new group is the admin of the org
            newGroup.admin = orgs[org].admin;
            Group storage parentOrg = orgs[org];
            parentOrg.childs.push(caller);
        }
        /// Add to group
        else {
            if (groups[org][parent].safe == address(0)) {
                revert ParentNotRegistered();
            }

            /// By default Admin of the new group is the admin of the parent (TODO check this)
            newGroup.admin = groups[org][parent].admin;
            Group storage parentGroup = groups[org][parent];
            parentGroup.childs.push(caller);
        }
        newGroup.parent = parent;
        newGroup.safe = caller;
        newGroup.name = name;
        /// Give Role SuperSafe
        RolesAuthority authority = RolesAuthority(rolesAuthority);
        authority.setUserRole(caller, SUPER_SAFE, true);

        emit GroupCreated(org, caller, name, newGroup.admin, parent);
    }

    /// @notice Get all the information about a group
    function getGroupInfo(address org, address group)
        public
        view
        OrgRegistered(org)
        validAddress(group)
        returns (string memory, address, address, address)
    {
        address groupSafe = groups[org][group].safe;
        if (groupSafe == address(0)) revert OrgNotRegistered();
        return (
            groups[org][group].name,
            groups[org][group].admin,
            groups[org][group].safe,
            groups[org][group].parent
        );
    }

    /// @notice check if the organisation is registered
    /// @param org address
    function isOrgRegistered(address org) public view returns (bool) {
        if (orgs[org].safe == address(0)) return false;
        return true;
    }

    /// @notice Check if child address is part of the group within an organisation
    function isChild(address org, address parent, address child)
        public
        view
        returns (bool)
    {
        /// Check within orgs first if parent is an organisation
        if (org == parent) {
            Group memory organisation = orgs[org];
            for (uint256 i = 0; i < organisation.childs.length; i++) {
                if (organisation.childs[i] == child) return true;
            }
        }
        /// Check within groups of the org
        if (groups[org][parent].safe == address(0)) {
            revert ParentNotRegistered();
        }
        Group memory group = groups[org][parent];
        for (uint256 i = 0; i < group.childs.length; i++) {
            if (group.childs[i] == child) return true;
        }
        return false;
    }

    /// @notice Check if an org is admin of the group
    function isAdmin(address org, address group) public view returns (bool) {
        if (orgs[org].safe == address(0)) return false;
        /// Check group admin
        Group memory _group = groups[org][group];
        if (_group.admin == org) {
            return true;
        }
        return false;
    }

    /// @notice Check if a user is an admin of the org
    function isUserAdmin(address org, address user)
        public
        view
        returns (bool)
    {
        Group memory _org = orgs[org];
        if (_org.admin == user) {
            return true;
        }
        return false;
    }

    /// @notice Check if a user is an safe lead of the group
    function isSafeLead(address org, address group, address user)
        public
        view
        returns (bool)
    {
        if (org == group) return false; // Root org cannot have a lead
        Group memory _group = groups[org][group];
        if (_group.safe == address(0)) revert GroupNotRegistered();
        if (_group.admin == user) {
            return true;
        }
        return false;
    }

    /// @notice Check if the group is a parent of another group
    function isParent(address org, address parent, address child)
        public
        view
        returns (bool)
    {
        Group memory childGroup = groups[org][child];
        address curentParent = childGroup.parent;
        /// TODO: probably more efficient to just create a parents mapping instead of this iterations
        while (curentParent != address(0)) {
            if (curentParent == parent) return true;
            childGroup = groups[org][curentParent];
            curentParent = childGroup.parent;
        }
        return false;
    }

    function domainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(DOMAIN_SEPARATOR_TYPEHASH, getChainId(), this)
        );
    }

    /// @dev Returns the chain id used by this contract.
    function getChainId() public view returns (uint256) {
        uint256 id;
        /// solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }

    function encodeTransactionData(
        address org,
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 _nonce
    ) public view returns (bytes memory) {
        bytes32 keyperTxHash = keccak256(
            abi.encode(
                KEYPER_TX_TYPEHASH,
                org,
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

    function getTransactionHash(
        address org,
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 _nonce
    ) public view returns (bytes32) {
        return keccak256(
            encodeTransactionData(org, safe, to, value, data, operation, _nonce)
        );
    }

    /// @notice Check if the signer is an owner of the safe
    /// @dev Call has to be done from a safe transaction
    /// @param gnosisSafe GnosisSafe interface
    /// @param signer Address of the signer to verify
    function isSafeOwner(IGnosisSafe gnosisSafe, address signer)
        private
        view
        returns (bool)
    {
        address[] memory safeOwners = gnosisSafe.getOwners();
        for (uint256 i = 0; i < safeOwners.length; i++) {
            if (safeOwners[i] == signer) {
                return true;
            }
        }
        return false;
    }
}
