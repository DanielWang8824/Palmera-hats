/* eslint-disable no-unused-vars */
/* eslint-disable camelcase */
import { ethers, network } from "hardhat";
import { AbiCoder, TransactionResponse } from "ethers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import dotenv from "dotenv";
import chai from "chai";
import {
    PalmeraModule,
    PalmeraModule__factory,
    PalmeraRoles,
    PalmeraRoles__factory,
    PalmeraGuard,
    PalmeraGuard__factory,
    Errors,
    Errors__factory,
    Events,
    Events__factory,
    Random,
    Random__factory,
    CREATE3Factory,
    CREATE3Factory__factory,
} from "../../typechain-types";
import Safe, {
    Eip1193Provider,
    SafeAccountConfig,
    SafeFactory,
} from "@safe-global/protocol-kit";
import { MetaTransactionData, SafeTransaction } from "@safe-global/safe-core-sdk-types";
import { SafeVersion } from "permissionless/_types/accounts";

dotenv.config();

const { expect } = chai;

// General Vars
let deployer: SignerWithAddress;
let accounts: SignerWithAddress[];
const safes: Safe[] = [];
let salt: string;
let orgName: string;

// Contracts Vars
let CREATE3Factory: CREATE3Factory;
let PalmeraModuleContract: PalmeraModule;
let PalmeraRoles: PalmeraRoles;
let PalmeraGuard: PalmeraGuard;

// Get Constants
const maxDepthTreeLimit = 50;

const snooze = (ms: any) => new Promise((resolve) => setTimeout(resolve, ms));

