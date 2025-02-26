Gas Optimization Summarize
===========================

## Average gas of all methods of PalmeraModule:

We run test with the below command
```
yarn test
```
- Before fix: `422,351`
- After  fix: `153,202`

Gas Optimization
===========================
## [Gas-01] Add missing break in the `getOrgBySafe` function of `PalmeraModule.sol`
```diff
function getOrgBySafe(uint256 safeId)
    ...
    for (uint256 i; i < orgHash.length;) {
        if (safes[orgHash[i]][safeId].safe != address(0)) {
            orgSafe = orgHash[i];
+           break;
        }
        unchecked {
            ++i;
        }
    }
    ...
```
## [Gas-02] Replace `for loop` with `mapping` index of `PalmeraModule.sol`

```diff
+ mapping(bytes32 => mapping(address => uint256)) public indexSafeBySafe;
    ...
    function getSafeIdBySafe(bytes32 org, address safe) 
    ...
-    for (uint256 i; i < indexSafe[org].length;) {
-        if (safes[org][indexSafe[org][i]].safe == safe) {
-            return indexSafe[org][i];
-        }
-        unchecked {
-            ++i;
-        }
-    }
+    if (indexSafe[org].length > 0 && indexSafeBySafe[org][safe] > 0)
+        return indexSafe[org][indexSafeBySafe[org][safe] - 1];
    ...
    // there are more diff. Please check the below Gif Diff link
```
...

