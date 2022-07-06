// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Enum} from "@safe-contracts/common/Enum.sol";
import {SignatureDecoder} from "@safe-contracts/common/SignatureDecoder.sol";
import {ISignatureValidator} from "@safe-contracts/interfaces/ISignatureValidator.sol";
import {ISignatureValidatorConstants} from "@safe-contracts/interfaces/ISignatureValidator.sol";
import {console} from "forge-std/console.sol";
import {GnosisSafeMath} from "@safe-contracts/external/GnosisSafeMath.sol";

interface GnosisSafe {
    /// @dev Allows a Module to execute a Safe transaction without any further confirmations.
    /// @param to Destination address of module transaction.
    /// @param value Ether value of module transaction.
    /// @param data Data payload of module transaction.
    /// @param operation Operation type of module transaction.
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external returns (bool success);

    /// @dev Allows to execute a Safe transaction confirmed by required number of owners and then pays the account that submitted the transaction.
    ///      Note: The fees are always transferred, even if the user transaction fails.
    /// @param to Destination address of Safe transaction.
    /// @param value Ether value of Safe transaction.
    /// @param data Data payload of Safe transaction.
    /// @param operation Operation type of Safe transaction.
    /// @param safeTxGas Gas that should be used for the Safe transaction.
    /// @param baseGas Gas costs that are independent of the transaction execution(e.g. base transaction fee, signature check, payment of the refund)
    /// @param gasPrice Gas price that should be used for the payment calculation.
    /// @param gasToken Token address (or 0 if ETH) that is used for the payment.
    /// @param refundReceiver Address of receiver of gas payment (or 0 if tx.origin).
    /// @param signatures Packed signature data ({bytes32 r}{bytes32 s}{uint8 v})
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);

    /// @dev Returns array of owners.
    /// @return Array of Safe owners.
    function getOwners() external view returns (address[] memory);

    function getThreshold() external view returns (uint256);
}

