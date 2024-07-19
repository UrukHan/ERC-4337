# Ditto Network Smart Contracts

![Stability](https://img.shields.io/badge/stability-indev-red)

<img src="https://i.imgur.com/g846Eq5.png" alt="Ditto" width="600">

## Table of Contents

- [Ditto Network Smart Contracts](#ditto-network-smart-contracts)
  - [Table of Contents](#table-of-contents)
  - [Getting started](#getting-started)
  - [Deployment](#deployment)
  - [Adding new modules](#adding-new-modules)
  - [Project structure](#project-structure)
  - [License](#license)

## Getting started

First, download repository:

```bash
git clone https://github.com/dittonetwork/ditto-audit
cd ditto-audit
```

Install dependencies:

```bash
forge install
```

Copy the .env.example to .env and fill it in:
```bash
cp .env.example .env
```

```bash
ETH_RPC_URL=
POL_RPC_URL=
ARB_RPC_URL=
OPT_RPC_URL=

POLYGON_API_KEY=
ARB_API_KEY=
BNB_API_KEY=
AVAX_API_KEY=
CELO_API_KEY=

PRIVATE_KEY=0x
```

Run tests
```bash
forge test
```

## Deployment

Env variables must be added to the terminal before deployment
```bash
source .env
``` 

Contract addresses stored in the [Registry](/script/Registry.sol)

For each network there is a file with a script to deploy to dev or prod (dev deploy is partially involved in creating the test environment)

to run the deploy script on dev
```bash
forge script script/FullDeploy.s.sol -vvvv --rpc-url $<network>_RPC_URL --sig "run(bool,bool)" true false --broadcast [--with-gas-price <gas price>]
```

Where:
  1. network - the network to which the script will be run
  2. true - add new implementation to the factory
  3. false - deploy contracts for dev
  4. gas price - optional parameter for gas price (e.g., gas price on arb is 0.1 gwei, but foundry takes 3.2 gwei)

Note:
  1. All contracts that do not equal a `address(0)` in the `Registry` file will not be re-deployed while script execution.
  2. Contracts deployed on the Ditto protocol must be cleared in order to deploy your own env 
    and the factory address must be modified in the `deployFactory` method to your own:
   - vaultFactoryProxyAdmin
   - vaultFactoryProxy
   - vaultProxyAdmin
   - dittoBridgeReceiver
   - protocolFees
   - entryPointLogic
   - executionLogic
   - stargateLogic
   - layerZeroLogic

## Adding new modules

After writing a new module, you need to add it to the `logics` structure in the `Registry` file and add it to the network script where it is needed: 
  1. its methods to the private function `_getData`
  2. its deployment to the public function `deploySystemContracts`` similar to the contracts already existing there

## Project structure

1. `script` - the logic of deployment, test environment creation and the registry of contracts
2. `src` - code of contracts
3. `test` - tests for contracts

---
## License

You can copy and paste the MIT license summary from below.

```
MIT License

Copyright (c) 2023 Ditto Network

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```