Please check total [Git Diff](https://github.com/DanielWang8824/Palmera-hats/commit/1f848411c45c7aba4587d2195b510bc5ad3aac35)

Gas Optimization Report
===========================
# Total average gas cost with compare
```
yarn test
```
## 1. This is the gas report after apply my patch.
```
·····················································································································
|  Solidity and Network Configuration                                                                               │   
································|·················|···············|·················|································   
|  Solidity: 0.8.23             ·  Optim: true    ·  Runs: 200    ·  viaIR: true    ·     Block: 30,000,000 gas     │   
································|·················|···············|·················|································   
|  Network: POLYGON             ·  L1: 37 gwei                    ·                 ·        0.47 usd/matic         │   
································|·················|···············|·················|················|···············   
|  Contracts / Methods          ·  Min            ·  Max          ·  Avg            ·  # calls       ·  usd (avg)   │   
································|·················|···············|·················|················|···············   
|  CREATE3Factory               ·                                                                                   │   
································|·················|···············|·················|················|···············   
|   ◯  deploy                   ·              -  ·            -  ·      5,212,154  ·            32  ·     0.09064  │   
································|·················|···············|·················|················|···············   
|   ◯  getDeployed              ·        -20,918  ·      -20,906  ·        -20,916  ·            16  ·           △  │   
································|·················|···············|·················|················|···············   
|  PalmeraGuard                 ·                                                                                   │   
································|·················|···············|·················|················|···············   
|   ◯  VERSION                  ·        -20,349  ·      -15,512  ·        -15,798  ·          4464  ·           △  │   
································|·················|···············|·················|················|···············   
|  PalmeraModule                ·                                                                                   │   
································|·················|···············|·················|················|···············   
|   ◯  depthTreeLimit           ·        -18,236  ·      -17,852  ·        -18,226  ·            39  ·           △  │   
································|·················|···············|·················|················|···············   
|   ◯  execTransactionOnBehalf  ·        184,703  ·      212,791  ·        192,607  ·            16  ·     0.00335  │   
································|·················|···············|·················|················|···············   
|   ◯  getOrgHashBySafe         ·        -18,543  ·       68,094  ·          1,140  ·           217  ·     0.00002  │   
································|·················|···············|·················|················|···············   
|   ◯  getSafeIdBySafe          ·        -16,389  ·      -13,622  ·        -13,728  ·           267  ·           △  │   
································|·················|···············|·················|················|···············   
|   ◯  getTransactionHash       ·        -20,599  ·      -20,587  ·        -20,588  ·            16  ·           △  │   
································|·················|···············|·················|················|···············   
|   ◯  isOrgRegistered          ·              -  ·            -  ·        -18,618  ·            36  ·           △  │   
································|·················|···············|·················|················|···············   
|   ◯  isRootSafeOf             ·         11,613  ·       78,416  ·         30,615  ·            38  ·     0.00053  │   
|  DataTypes                    ·              -  ·            -  ·         66,028  ·         0.2 %  ·     0.00115  │
································|·················|···············|·················|················|···············
|  Errors                       ·              -  ·            -  ·         66,028  ·         0.2 %  ·     0.00115  │
································|·················|···············|·················|················|···············
|  Events                       ·              -  ·            -  ·         66,028  ·         0.2 %  ·     0.00115  │
································|·················|···············|·················|················|···············
|  PalmeraGuard                 ·              -  ·            -  ·        426,048  ·         1.4 %  ·     0.00741  │
································|·················|···············|·················|················|···············
|  PalmeraRoles                 ·              -  ·            -  ·      1,120,037  ·         3.7 %  ·     0.01948  │
································|·················|···············|·················|················|···············
|  Key                                                                                                              │
·····················································································································
|  ◯  Execution gas for this method does not include intrinsic gas overhead                                         │
·····················································································································
|  △  Cost was non-zero but below the precision setting for the currency display (see options)                      │
·····················································································································
|  Toolchain:  hardhat                                                                                              │
·····················································································································
```

## 2. This is the gas report with original source code.
```
·····················································································································
|  Solidity and Network Configuration                                                                               │
································|·················|···············|·················|································
|  Solidity: 0.8.23             ·  Optim: true    ·  Runs: 200    ·  viaIR: true    ·     Block: 30,000,000 gas     │
································|·················|···············|·················|································
|  Network: POLYGON             ·  L1: 37 gwei                    ·                 ·        0.47 usd/matic         │
································|·················|···············|·················|················|···············
|  Contracts / Methods          ·  Min            ·  Max          ·  Avg            ·  # calls       ·  usd (avg)   │
································|·················|···············|·················|················|···············
|  CREATE3Factory               ·                                                                                   │
································|·················|···············|·················|················|···············
|   ◯  deploy                   ·              -  ·            -  ·      5,125,265  ·            32  ·     0.08913  │
································|·················|···············|·················|················|···············
|   ◯  getDeployed              ·        -20,918  ·      -20,906  ·        -20,916  ·            16  ·           △  │
································|·················|···············|·················|················|···············
|  PalmeraGuard                 ·                                                                                   │
································|·················|···············|·················|················|···············
|   ◯  VERSION                  ·        -20,349  ·      -15,512  ·        -15,788  ·          4628  ·           △  │
································|·················|···············|·················|················|···············
|  PalmeraModule                ·                                                                                   │
································|·················|···············|·················|················|···············
|   ◯  depthTreeLimit           ·              -  ·            -  ·        -18,258  ·            48  ·           △  │
································|·················|···············|·················|················|···············
|   ◯  execTransactionOnBehalf  ·        205,086  ·      286,938  ·        231,877  ·            12  ·     0.00403  │
································|·················|···············|·················|················|···············
|   ◯  getOrgHashBySafe         ·         -8,702  ·      257,004  ·         54,749  ·           237  ·     0.00095  │
································|·················|···············|·················|················|···············
|   ◯  getSafeIdBySafe          ·        -13,508  ·       66,264  ·         11,916  ·           287  ·     0.00021  │
································|·················|···············|·················|················|···············
|   ◯  getTransactionHash       ·        -20,621  ·      -20,597  ·        -20,607  ·            34  ·           △  │
································|·················|···············|·················|················|···············
|   ◯  isOrgRegistered          ·              -  ·            -  ·        -18,640  ·            46  ·           △  │
································|·················|···············|·················|················|···············
|   ◯  isRootSafeOf             ·          9,865  ·       88,853  ·         33,495  ·            47  ·     0.00058  │
································|·················|···············|·················|················|···············
|   ◯  isSafeLead               ·          1,136  ·        3,330  ·          2,891  ·            20  ·     0.00005  │
································|·················|···············|·················|················|···············
|   ◯  isSafeRegistered         ·         60,811  ·       60,823  ·         60,813  ·             8  ·     0.00106  │
································|·················|···············|·················|················|···············
|   ◯  isTreeMember             ·        -20,266  ·      264,108  ·         84,115  ·           183  ·     0.00146  │
································|·················|···············|·················|················|···············
|  ◯  Execution gas for this method does not include intrinsic gas overhead                                         │
·····················································································································
|  △  Cost was non-zero but below the precision setting for the currency display (see options)                      │
·····················································································································
|  Toolchain:  hardhat                                                                                              │
·····················································································································
```

Simple Gas Optimization Test
===========================

I added simple gas optimazation test `gas-avg-main.test.ts` and we could run with the below command.

```
yarn test gas-avg
```
## Average gas of all methods of PalmeraModule:
- Before fix: `+29,900`
- After  fix: `-24,837`

The below is the compare result.

## 1. This is the gas report after apply my patch.
```
················································································································
|  Solidity and Network Configuration                                                                          │
···························|·················|···············|·················|································
|  Solidity: 0.8.23        ·  Optim: true    ·  Runs: 200    ·  viaIR: true    ·     Block: 30,000,000 gas     │
···························|·················|···············|·················|································
|  Network: POLYGON        ·  L1: 30 gwei                    ·                 ·        0.48 usd/matic         │
···························|·················|···············|·················|················|···············
|  Contracts / Methods     ·  Min            ·  Max          ·  Avg            ·  # calls       ·  usd (avg)   │
···························|·················|···············|·················|················|···············
|  CREATE3Factory          ·                                                                                   │
···························|·················|···············|·················|················|···············
|   ◯  deploy              ·              -  ·            -  ·      5,212,154  ·             4  ·     0.07506  │
···························|·················|···············|·················|················|···············
|   ◯  getDeployed         ·        -20,918  ·      -20,906  ·        -20,912  ·             2  ·           △  │
···························|·················|···············|·················|················|···············
|  PalmeraGuard            ·                                                                                   │
···························|·················|···············|·················|················|···············
|   ◯  VERSION             ·        -20,349  ·      -15,512  ·        -15,804  ·           630  ·           △  │
···························|·················|···············|·················|················|···············
|  PalmeraModule           ·                                                                                   │
···························|·················|···············|·················|················|···············
|   ◯  depthTreeLimit      ·        -18,236  ·      -18,224  ·        -18,233  ·             4  ·           △  │
···························|·················|···············|·················|················|···············
|   ◯  getOrgHashBySafe    ·         -8,840  ·       12,142  ·         -2,481  ·            33  ·           △  │
···························|·················|···············|·················|················|···············
|   ◯  getSafeIdBySafe     ·        -13,646  ·      -13,634  ·        -13,643  ·            33  ·           △  │
···························|·················|···············|·················|················|···············
|   ◯  getTransactionHash  ·              -  ·            -  ·        -20,587  ·             1  ·           △  │
···························|·················|···············|·················|················|···············
|   ◯  isOrgRegistered     ·        -18,618  ·      -18,606  ·        -18,616  ·             5  ·           △  │
···························|·················|···············|·················|················|···············
|   ◯  isRootSafeOf        ·         11,613  ·       29,832  ·         18,901  ·             5  ·     0.00027  │
···························|·················|···············|·················|················|···············
|   ◯  isTreeMember        ·         20,496  ·       91,346  ·         48,300  ·            28  ·     0.00070  │
···························|·················|···············|·················|················|···············
|   ◯  nonce               ·              -  ·            -  ·        -18,478  ·             1  ·           △  │
···························|·················|···············|·················|················|···············
|  Deployments                               ·                                 ·  % of limit    ·              │
···························|·················|···············|·················|················|···············
|  Constants               ·              -  ·            -  ·         66,028  ·         0.2 %  ·     0.00095  │
···························|·················|···············|·················|················|···············
|  DataTypes               ·              -  ·            -  ·         66,028  ·         0.2 %  ·     0.00095  │
···························|·················|···············|·················|················|···············
|  Errors                  ·              -  ·            -  ·         66,028  ·         0.2 %  ·     0.00095  │
···························|·················|···············|·················|················|···············
|  Events                  ·              -  ·            -  ·         66,028  ·         0.2 %  ·     0.00095  │
···························|·················|···············|·················|················|···············
|  PalmeraGuard            ·        426,024  ·      426,036  ·        426,030  ·         1.4 %  ·     0.00613  │
···························|·················|···············|·················|················|···············
|  PalmeraRoles            ·      1,120,025  ·    1,120,037  ·      1,120,031  ·         3.7 %  ·     0.01613  │
···························|·················|···············|·················|················|···············
|  Key                                                                                                         │
················································································································
|  ◯  Execution gas for this method does not include intrinsic gas overhead                                    │
················································································································
|  △  Cost was non-zero but below the precision setting for the currency display (see options)                 │
················································································································
|  Toolchain:  hardhat                                                                                         │
················································································································
```



## 2. This is the gas report with original source code.
```
················································································································
|  Solidity and Network Configuration                                                                          │
···························|·················|···············|·················|································
|  Solidity: 0.8.23        ·  Optim: true    ·  Runs: 200    ·  viaIR: true    ·     Block: 30,000,000 gas     │
···························|·················|···············|·················|································
|  Network: POLYGON        ·  L1: 30 gwei                    ·                 ·        0.48 usd/matic         │
···························|·················|···············|·················|················|···············
|  Contracts / Methods     ·  Min            ·  Max          ·  Avg            ·  # calls       ·  usd (avg)   │
···························|·················|···············|·················|················|···············
|  CREATE3Factory          ·                                                                                   │
···························|·················|···············|·················|················|···············
|   ◯  deploy              ·              -  ·            -  ·      5,125,265  ·             4  ·     0.07380  │
···························|·················|···············|·················|················|···············
|   ◯  getDeployed         ·              -  ·            -  ·        -20,918  ·             2  ·           △  │
···························|·················|···············|·················|················|···············
|  PalmeraGuard            ·                                                                                   │
···························|·················|···············|·················|················|···············
|   ◯  VERSION             ·        -20,349  ·      -15,512  ·        -15,804  ·           630  ·           △  │
···························|·················|···············|·················|················|···············
|  PalmeraModule           ·                                                                                   │
···························|·················|···············|·················|················|···············
|   ◯  depthTreeLimit      ·        -18,258  ·      -18,246  ·        -18,255  ·             4  ·           △  │
···························|·················|···············|·················|················|···············
|   ◯  getOrgHashBySafe    ·         -8,702  ·      100,164  ·         36,071  ·            33  ·     0.00052  │
···························|·················|···············|·················|················|···············
|   ◯  getSafeIdBySafe     ·        -13,508  ·       46,312  ·          4,320  ·            33  ·     0.00006  │
···························|·················|···············|·················|················|···············
|   ◯  getTransactionHash  ·              -  ·            -  ·        -20,609  ·             1  ·           △  │
···························|·················|···············|·················|················|···············
|   ◯  isOrgRegistered     ·        -18,640  ·      -18,628  ·        -18,638  ·             5  ·           △  │
···························|·················|···············|·················|················|···············
|   ◯  isRootSafeOf        ·          9,865  ·       28,093  ·         17,156  ·             5  ·     0.00025  │
···························|·················|···············|·················|················|···············
|   ◯  isTreeMember        ·         20,550  ·       91,406  ·         48,355  ·            28  ·     0.00070  │
···························|·················|···············|·················|················|···············
|   ◯  nonce               ·              -  ·            -  ·        -18,500  ·             1  ·           △  │
···························|·················|···············|·················|················|···············
|  Deployments                               ·                                 ·  % of limit    ·              │
···························|·················|···············|·················|················|···············
|  Constants               ·              -  ·            -  ·         66,028  ·         0.2 %  ·     0.00095  │
···························|·················|···············|·················|················|···············
|  DataTypes               ·              -  ·            -  ·         66,016  ·         0.2 %  ·     0.00095  │
···························|·················|···············|·················|················|···············
|  Errors                  ·              -  ·            -  ·         66,028  ·         0.2 %  ·     0.00095  │
···························|·················|···············|·················|················|···············
|  Events                  ·              -  ·            -  ·         66,028  ·         0.2 %  ·     0.00095  │
···························|·················|···············|·················|················|···············
|  PalmeraGuard            ·              -  ·            -  ·        426,048  ·         1.4 %  ·     0.00614  │
···························|·················|···············|·················|················|···············
|  PalmeraRoles            ·              -  ·            -  ·      1,120,037  ·         3.7 %  ·     0.01613  │
···························|·················|···············|·················|················|···············
|  Key                                                                                                         │
················································································································
|  ◯  Execution gas for this method does not include intrinsic gas overhead                                    │
················································································································
|  △  Cost was non-zero but below the precision setting for the currency display (see options)                 │
················································································································
|  Toolchain:  hardhat                                                                                         │
················································································································
```