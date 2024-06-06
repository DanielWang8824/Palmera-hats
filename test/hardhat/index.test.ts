/* eslint-disable no-unused-vars */
/* eslint-disable camelcase */
import { ethers, run, network } from "hardhat";
import { AbiCoder, TransactionResponse} from "ethers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
    setBalance,
    impersonateAccount,
} from "@nomicfoundation/hardhat-network-helpers";
import dotenv from "dotenv";
import chai from "chai";
import {
    Palmera_Module,
    Palmera_Module__factory,
    Palmera_Roles,
    Palmera_Roles__factory,
    Palmera_Guard,
    Palmera_Guard__factory,
    Constants,
    Constants__factory,
    DataTypes,
    DataTypes__factory,
    Errors,
    Errors__factory,
    Events,
    Events__factory,
    Random,
    Random__factory,
    CREATE3Factory,
    CREATE3Factory__factory,
} from "../typechain-types";
import Safe, { Eip1193Provider, SafeAccountConfig, SafeFactory } from '@safe-global/protocol-kit'
import { PalmeraModule__factory } from "../../typechain-types";
import { MetaTransactionData } from "@safe-global/safe-core-sdk-types";

dotenv.config();

const { expect } = chai;

// General Vars
let deployer: SignerWithAddress;
let accounts: SignerWithAddress[];
const safes: Safe[] = [];

// Contracts Vars
let CREATE3Factory: CREATE3Factory;
let PalmeraModuleContract: Palmera_Module;
let PalmeraRoles: Palmera_Roles;
let PalmeraGuard: Palmera_Guard;

// Get Constants
const maxDepthTreeLimit = 50;
const orgName = "Basic Org";

const snooze = (ms: any) => new Promise((resolve) => setTimeout(resolve, ms));