describe("Basic Deployment of Palmera Environment", function () {
    /** Deploy All Environment and Several Safe Account for Different Use Cases */
    /** 1. Deploy All Libreries */
    const deployLibraries = async (deployer: SignerWithAddress) => {
        // Deploy Constants Library
        const ConstantsFactory = (await ethers.getContractFactory(
            "Constants",
            deployer,
        ));
        const ConstantsLibrary = await ConstantsFactory.deploy();
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await ConstantsLibrary.getAddress()).to.properAddress;
        console.log(
            `Constants Library deployed at: ${await ConstantsLibrary.getAddress()}`,
        );
        // Deploy DataTypes Library
        const DataTypesFactory = (await ethers.getContractFactory(
            "DataTypes",
            deployer,
        ));
        const DataTypesLibrary = await DataTypesFactory.deploy();
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await DataTypesLibrary.getAddress()).to.properAddress;
        console.log(
            `DataTypes Library deployed at: ${await DataTypesLibrary.getAddress()}`,
        );
        // Deploy Errors Library
        const ErrorsFactory = (await ethers.getContractFactory(
            "Errors",
            deployer,
        )) as Errors__factory;
        const ErrorsLibrary = await ErrorsFactory.deploy();
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await ErrorsLibrary.getAddress()).to.properAddress;
        console.log(
            `Errors Library deployed at: ${await ErrorsLibrary.getAddress()}`,
        );
        // Deploy Events Library
        const EventsFactory = (await ethers.getContractFactory(
            "Events",
            deployer,
        )) as unknown as Events__factory;
        const EventsLibrary = await EventsFactory.deploy();
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await EventsLibrary.getAddress()).to.properAddress;
        console.log(
            `Events Library deployed at: ${await EventsLibrary.getAddress()}`,
        );
    };
    /** 2. Deploy Palmera Environment */
    const deployPalmeraEnvironment = async (salt: string, deployer: SignerWithAddress) => {
        // Create a Instance of CREATE# Factory for Predict Address Deployments, from the address https://polygonscan.com/address/0x93fec2c00bfe902f733b57c5a6ceed7cd1384ae1#code
        // create this instance from the address deployed "0x93fec2c00bfe902f733b57c5a6ceed7cd1384ae1"
        CREATE3Factory = (await ethers.getContractAt(
            "CREATE3Factory",
            "0x93fec2c00bfe902f733b57c5a6ceed7cd1384ae1",
            deployer,
        )) as unknown as CREATE3Factory;
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await CREATE3Factory.getAddress()).to.properAddress;
        console.log(
            `CREATE3Factory deployed at: ${await CREATE3Factory.getAddress()}`,
        );
        const PalmeraModuleAddress = await CREATE3Factory.getDeployed(
            await deployer.getAddress(),
            salt,
        );
        console.log(`Palmera Module Address Predicted: ${PalmeraModuleAddress}`);
        // Deploy Palmera Roles
        const PalmeraRolesFactory = await ethers.getContractFactory(
            "PalmeraRoles",
            deployer,
        );
        // Deploy Palmera Roles, with the address of the Palmera Module like unique argument
        PalmeraRoles = (await PalmeraRolesFactory.deploy(PalmeraModuleAddress)) as unknown as PalmeraRoles;
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await PalmeraRoles.getAddress()).to.properAddress;
        console.log(
            `Palmera Roles deployed at: ${await PalmeraRoles.getAddress()}`,
        );
        // Deploy Palmera Module with CREATE3Factory
        // create args for deploy Palmera Module, with the address of Palmera Roles and maxDepthTreeLimit
        const newAbiCoder = new AbiCoder();
        const args: string = newAbiCoder.encode(
            ["address", "uint256"],
            [await PalmeraRoles.getAddress(), maxDepthTreeLimit],
        );
        // Get creation Code of Palmera Module, from Contract Code of Palmera Module in src folder
        const bytecode: string = ethers.solidityPacked(
            ["bytes", "bytes"],
            [PalmeraModule__factory.bytecode, args],
        );
        // Deploy Palmera Module with CREATE3Factory
        const PalmeraModuleDeployed: TransactionResponse = await CREATE3Factory.deploy(
            salt,
            bytecode,
        );
        // wait for the transaction to be mined
        const receipt = await PalmeraModuleDeployed.wait(1);
        // get the address of the Palmera Module deployed
        const PalmeraModuleAddressDeployed: string = receipt?.logs[0].address!!;
        console.log(`Palmera Module Deployed at: ${PalmeraModuleAddressDeployed}`);
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(PalmeraModuleAddressDeployed).to.equal(PalmeraModuleAddress);
        // Create a Instance of Palmera Module
        PalmeraModuleContract = (await ethers.getContractAt(
            "PalmeraModule",
            PalmeraModuleAddressDeployed,
            deployer,
        )) as unknown as PalmeraModule;
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await PalmeraModuleContract.getAddress()).to.properAddress;
        // Deploy Palmera Guard
        const PalmeraGuardFactory = (await ethers.getContractFactory(
            "PalmeraGuard",
            deployer,
        )) as unknown as PalmeraGuard__factory;
        PalmeraGuard = await PalmeraGuardFactory.deploy(
            PalmeraModuleAddressDeployed,
        );
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        expect(await PalmeraGuard.getAddress()).to.properAddress;
        console.log(
            `Palmera Guard deployed at: ${await PalmeraGuard.getAddress()}`,
        );
    };
    /** 3. Inicializate Safe Factory, Deploy X Safe Accounts and Setup Palmera Module and Palmera Guard */
    const deploySafeFactory = async (salt: string, PalmeraModuleAddressDeployed: string, amountsSafes: number, safeVersion: SafeVersion | undefined = "1.4.1", accounts: SignerWithAddress[]) => {
        for (let i = 0, j = 0; j < amountsSafes; ++j, i += 3) {
            const safeFactory = await SafeFactory.init({
                provider: network.provider,
                signer: await accounts[i].getAddress(),
                safeVersion,
            });
            const safeAccCfg: SafeAccountConfig = {
                owners: [
                    await accounts[i].getAddress(),
                    await accounts[i + 1].getAddress(),
                    await accounts[i + 2].getAddress(),
                ],
                threshold: 1,
            };
            const saltNonce = salt;
            safes[j] = await safeFactory.deploySafe({
                safeAccountConfig: safeAccCfg,
                saltNonce,
            });
            console.log(
                `Safe Account ${i / 3 + 1} deployed at: ${await safes[j].getAddress()}`,
            );
            // Enable Palmera Module and Guard in Safe Account
            const tx1 = await safes[j].createEnableModuleTx(
                PalmeraModuleAddressDeployed,
            );
            const tx2 = await safes[j].executeTransaction(tx1);
            // @ts-ignore
            await tx2.transactionResponse?.wait();
            // Verify if the Module is enabled in Safe Account
            const enabledModule = await safes[j].getModules();
            expect(enabledModule[0]).to.include(PalmeraModuleAddressDeployed);
            // Enable Palmera Guard in Safe Account
            const tx3 = await safes[j].createEnableGuardTx(
                await PalmeraGuard.getAddress(),
            );
            const tx4 = await safes[j].executeTransaction(tx3);
            // @ts-ignore
            await tx4.transactionResponse?.wait();
            // Verify if the Guard is enabled in Safe Account
            const enabledGuard = await safes[j].getGuard();
            expect(enabledGuard).to.equal(await PalmeraGuard.getAddress());
        }
        console.log(
            "All Safe Accounts Deployed and Enabled with Palmera Module and Guard",
        );
    }
    /** 4. Deploy Org Lineal Tree in Palmera Module */
    const deployLinealTreeOrg = async (safes: Safe[], orgName: string): Promise<any> => {
        // Register a Basic Org in Palmera Module
        const tx: MetaTransactionData[] = [
            {
                to: await PalmeraModuleContract.getAddress(),
                value: "0x0",
                data: PalmeraModuleContract.interface.encodeFunctionData(
                    "registerOrg",
                    [orgName],
                ),
            },
        ];
        const safeTx = await safes[0].createTransaction({ transactions: tx });
        const txResponse = await safes[0].executeTransaction(safeTx);
        // @ts-ignore
        await txResponse.transactionResponse?.wait();
        // Get the Org Hash, and Verify if the Safe Account is the Root of the Org, with the Org Name
        const orgHash = await PalmeraModuleContract.getOrgHashBySafe(
            await safes[0].getAddress(),
        );
        console.log(`Org Hash: ${orgHash}`);
        // Validate the Org Hash, is the Keccak256 Hash of the Org Name
        expect(orgHash).to.equal(
            ethers.solidityPackedKeccak256(["string"], [orgName]),
        );
        // Validate the Org Hash, is an Organization Registered in Palmera Module
        expect(await PalmeraModuleContract.isOrgRegistered(orgHash)).to.equal(true);
        // Get the Root Id of the Org, and Verify if the Safe Account is the Root of the Org
        const rootId: number = parseInt((await PalmeraModuleContract.getSafeIdBySafe(
            orgHash,
            await safes[0].getAddress(),
        )).toString());
        // Validate the Safe Account is the Root of the Org
        expect(
            await PalmeraModuleContract.isRootSafeOf(
                await safes[0].getAddress(),
                rootId,
            ),
        ).to.equal(true);
        console.log(`Root Safe Account Id: ${rootId}`);
        // Add Safe Accounts to the Org
        for (let i = 1; i < safes.length; ++i) {
            const tx2: MetaTransactionData[] = [
                {
                    to: await PalmeraModuleContract.getAddress(),
                    value: "0x0",
                    data: PalmeraModuleContract.interface.encodeFunctionData("addSafe", [
                        rootId,
                        `Safe ${i}`,
                    ]),
                },
            ];
            const safeTx2 = await safes[i].createTransaction({
                transactions: tx2,
            });
            const txResponse2 = await safes[i].executeTransaction(safeTx2);
            // @ts-ignore
            await txResponse2.transactionResponse?.wait();
            // Get the Safe Id, and Verify if the Safe Account is added to the Org
            const safeId: number = parseInt((await PalmeraModuleContract.getSafeIdBySafe(
                orgHash,
                await safes[i].getAddress(),
            )).toString());
            // Validate the Safe Account is added to the Org
            expect(await PalmeraModuleContract.isTreeMember(rootId, safeId)).to.equal(
                true,
            );
            // Get Org Hash by Safe Account
            const orgHashBySafe = await PalmeraModuleContract.getOrgHashBySafe(
                await safes[i].getAddress(),
            );
            // Validate the Org Hash by Root Safe Account is the same as the Org Hash by Safe Account
            expect(orgHash).to.equal(orgHashBySafe);
            console.log(`Safe Account Id associate to Org: ${safeId}`);
        }
        console.log("All Safe Accounts Added to the Lineal Tree Org");
        return orgHash;
    };
    /** 5. Deploy Org 1-to-3 Tree in Palmera Module */
    const deploy1to3TreeOrg = async (safes: Safe[], orgName: string): Promise<any> => {
        if (safes.length % 3 !== 1) {
            throw new Error("The number of Safe Accounts must be 3n + 1");
        }
        if (safes.length < 4) {
            throw new Error("The number of Safe Accounts must be greater than 3");
        }
        // Register a Basic Org in Palmera Module
        const tx: MetaTransactionData[] = [
            {
                to: await PalmeraModuleContract.getAddress(),
                value: "0x0",
                data: PalmeraModuleContract.interface.encodeFunctionData(
                    "registerOrg",
                    [orgName],
                ),
            },
        ];
        const safeTx = await safes[0].createTransaction({ transactions: tx });
        const txResponse = await safes[0].executeTransaction(safeTx);
        // @ts-ignore
        await txResponse.transactionResponse?.wait();
        // Get the Org Hash, and Verify if the Safe Account is the Root of the Org, with the Org Name
        const orgHash = await PalmeraModuleContract.getOrgHashBySafe(
            await safes[0].getAddress(),
        );
        console.log(`Org Hash: ${orgHash}`);
        // Validate the Org Hash, is the Keccak256 Hash of the Org Name
        expect(orgHash).to.equal(
            ethers.solidityPackedKeccak256(["string"], [orgName]),
        );
        // Validate the Org Hash, is an Organization Registered in Palmera Module
        expect(await PalmeraModuleContract.isOrgRegistered(orgHash)).to.equal(true);
        // Get the Root Id of the Org, and Verify if the Safe Account is the Root of the Org
        const rootId: number = parseInt((await PalmeraModuleContract.getSafeIdBySafe(
            orgHash,
            await safes[0].getAddress(),
        )).toString());
        // Validate the Safe Account is the Root of the Org
        expect(
            await PalmeraModuleContract.isRootSafeOf(
                await safes[0].getAddress(),
                rootId,
            ),
        ).to.equal(true);
        console.log(`Root Safe Account Id: ${rootId}`);
        // Add Safe Accounts to the Org
        for (let i = 1; i < 4; ++i) {
            const tx2: MetaTransactionData[] = [
                {
                    to: await PalmeraModuleContract.getAddress(),
                    value: "0x0",
                    data: PalmeraModuleContract.interface.encodeFunctionData("addSafe", [
                        rootId,
                        `Safe ${i}`,
                    ]),
                },
            ];
            const safeTx2 = await safes[i].createTransaction({
                transactions: tx2,
            });
            const txResponse2 = await safes[i].executeTransaction(safeTx2);
            // @ts-ignore
            await txResponse2.transactionResponse?.wait();
            // Get the Safe Id, and Verify if the Safe Account is added to the Org
            const safeId: number = parseInt((await PalmeraModuleContract.getSafeIdBySafe(
                orgHash,
                await safes[i].getAddress(),
            )).toString());
            // Validate the Safe Account is added to the Org
            expect(await PalmeraModuleContract.isTreeMember(rootId, safeId)).to.equal(
                true,
            );
            // Get Org Hash by Safe Account
            const orgHashBySafe = await PalmeraModuleContract.getOrgHashBySafe(
                await safes[i].getAddress(),
            );
            // Validate the Org Hash by Root Safe Account is the same as the Org Hash by Safe Account
            expect(orgHash).to.equal(orgHashBySafe);
            console.log(`Safe Account Id associate to Org: ${safeId}`);
        }
        if (safes.length >= 7) {
            for (let i = 4; i < 7; ++i) {
                const tx2: MetaTransactionData[] = [
                    {
                        to: await PalmeraModuleContract.getAddress(),
                        value: "0x0",
                        data: PalmeraModuleContract.interface.encodeFunctionData("addSafe", [
                            2,
                            `Safe ${i}`,
                        ]),
                    },
                ];
                const safeTx2 = await safes[i].createTransaction({
                    transactions: tx2,
                });
                const txResponse2 = await safes[i].executeTransaction(safeTx2);
                // @ts-ignore
                await txResponse2.transactionResponse?.wait();
                // Get the Safe Id, and Verify if the Safe Account is added to the Org
                const safeId: number = parseInt((await PalmeraModuleContract.getSafeIdBySafe(
                    orgHash,
                    await safes[i].getAddress(),
                )).toString());
                // Validate the Safe Account is added to the Org
                expect(await PalmeraModuleContract.isTreeMember(2, safeId)).to.equal(
                    true,
                );
                // Get Org Hash by Safe Account
                const orgHashBySafe = await PalmeraModuleContract.getOrgHashBySafe(
                    await safes[i].getAddress(),
                );
                // Validate the Org Hash by Root Safe Account is the same as the Org Hash by Safe Account
                expect(orgHash).to.equal(orgHashBySafe);
                console.log(`Safe Account Id associate to Org: ${safeId}`);
            }
        }
        if (safes.length >= 10) {
            for (let i = 7; i < 10; ++i) {
                const tx2: MetaTransactionData[] = [
                    {
                        to: await PalmeraModuleContract.getAddress(),
                        value: "0x0",
                        data: PalmeraModuleContract.interface.encodeFunctionData("addSafe", [
                            3,
                            `Safe ${i}`,
                        ]),
                    },
                ];
                const safeTx2 = await safes[i].createTransaction({
                    transactions: tx2,
                });
                const txResponse2 = await safes[i].executeTransaction(safeTx2);
                // @ts-ignore
                await txResponse2.transactionResponse?.wait();
                // Get the Safe Id, and Verify if the Safe Account is added to the Org
                const safeId: number = parseInt((await PalmeraModuleContract.getSafeIdBySafe(
                    orgHash,
                    await safes[i].getAddress(),
                )).toString());
                // Validate the Safe Account is added to the Org
                expect(await PalmeraModuleContract.isTreeMember(3, safeId)).to.equal(
                    true,
                );
                // Get Org Hash by Safe Account
                const orgHashBySafe = await PalmeraModuleContract.getOrgHashBySafe(
                    await safes[i].getAddress(),
                );
                // Validate the Org Hash by Root Safe Account is the same as the Org Hash by Safe Account
                expect(orgHash).to.equal(orgHashBySafe);
                console.log(`Safe Account Id associate to Org: ${safeId}`);
            }
        }
        if (safes.length >= 13) {
            for (let i = 10; i < 13; ++i) {
                const tx2: MetaTransactionData[] = [
                    {
                        to: await PalmeraModuleContract.getAddress(),
                        value: "0x0",
                        data: PalmeraModuleContract.interface.encodeFunctionData("addSafe", [
                            4,
                            `Safe ${i}`,
                        ]),
                    },
                ];
                const safeTx2 = await safes[i].createTransaction({
                    transactions: tx2,
                });
                const txResponse2 = await safes[i].executeTransaction(safeTx2);
                // @ts-ignore
                await txResponse2.transactionResponse?.wait();
                // Get the Safe Id, and Verify if the Safe Account is added to the Org
                const safeId: number = parseInt((await PalmeraModuleContract.getSafeIdBySafe(
                    orgHash,
                    await safes[i].getAddress(),
                )).toString());
                // Validate the Safe Account is added to the Org
                expect(await PalmeraModuleContract.isTreeMember(4, safeId)).to.equal(
                    true,
                );
                // Get Org Hash by Safe Account
                const orgHashBySafe = await PalmeraModuleContract.getOrgHashBySafe(
                    await safes[i].getAddress(),
                );
                // Validate the Org Hash by Root Safe Account is the same as the Org Hash by Safe Account
                expect(orgHash).to.equal(orgHashBySafe);
                console.log(`Safe Account Id associate to Org: ${safeId}`);
            }
        }
        console.log("All Safe Accounts Added to the Org 1-to-3 Tree");
        return orgHash;
    };
    // Inicializate Safe Factory, Deploy X Safe Accounts and Setup Palmera Module and Palmera Guard
    beforeEach(async () => {
        // Get Signers
        accounts = await ethers.getSigners();
        deployer = accounts[0];
        // call getDeployed function from CREATE3Factory to get the address of the Palmera Module
        salt = ethers.keccak256(
            ethers.toUtf8Bytes(`0x${Math.random() % 1000}`),
        );
        // Deploy Libraries
        await deployLibraries(deployer);
        // Deploy Palmera Environment
        await deployPalmeraEnvironment(salt, deployer);
    });

    /** Create a Basic Org with a Linear Structura and After Test ExecuteOnBehalf of Root Safe over last Child Safe */
    /** 1. Create a Basic Org in Palmera Module */
    /** 2. Add Safe Accounts to the Org */
    /** 3. ExecuteOnBehalf of Root Safe over last Child Safe, and the Caller is Another Account EOA */
    it("Create a Basic Lineal Org in Palmera Module, and Test ExecuteOnBehalf with EOA", async () => {
        // Get Safe Accounts with Palmera Module and Guard Enabled
        await deploySafeFactory(salt, await PalmeraModuleContract.getAddress(), 4, "1.4.1", accounts);
        // slice the Safe Accounts to get the firsth four Safe Accounts
        const safesSlice = safes.slice(0, 4);
        // verify the length of the slice
        expect(safesSlice.length).to.equal(4);
        // Register a Basic Org in Palmera Module
        orgName = "Basic Lineal Org";
        // Get the Org Hash, and Verify if the Safe Account is the Root of the Org, with the Org Name
        const orgHash = await deployLinealTreeOrg(safesSlice, orgName);
        // Get last Account
        const lastAccount = accounts[accounts.length - 1];
        // Get last Safe Account
        const lastSafe = safesSlice[safesSlice.length - 1];
        // Transfer 0.1 ETH  from last account to last Safe Account
        await lastAccount.sendTransaction({
            to: await lastSafe.getAddress(),
            value: ethers.parseEther("0.153"),
        });
        // Verify the Balance of the Safe Account
        const balance = await lastAccount.provider.getBalance(
            await lastSafe.getAddress(),
        );
        expect(balance).to.equal(ethers.parseEther("0.153"));
        console.log(
            `Balance of Last Safe Account Before ExecuteOnBehalf: ${balance}`,
        );
        // Get Nonce of Palmera Module
        const nonce: number = parseInt((await PalmeraModuleContract.nonce(orgHash)).toString());
        console.log(`Nonce: ${nonce}`);
        // Get getTransactionHash of Palmera Module
        const txHash: string = await PalmeraModuleContract.getTransactionHash(
            orgHash,
            await safesSlice[0].getAddress(),
            await lastSafe.getAddress(),
            await lastAccount.getAddress(),
            ethers.parseEther("0.153"),
            "0x",
            0,
            nonce,
        );
        console.log(`Transaction Hash: ${txHash}`);
        // get Signature of the Transaction Hash signed by the Root Safe Account
        const signature = await safesSlice[0].signHash(txHash);
        console.log(`Signature: ${signature.data}`);
        // Get Balance of Last Account before Execute Transaction OnBehalf
        const balance1 = await lastAccount.provider.getBalance(
            await lastAccount.getAddress(),
        );
        console.log(
            `Balance of Last Account Before Execute Transaction OnBehalf: ${balance1}`,
        );
        // Execute Transaction OnBehalf of Root Safe Account over last Safe Account
        // Get another Account
        const anotherAccount = accounts[accounts.length - 2];
        // send tx from Another Account to pay gas for Execute Transaction OnBehalf of Root Safe Account over last Safe Account
        const safeTx3 = await anotherAccount.sendTransaction({
            to: await PalmeraModuleContract.getAddress(),
            value: "0x0",
            data: PalmeraModuleContract.interface.encodeFunctionData(
                "execTransactionOnBehalf",
                [
                    orgHash,
                    await safesSlice[0].getAddress(),
                    await lastSafe.getAddress(),
                    await lastAccount.getAddress(),
                    ethers.parseEther("0.153"),
                    "0x",
                    0,
                    signature.data,
                ],
            ),
        });
        // wait for the transaction to be mined
        const receipt = await lastAccount.provider.getTransactionReceipt(
            safeTx3.hash,
        );
        // Verify the Transaction was executed
        expect(receipt).to.not.equal(null);
        // Verify the Transaction was successful
        expect(receipt?.status).to.equal(1);
        // Verify the Balance of the Safe Account
        const balance2 = await lastAccount.provider.getBalance(
            await lastSafe.getAddress(),
        );
        expect(balance2).to.equal(0);
        console.log(
            `Balance of Last Safe Account After Execute Transaction OnBehalf: ${balance2}`,
        );
        // Get Balance of ETH of Last Account after Execute Transaction OnBehalf
        const balance3 = await lastAccount.provider.getBalance(
            await lastAccount.getAddress(),
        );
        // Verify the Balance of the Last Account
        console.log(
            `Balance of Last Account After Execute Transaction OnBehalf: ${balance3}`,
        );
        expect(balance3).to.equal(balance1 + ethers.parseEther("0.153"));
    });

    /** Create a Basic Org with a Linear Structura and After Test ExecuteOnBehalf of Root Safe over last Child Safe */
    /** 1. Create a Basic Org in Palmera Module */
    /** 2. Add Safe Accounts to the Org */
    /** 3. ExecuteOnBehalf of Root Safe over last Child Safe, and the Caller is Another Safe Account */
    it("Create a Basic Lineal Org in Palmera Module, and Test ExecuteOnBehalf with Another Safe", async () => {
        // Get Safe Accounts with Palmera Module and Guard Enabled
        await deploySafeFactory(salt, await PalmeraModuleContract.getAddress(), 3, "1.4.1", accounts);
        // Slice to small org
        const safesSlice = safes.slice(0, 3);
        // Verify the length of the slice
        expect(safesSlice.length).to.equal(3);
        // Register a Basic Org in Palmera Module
        orgName = "Basic Lineal Org";
        // Get the Org Hash, and Verify if the Safe Account is the Root of the Org, with the Org Name
        const orgHash = await deployLinealTreeOrg(safesSlice, orgName);
        // Get last Account
        const lastAccount = accounts[accounts.length - 1];
        // Get last Safe Account
        const lastSafe = safesSlice[safesSlice.length - 1];
        // Transfer 0.1 ETH  from last account to last Safe Account
        await lastAccount.sendTransaction({
            to: await lastSafe.getAddress(),
            value: ethers.parseEther("0.153"),
        });
        // Verify the Balance of the Safe Account
        const balance = await lastAccount.provider.getBalance(
            await lastSafe.getAddress(),
        );
        expect(balance).to.equal(ethers.parseEther("0.153"));
        console.log(
            `Balance of Last Safe Account Before ExecuteOnBehalf: ${balance}`,
        );
        // Get Nonce of Palmera Module
        const nonce: number = parseInt((await PalmeraModuleContract.nonce(orgHash)).toString());
        console.log(`Nonce: ${nonce}`);
        // Get getTransactionHash of Palmera Module
        const txHash: string = await PalmeraModuleContract.getTransactionHash(
            orgHash,
            await safesSlice[0].getAddress(),
            await lastSafe.getAddress(),
            await lastAccount.getAddress(),
            ethers.parseEther("0.153"),
            "0x",
            0,
            nonce,
        );
        console.log(`Transaction Hash: ${txHash}`);
        // get Signature of the Transaction Hash signed by the Root Safe Account
        const signature = await safesSlice[0].signHash(txHash);
        console.log(`Signature: ${signature.data}`);
        // Get Balance of Last Account before Execute Transaction OnBehalf
        const balance1 = await lastAccount.provider.getBalance(
            await lastAccount.getAddress(),
        );
        console.log(
            `Balance of Last Account Before Execute Transaction OnBehalf: ${balance1}`,
        );
        // Execute Transaction OnBehalf of Root Safe Account over last Safe Account
        // Get another Safe Account
        const anotherSafeAccount = safesSlice[safesSlice.length - 2];
        // send tx from Another Account to pay gas for Execute Transaction OnBehalf of Root Safe Account over last Safe Account
        const safeTx3 = await anotherSafeAccount.createTransaction({
            transactions: [
                {
                    to: await PalmeraModuleContract.getAddress(),
                    value: "0x0",
                    data: PalmeraModuleContract.interface.encodeFunctionData(
                        "execTransactionOnBehalf",
                        [
                            orgHash,
                            await safesSlice[0].getAddress(),
                            await lastSafe.getAddress(),
                            await lastAccount.getAddress(),
                            ethers.parseEther("0.153"),
                            "0x",
                            0,
                            signature.data,
                        ],
                    ),
                },
            ],
        });
        // execute safe transaction
        const txResponse3 = await anotherSafeAccount.executeTransaction(safeTx3);
        // wait for the transaction to be mined
        // @ts-ignore
        await txResponse3.transactionResponse?.wait();
        // Verify the Balance of the Safe Account
        const balance2 = await lastAccount.provider.getBalance(
            await lastSafe.getAddress(),
        );
        expect(balance2).to.equal(0);
        console.log(
            `Balance of Last Safe Account After Execute Transaction OnBehalf: ${balance2}`,
        );
        // Get Balance of ETH of Last Account after Execute Transaction OnBehalf
        const balance3 = await lastAccount.provider.getBalance(
            await lastAccount.getAddress(),
        );
        // Verify the Balance of the Last Account
        console.log(
            `Balance of Last Account After Execute Transaction OnBehalf: ${balance3}`,
        );
        expect(balance3).to.equal(balance1 + ethers.parseEther("0.153"));
    });

    /** Create a Basic Org with a 1-to-3 Structura and After Test ExecuteOnBehalf of Root Safe over last Child Safe */
    /** 1. Create a Basic Org in Palmera Module */
    /** 2. Add Safe Accounts to the Org */
    /** 3. ExecuteOnBehalf of Root Safe over last Child Safe, and the Caller is Another Account EOA */
    it("Create a Basic 1-to-3 Org in Palmera Module, and Test ExecuteOnBehalf with EOA", async () => {
        // Get Safe Accounts with Palmera Module and Guard Enabled
        await deploySafeFactory(salt, await PalmeraModuleContract.getAddress(), 4, "1.4.1", accounts);
        // slice the Safe Accounts to get the firsth four Safe Accounts
        const safesSlice = safes.slice(0, 4);
        // verify the length of the slice
        expect(safesSlice.length).to.equal(4);
        // Register a Basic Org in Palmera Module
        orgName = "Basic 1-to-3 Org";
        // Get the Org Hash, and Verify if the Safe Account is the Root of the Org, with the Org Name
        const orgHash = await deploy1to3TreeOrg(safesSlice, orgName);
        // Get last Account
        const lastAccount = accounts[accounts.length - 1];
        // Get last Safe Account
        const lastSafe = safesSlice[safesSlice.length - 1];
        // Transfer 0.1 ETH  from last account to last Safe Account
        await lastAccount.sendTransaction({
            to: await lastSafe.getAddress(),
            value: ethers.parseEther("0.153"),
        });
        // Verify the Balance of the Safe Account
        const balance = await lastAccount.provider.getBalance(
            await lastSafe.getAddress(),
        );
        expect(balance).to.equal(ethers.parseEther("0.153"));
        console.log(
            `Balance of Last Safe Account Before ExecuteOnBehalf: ${balance}`,
        );
        // Get Nonce of Palmera Module
        const nonce: number = parseInt((await PalmeraModuleContract.nonce(orgHash)).toString());
        console.log(`Nonce: ${nonce}`);
        // Get getTransactionHash of Palmera Module
        const txHash: string = await PalmeraModuleContract.getTransactionHash(
            orgHash,
            await safesSlice[0].getAddress(),
            await lastSafe.getAddress(),
            await lastAccount.getAddress(),
            ethers.parseEther("0.153"),
            "0x",
            0,
            nonce,
        );
        console.log(`Transaction Hash: ${txHash}`);
        // get Signature of the Transaction Hash signed by the Root Safe Account
        const signature = await safesSlice[0].signHash(txHash);
        console.log(`Signature: ${signature.data}`);
        // Get Balance of Last Account before Execute Transaction OnBehalf
        const balance1 = await lastAccount.provider.getBalance(
            await lastAccount.getAddress(),
        );
        console.log(
            `Balance of Last Account Before Execute Transaction OnBehalf: ${balance1}`,
        );
        // Execute Transaction OnBehalf of Root Safe Account over last Safe Account
        // Get another Account
        const anotherAccount = accounts[accounts.length - 2];
        // send tx from Another Account to pay gas for Execute Transaction OnBehalf of Root Safe Account over last Safe Account
        const safeTx3 = await anotherAccount.sendTransaction({
            to: await PalmeraModuleContract.getAddress(),
            value: "0x0",
            data: PalmeraModuleContract.interface.encodeFunctionData(
                "execTransactionOnBehalf",
                [
                    orgHash,
                    await safesSlice[0].getAddress(),
                    await lastSafe.getAddress(),
                    await lastAccount.getAddress(),
                    ethers.parseEther("0.153"),
                    "0x",
                    0,
                    signature.data,
                ],
            ),
        });
        // wait for the transaction to be mined
        const receipt = await lastAccount.provider.getTransactionReceipt(
            safeTx3.hash,
        );
        // Verify the Transaction was executed
        expect(receipt).to.not.equal(null);
        // Verify the Transaction was successful
        expect(receipt?.status).to.equal(1);
        // Verify the Balance of the Safe Account
        const balance2 = await lastAccount.provider.getBalance(
            await lastSafe.getAddress(),
        );
        expect(balance2).to.equal(0);
        console.log(
            `Balance of Last Safe Account After Execute Transaction OnBehalf: ${balance2}`,
        );
        // Get Balance of ETH of Last Account after Execute Transaction OnBehalf
        const balance3 = await lastAccount.provider.getBalance(
            await lastAccount.getAddress(),
        );
        // Verify the Balance of the Last Account
        console.log(
            `Balance of Last Account After Execute Transaction OnBehalf: ${balance3}`,
        );
        expect(balance3).to.equal(balance1 + ethers.parseEther("0.153"));
    });

    /** Create a Basic Org with a 1-to-3 Structura and After Test ExecuteOnBehalf of Root Safe over last Child Safe */
    /** 1. Create a Basic Org in Palmera Module */
    /** 2. Add Safe Accounts to the Org */
    /** 3. ExecuteOnBehalf of Root Safe over last Child Safe, and the Caller is Another Safe Account */
    it("Create a Basic 1-to-3 Org in Palmera Module, and Test ExecuteOnBehalf with Another Safe", async () => {
        // Get Safe Accounts with Palmera Module and Guard Enabled
        await deploySafeFactory(salt, await PalmeraModuleContract.getAddress(), 13, "1.4.1", accounts);
        // Slice to small org
        const safesSlice = safes.slice(0, 13);
        // Verify the length of the slice
        expect(safesSlice.length).to.equal(13);
        // Register a Basic Org in Palmera Module
        orgName = "Basic 1-to-3 Org";
        // Get the Org Hash, and Verify if the Safe Account is the Root of the Org, with the Org Name
        const orgHash = await deploy1to3TreeOrg(safesSlice, orgName);
        // Get last Account
        const lastAccount = accounts[accounts.length - 1];
        // Get last Safe Account
        const lastSafe = safesSlice[safesSlice.length - 1];
        // Transfer 0.1 ETH  from last account to last Safe Account
        await lastAccount.sendTransaction({
            to: await lastSafe.getAddress(),
            value: ethers.parseEther("0.153"),
        });
        // Verify the Balance of the Safe Account
        const balance = await lastAccount.provider.getBalance(
            await lastSafe.getAddress(),
        );
        expect(balance).to.equal(ethers.parseEther("0.153"));
        console.log(
            `Balance of Last Safe Account Before ExecuteOnBehalf: ${balance}`,
        );
        // Get Nonce of Palmera Module
        const nonce: number = parseInt((await PalmeraModuleContract.nonce(orgHash)).toString());
        console.log(`Nonce: ${nonce}`);
        // Get getTransactionHash of Palmera Module
        const txHash: string = await PalmeraModuleContract.getTransactionHash(
            orgHash,
            await safesSlice[0].getAddress(),
            await lastSafe.getAddress(),
            await lastAccount.getAddress(),
            ethers.parseEther("0.153"),
            "0x",
            0,
            nonce,
        );
        console.log(`Transaction Hash: ${txHash}`);
        // get Signature of the Transaction Hash signed by the Root Safe Account
        const signature = await safesSlice[0].signHash(txHash);
        console.log(`Signature: ${signature.data}`);
        // Get Balance of Last Account before Execute Transaction OnBehalf
        const balance1 = await lastAccount.provider.getBalance(
            await lastAccount.getAddress(),
        );
        console.log(
            `Balance of Last Account Before Execute Transaction OnBehalf: ${balance1}`,
        );
        // Execute Transaction OnBehalf of Root Safe Account over last Safe Account
        // Get another Safe Account
        const anotherSafeAccount = safesSlice[safesSlice.length - 2];
        // send tx from Another Account to pay gas for Execute Transaction OnBehalf of Root Safe Account over last Safe Account
        const safeTx3 = await anotherSafeAccount.createTransaction({
            transactions: [
                {
                    to: await PalmeraModuleContract.getAddress(),
                    value: "0x0",
                    data: PalmeraModuleContract.interface.encodeFunctionData(
                        "execTransactionOnBehalf",
                        [
                            orgHash,
                            await safesSlice[0].getAddress(),
                            await lastSafe.getAddress(),
                            await lastAccount.getAddress(),
                            ethers.parseEther("0.153"),
                            "0x",
                            0,
                            signature.data,
                        ],
                    ),
                },
            ],
        });
        // execute safe transaction
        const txResponse3 = await anotherSafeAccount.executeTransaction(safeTx3);
        // wait for the transaction to be mined
        // @ts-ignore
        await txResponse3.transactionResponse?.wait();
        // Verify the Balance of the Safe Account
        const balance2 = await lastAccount.provider.getBalance(
            await lastSafe.getAddress(),
        );
        expect(balance2).to.equal(0);
        console.log(
            `Balance of Last Safe Account After Execute Transaction OnBehalf: ${balance2}`,
        );
        // Get Balance of ETH of Last Account after Execute Transaction OnBehalf
        const balance3 = await lastAccount.provider.getBalance(
            await lastAccount.getAddress(),
        );
        // Verify the Balance of the Last Account
        console.log(
            `Balance of Last Account After Execute Transaction OnBehalf: ${balance3}`,
        );
        expect(balance3).to.equal(balance1 + ethers.parseEther("0.153"));
    });
});