// TODO modifiers for auth calling the diff functions
// TODO define how secure this setup should be: Calls only from Admin? Calls from safe contract (with multisig rule)
// TODO update signers set
contract KeyperModule is SignatureDecoder, ISignatureValidatorConstants {
    string public constant NAME = "Keyper Module";
    string public constant VERSION = "0.1.0";

    // keccak256(
    //     "EIP712Domain(uint256 chainId,address verifyingContract)"
    // );
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

    // keccak256(
    //     "KeyperTx(address org,address safe,address to,uint256 value,bytes data,uint8 operation,uint256 nonce)"
    // );
    bytes32 private constant KEYPER_TX_TYPEHASH =
        0xbb667b7bf67815e546e48fb8d0e6af5c31fe53b9967ed45225c9d55be21652da;
    using GnosisSafeMath for uint256;

    // Orgs -> Groups
    mapping(address => mapping(address => Group)) public groups;
    // Safe -> full set of signers
    // mapping(address => mapping(address => bool)) public signers;

    // Orgs info
    mapping(address => Group) public orgs;

    uint256 public nonce;
    address internal constant SENTINEL_OWNERS = address(0x1);

    // Errors
    error OrgNotRegistered();
    error GroupNotRegistered();
    error ParentNotRegistered();
    error AdminNotRegistered();
    error NotAuthorized();
    error NotAuthorizedExecOnBehalf();

    struct Group {
        string name;
        address admin;
        address safe;
        mapping(address => bool) childs;
        address parent;
    }

    struct TransactionHelper {
        Enum.Operation operation;
        uint256 safeTxGas;
        uint256 baseGas;
        uint256 gasPrice;
        address gasToken;
    }

    modifier onlyAdmin(address _group) {
        require(_group != address(0));
        if (orgs[msg.sender].safe == address(0)) revert AdminNotRegistered();
        Group storage group = groups[msg.sender][_group];
        // if (msg.sender != group.admin) revert NotAuthorized();
        // TODO ADD case when adding a group that has not been set his admin
        // In this case we should just check that the Admin is an org
        // Add later check on addGroup function that will reverify the correct org is the admin
        _;
    }

    function getOrg(address _org)
        public
        view
        returns (
            string memory,
            address,
            address,
            address
        )
    {
        require(_org != address(0));
        if (orgs[_org].safe == address(0)) revert OrgNotRegistered();
        return (
            orgs[_org].name,
            orgs[_org].admin,
            orgs[_org].safe,
            orgs[_org].parent
        );
    }

    function createOrg(string memory _name) public {
        Group storage rootOrg = orgs[msg.sender];
        rootOrg.admin = msg.sender;
        rootOrg.name = _name;
        rootOrg.safe = msg.sender;
    }

    // TODO call auth modifier (only admin can add a group)
    // Org to add group
    // group safe address
    // Parent: Registered org or group
    // Admin: Registered org
    // Group name
    function addGroup(
        address _org,
        address _group,
        address _parent,
        address _admin,
        string memory _name
    ) public {
        if (orgs[_org].safe == address(0)) revert OrgNotRegistered();
        if (orgs[_parent].safe == address(0)) {
            // Check within groups
            if (groups[_org][_parent].safe == address(0))
                revert ParentNotRegistered();
        }
        if (orgs[_admin].safe == address(0)) revert AdminNotRegistered();
        // check msg.sender is the admin of the _org
        if (msg.sender != _org) revert NotAuthorized();
        Group storage group = groups[_org][_group];
        group.name = _name;
        group.admin = _admin;
        group.parent = _parent;
        group.safe = _group;
        // Update child on parent
        // TODO add logic to handle childs for orgs
        Group storage parentGroup = groups[_org][_parent];
        parentGroup.childs[_group] = true;
        // Is parent an org? => need to update the org mapping info too
        if (_org == _parent) {
            Group storage org = orgs[_org];
            org.childs[_group] = true;
        }
    }

    // returns
    // name Group
    // admin @
    // safe @
    // parent @
    function getGroupInfo(address _org, address _group)
        public
        view
        returns (
            string memory,
            address,
            address,
            address
        )
    {
        address groupSafe = groups[_org][_group].safe;
        if (groupSafe == address(0)) revert OrgNotRegistered();

        return (
            groups[_org][_group].name,
            groups[_org][_group].admin,
            groups[_org][_group].safe,
            groups[_org][_group].parent
        );
    }

    // Check if _child address is part of the group
    function isChild(
        address _org,
        address _parent,
        address _child
    ) public view returns (bool) {
        if (orgs[_org].safe == address(0)) revert OrgNotRegistered();
        // Check within orgs first if parent is org
        if (_org == _parent) {
            Group storage org = orgs[_org];
            return org.childs[_child];
        }
        // Check within groups of the org
        if (groups[_org][_parent].safe == address(0))
            revert ParentNotRegistered();
        Group storage group = groups[_org][_parent];
        return group.childs[_child];
    }

    // Check if an org is admin of the group
    function isAdmin(address org, address safe) public view returns (bool) {
        if (orgs[org].safe == address(0)) revert OrgNotRegistered();
        // Check group admin
        Group storage group = groups[org][safe];
        if (group.admin == org) {
            return true;
        }
        return false;
    }

    // TODO remove org param
    function execTransactionOnBehalf(
        address org,
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        bytes memory signatures
    ) external payable returns (bool success) {
        // Check org is admin of safe
        // TODO improve this check
        if (!isAdmin(org, safe)) revert NotAuthorizedExecOnBehalf();
        bytes32 txHash;
        // Use scope here to limit variable lifetime and prevent `stack too deep` errors
        {
            bytes memory keyperTxHashData = encodeTransactionData(
                // Keyper Info
                org,
                safe,
                // Transaction info
                to,
                value,
                data,
                operation,
                // Signature info
                nonce
            );
            // Increase nonce and execute transaction.
            nonce++;
            txHash = keccak256(keyperTxHashData);
            checkNSignatures(txHash, keyperTxHashData, signatures, org);
            // Execute transaction from safe
            GnosisSafe gnosisSafe = GnosisSafe(safe);
            bool result = gnosisSafe.execTransactionFromModule(
                to,
                value,
                data,
                operation
            );
            return result;
        }
    }

    function domainSeparator() public view returns (bytes32) {
        return
            keccak256(
                abi.encode(DOMAIN_SEPARATOR_TYPEHASH, getChainId(), this)
            );
    }

    /// @dev Returns the chain id used by this contract.
    function getChainId() public view returns (uint256) {
        uint256 id;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }

    /**
     * @dev Checks whether the signature provided is valid for the provided data, hash. Will revert otherwise.
     * @param dataHash Hash of the data (could be either a message hash or transaction hash)
     * @param data That should be signed (this is passed to an external validator contract)
     * @param signatures Signature data that should be verified. Can be ECDSA signature, contract signature (EIP-1271) or approved hash.
     * @param org Org address
     */
    function checkNSignatures(
        bytes32 dataHash,
        bytes memory data,
        bytes memory signatures,
        address org
    ) public view {
        GnosisSafe gnosisSafe = GnosisSafe(org);
        uint256 requiredSignatures = gnosisSafe.getThreshold();
        // Check that the provided signature data is not too short
        require(signatures.length >= requiredSignatures.mul(65), "GS020");
        // There cannot be an owner with address 0.
        address lastOwner = address(0);
        address currentOwner;
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 i;
        for (i = 0; i < requiredSignatures; i++) {
            (v, r, s) = signatureSplit(signatures, i);
            if (v == 0) {
                // If v is 0 then it is a contract signature
                // When handling contract signatures the address of the contract is encoded into r
                currentOwner = address(uint160(uint256(r)));

                // Check that signature data pointer (s) is not pointing inside the static part of the signatures bytes
                // This check is not completely accurate, since it is possible that more signatures than the threshold are send.
                // Here we only check that the pointer is not pointing inside the part that is being processed
                require(uint256(s) >= requiredSignatures.mul(65), "GS021");

                // Check that signature data pointer (s) is in bounds (points to the length of data -> 32 bytes)
                require(uint256(s).add(32) <= signatures.length, "GS022");

                // Check if the contract signature is in bounds: start of data is s + 32 and end is start + signature length
                uint256 contractSignatureLen;
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    contractSignatureLen := mload(add(add(signatures, s), 0x20))
                }
                require(
                    uint256(s).add(32).add(contractSignatureLen) <=
                        signatures.length,
                    "GS023"
                );

                // Check signature
                bytes memory contractSignature;
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    // The signature data for contract signatures is appended to the concatenated signatures and the offset is stored in s
                    contractSignature := add(add(signatures, s), 0x20)
                }
                require(
                    ISignatureValidator(currentOwner).isValidSignature(
                        data,
                        contractSignature
                    ) == EIP1271_MAGIC_VALUE,
                    "GS024"
                );
                // }
                // TODO: Identify this usecase
                // else if (v == 1) {
                //     // If v is 1 then it is an approved hash
                //     // When handling approved hashes the address of the approver is encoded into r
                //     currentOwner = address(uint160(uint256(r)));
                //     // Hashes are automatically approved by the sender of the message or when they have been pre-approved via a separate transaction
                //     require(msg.sender == currentOwner || approvedHashes[currentOwner][dataHash] != 0, "GS025");
                //
            } else if (v > 30) {
                // If v > 30 then default va (27,28) has been adjusted for eth_sign flow
                // To support eth_sign and similar we adjust v and hash the messageHash with the Ethereum message prefix before applying ecrecover
                currentOwner = ecrecover(
                    keccak256(
                        abi.encodePacked(
                            "\x19Ethereum Signed Message:\n32",
                            dataHash
                        )
                    ),
                    v - 4,
                    r,
                    s
                );
            } else {
                // Default is the ecrecover flow with the provided data hash
                // Use ecrecover with the messageHash for EOA signatures
                currentOwner = ecrecover(dataHash, v, r, s);
            }
            require(
                currentOwner > lastOwner && currentOwner != SENTINEL_OWNERS,
                "GS026"
            );
            // TODO change this logic, not optimized: Check current owner is part of the owners of the org safe
            require(isSafeOwner(gnosisSafe, currentOwner) != false, "GS026");
            lastOwner = currentOwner;
        }
    }

    function isSafeOwner(GnosisSafe gnosisSafe, address signer)
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
        return
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                domainSeparator(),
                keyperTxHash
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
        return
            keccak256(
                encodeTransactionData(
                    org,
                    safe,
                    to,
                    value,
                    data,
                    operation,
                    _nonce
                )
            );
    }
}