describe("Basic Deployment of Palmera Environment", function () {
    beforeEach(async () => {
        // Get Signers
        accounts = await ethers.getSigners();
        deployer = accounts[0];
        // Deploy Constants Library
        const ConstantsFactory = (await ethers.getContractFactory("Constants", deployer)) as Constants__factory;
        const ConstantsLibrary = await ConstantsFactory.deploy();
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await ConstantsLibrary.getAddress()).to.properAddress;
        console.log(`Constants Library deployed at: ${await ConstantsLibrary.getAddress()}`);
        // Deploy DataTypes Library
        const DataTypesFactory = (await ethers.getContractFactory("DataTypes", deployer)) as DataTypes__factory;
        const DataTypesLibrary = await DataTypesFactory.deploy();
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await DataTypesLibrary.getAddress()).to.properAddress;
        console.log(`DataTypes Library deployed at: ${await DataTypesLibrary.getAddress()}`);
        // Deploy Errors Library
        const ErrorsFactory = (await ethers.getContractFactory("Errors", deployer)) as Errors__factory;
        const ErrorsLibrary = await ErrorsFactory.deploy();
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await ErrorsLibrary.getAddress()).to.properAddress;
        console.log(`Errors Library deployed at: ${await ErrorsLibrary.getAddress()}`);
        // Deploy Events Library
        const EventsFactory = (await ethers.getContractFactory("Events", deployer)) as Events__factory;
        const EventsLibrary = await EventsFactory.deploy();
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await EventsLibrary.getAddress()).to.properAddress;
        console.log(`Events Library deployed at: ${await EventsLibrary.getAddress()}`);
        // Deploy Random Library
        const RandomFactory = (await ethers.getContractFactory("Random", deployer)) as Random__factory;
        const RandomLibrary = await RandomFactory.deploy();
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await RandomLibrary.getAddress()).to.properAddress;
        console.log(`Random Library deployed at: ${await RandomLibrary.getAddress()}`);
        // Create a Instance of CREATE# Factory for Predict Address Deployments, from the address https://polygonscan.com/address/0x93fec2c00bfe902f733b57c5a6ceed7cd1384ae1#code
        // create this instance from the address deployed "0x93fec2c00bfe902f733b57c5a6ceed7cd1384ae1"
        CREATE3Factory = await ethers.getContractAt("CREATE3Factory", "0x93fec2c00bfe902f733b57c5a6ceed7cd1384ae1", deployer);
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await CREATE3Factory.getAddress()).to.properAddress;
        console.log(`CREATE3Factory deployed at: ${await CREATE3Factory.getAddress()}`);
        // call getDeployed function from CREATE3Factory to get the address of the Palmera Module
        const salt: string = ethers.keccak256(ethers.toUtf8Bytes("0xfff"));
        const PalmeraModuleAddress = await CREATE3Factory.getDeployed(await deployer.getAddress(), salt);
        console.log(`Palmera Module Address Predicted: ${PalmeraModuleAddress}`);
        // Deploy Palmera Roles
        const PalmeraRolesFactory = (await ethers.getContractFactory("PalmeraRoles", deployer)) as Palmera_Roles__factory;
        // Deploy Palmera Roles, with the address of the Palmera Module like unique argument
        PalmeraRoles = await PalmeraRolesFactory.deploy(PalmeraModuleAddress);
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await PalmeraRoles.getAddress()).to.properAddress;
        console.log(`Palmera Roles deployed at: ${await PalmeraRoles.getAddress()}`);
        // Deploy Palmera Module with CREATE3Factory
        // create args for deploy Palmera Module, with the address of Palmera Roles and maxDepthTreeLimit
        const newAbiCoder = new AbiCoder();
        const args: string = newAbiCoder.encode(["address", "uint256"], [await PalmeraRoles.getAddress(), maxDepthTreeLimit]);
        // Get creation Code of Palmera Module, from Contract Code of Palmera Module in src folder
        const bytecode: string = ethers.solidityPacked(["bytes", "bytes"], [PalmeraModule__factory.bytecode, args]);
        // Deploy Palmera Module with CREATE3Factory
        const PalmeraModuleDeployed: TransactionResponse = await CREATE3Factory.deploy(salt, bytecode);
        // wait for the transaction to be mined
        const receipt = await PalmeraModuleDeployed.wait(1);
        // get the address of the Palmera Module deployed
        const PalmeraModuleAddressDeployed: string = receipt?.logs[0].address!!;
        console.log(`Palmera Module Deployed at: ${PalmeraModuleAddressDeployed}`);
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(PalmeraModuleAddressDeployed).to.equal(PalmeraModuleAddress);
        // Create a Instance of Palmera Module
        PalmeraModuleContract = (await ethers.getContractAt("PalmeraModule", PalmeraModuleAddressDeployed, deployer)) as Palmera_Module;
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await PalmeraModuleContract.getAddress()).to.properAddress;
        // Deploy Palmera Guard
        const PalmeraGuardFactory = (await ethers.getContractFactory("PalmeraGuard", deployer)) as Palmera_Guard__factory;
        PalmeraGuard = await PalmeraGuardFactory.deploy(PalmeraModuleAddressDeployed);
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await PalmeraGuard.getAddress()).to.properAddress;
        console.log(`Palmera Guard deployed at: ${await PalmeraGuard.getAddress()}`);
        // Deploy Safe Factory
        const safeVersion = "1.4.1";
        // Deploy 9 Safe Accounts
        for (let i = 0 ,j = 0; j < 9; ++j , i += 3) {
            const safeFactory = await SafeFactory.init({
                provider: network.provider,
                signer: await accounts[i].getAddress(),
                safeVersion,
            })
            const safeAccCfg: SafeAccountConfig = {
                owners: [await accounts[i].getAddress(), await accounts[i+1].getAddress(), await accounts[i+2].getAddress()],
                threshold: 1,
            }
            const saltNonce = "0xaaa";
            safes[j] = await safeFactory.deploySafe({ safeAccountConfig: safeAccCfg, saltNonce });
            console.log(`Safe Account ${(i / 3) + 1} deployed at: ${ await safes[j].getAddress()}`);
            // Enable Palmera Module and Guard in Safe Account
            const tx1 = await safes[j].createEnableModuleTx(PalmeraModuleAddressDeployed);
            const tx2 = await safes[j].executeTransaction(tx1);
            await tx2.transactionResponse?.wait();
            // Verify if the Module is enabled in Safe Account
            const enabledModule = await safes[j].getModules();
            expect(enabledModule[0]).to.include(PalmeraModuleAddressDeployed);
            // Enable Palmera Guard in Safe Account
            const tx3 = await safes[j].createEnableGuardTx(await PalmeraGuard.getAddress());
            const tx4 = await safes[j].executeTransaction(tx3);
            await tx4.transactionResponse?.wait();
            // Verify if the Guard is enabled in Safe Account
            const enabledGuard = await safes[j].getGuard();
            expect(enabledGuard).to.equal(await PalmeraGuard.getAddress());
        }
        console.log("All Safe Accounts Deployed and Enabled with Palmera Module and Guard");
    });

    it("Create a Basic Org in Palmera Module", async () => {
        // Register a Basic Org in Palmera Module
        const tx: MetaTransactionData[] = [{
            to: await PalmeraModuleContract.getAddress(),
            value: "0x0",
            data: PalmeraModuleContract.interface.encodeFunctionData("registerOrg", [orgName])
        }]
        const safeTx = await safes[0].createTransaction({ transactions: tx });
        const txResponse = await safes[0].executeTransaction(safeTx);
        await txResponse.transactionResponse?.wait();
        // Get the Org Hash, and Verify if the Safe Account is the Root of the Org, with the Org Name
        const orgHash = await PalmeraModuleContract.getOrgHashBySafe(await safes[0].getAddress());
        console.log(`Org Hash: ${orgHash}`);
        // Validate the Org Hash, is the Keccak256 Hash of the Org Name
        expect(orgHash).to.equal(ethers.solidityPackedKeccak256(["string"], [orgName]));
        // Validate the Org Hash, is an Organization Registered in Palmera Module
        expect(await PalmeraModuleContract.isOrgRegistered(orgHash)).to.equal(true);
        // Get the Root Id of the Org, and Verify if the Safe Account is the Root of the Org
        const rootId: number = await PalmeraModuleContract.getSafeIdBySafe(orgHash, await safes[0].getAddress());
        // Validate the Root Id, is 1 because is the first Safe Account Registered in Palmera Module
        expect(rootId).to.equal(1);
        // Validate the Safe Account is the Root of the Org
        expect(await PalmeraModuleContract.isRootSafeOf(await safes[0].getAddress(), rootId)).to.equal(true);
        console.log(`Root Safe Account Id: ${rootId}`);
        // Add Safe Accounts to the Org
        for (let i = 1; i < 9; ++i) {
            const tx2: MetaTransactionData[] = [{
                to: await PalmeraModuleContract.getAddress(),
                value: "0x0",
                data: PalmeraModuleContract.interface.encodeFunctionData("addSafe", [rootId, `Safe ${i}`])
            }]
            const safeTx2 = await safes[i].createTransaction({ transactions: tx2 });
            const txResponse2 = await safes[i].executeTransaction(safeTx2);
            await txResponse2.transactionResponse?.wait();
            // Get the Safe Id, and Verify if the Safe Account is added to the Org
            const safeId: number = await PalmeraModuleContract.getSafeIdBySafe(orgHash, await safes[i].getAddress());
            // Validate the Safe Id, is the Safe Account Number in the Org
            expect(safeId).to.equal(i + 1);
            // Validate the Safe Account is added to the Org
            expect(await PalmeraModuleContract.isTreeMember(rootId, safeId)).to.equal(true);
            // Get Org Hash by Root Safe Account
            const orgHashbyRootSafe = await PalmeraModuleContract.getOrgHashBySafe(await safes[0].getAddress());
            // Get Org Hash by Safe Account
            const orgHashBySafe = await PalmeraModuleContract.getOrgHashBySafe(await safes[i].getAddress());
            // Validate the Org Hash by Root Safe Account is the same as the Org Hash by Safe Account
            expect(orgHashbyRootSafe).to.equal(orgHashBySafe);
            console.log(`Safe Account Id associate to Org: ${safeId}`);
        }
    });

});
