// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ProxyAdmin, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {IDittoOracleV3} from "../src/vault/interfaces/IDittoOracleV3.sol";
import {DittoBridgeReceiver} from "../src/DittoBridgeReceiver.sol";
import {ProtocolFees} from "../src/ProtocolFees.sol";

import {IAutomate} from "@gelato/contracts/integrations/Types.sol";
import {IPoolAddressesProvider} from "@aave/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {VaultProxyAdmin} from "../src/VaultProxyAdmin.sol";
import {UpgradeLogic} from "../src/vault/UpgradeLogic.sol";
import {IWETH9} from "../src/vault/interfaces/external/IWETH9.sol";
import {IV3SwapRouter} from "../src/vault/interfaces/external/IV3SwapRouter.sol";
import {AaveLogicLens} from "../src/lens/AaveLogicLens.sol";
import {DexLogicLens} from "../src/lens/DexLogicLens.sol";

library Registry {
    struct Contracts {
        ProxyAdmin vaultFactoryProxyAdmin;
        address vaultFactoryImplementation;
        address vaultFactoryImplementationProd;
        ITransparentUpgradeableProxy vaultFactoryProxy;
        ITransparentUpgradeableProxy vaultFactoryProxyProd;
        VaultProxyAdmin vaultProxyAdmin;
        VaultProxyAdmin vaultProxyAdminProd;
        IDittoOracleV3 dittoOracle;
        DittoBridgeReceiver dittoBridgeReceiver;
        DittoBridgeReceiver dittoBridgeReceiverProd;
        ProtocolFees protocolFees;
        ProtocolFees protocolFeesProd;
        address protocolModuleList;
        address protocolModuleListProd;
        IWETH9 wrappedNative;
        IV3SwapRouter uniswapRouter;
        IUniswapV3Factory uniswapFactory;
        INonfungiblePositionManager uniswapNFTPositionManager;
        IV3SwapRouter pancakeswapRouter;
        IUniswapV3Factory pancakeswapFactory;
        INonfungiblePositionManager pancakeswapNFTPositionManager;
        IPoolAddressesProvider aaveAddressesProvider;
        IAutomate automateGelato;
        address stargateRouter;
        address layerZeroEndpoint;
        address celerCircleBridgeProxy;
        address usdc;
        address entryPoint;
        address entryPointCreator;
        Logics logics;
        Lens lens;
        Modules modules;
        PartnerFeesContracts partnerFeesContracts;
    }

    struct Logics {
        address vaultUpgradeLogic;
        address accountAbstractionLogic;
        address versionUpgradeLogic;
        address versionUpgradeLogicProd;
        address accessControlLogic;
        address entryPointLogic;
        address entryPointLogicProd;
        address executionLogic;
        address executionLogicProd;
        address vaultLogic;
        address nativeWrapper;
        address uniswapLogic;
        address pancakeswapLogic;
        address timeCheckerLogic;
        address priceCheckerLogicUniswap;
        address priceDifferenceCheckerLogicUniswap;
        address priceCheckerLogicPancakeswap;
        address priceDifferenceCheckerLogicPancakeswap;
        address deltaNeutralStrategyLogic;
        address aaveCheckerLogic;
        address aaveActionLogic;
        address stargateLogic;
        address stargateLogicProd;
        address layerZeroLogic;
        address layerZeroLogicProd;
        address celerCircleBridgeLogic;
        address uniswapDexCheckerLogic;
        address pancakeswapDexCheckerLogic;
    }

    struct Lens {
        AaveLogicLens aaveLogicLens;
        DexLogicLens dexLogicLens;
    }

    struct Modules {
        address partnerFeeModule;
    }

    struct PartnerFeesContracts {
        address partnerFees;
    }

    error InvalidChainId();

    // Polygon
    function _137() internal pure returns (Contracts memory) {
        Lens memory lens;
        lens.dexLogicLens = DexLogicLens(
            0x0F75cEf935D8A4D30E6dC95A385d6bCCC657678E //
        );
        lens.aaveLogicLens = AaveLogicLens(
            0x953BAaBbC3b6034571417BF78508799E7B1Ebf3E //
        );

        Logics memory logics;
        logics.vaultUpgradeLogic = 0xB5047973F9922d04d7d69dC5A2DCd350A51A1833; //
        logics
            .accountAbstractionLogic = 0x9669F549D62258d8BECbA177a0e809740044fff7; //
        logics.versionUpgradeLogic = 0xbf78b516B37A06F39f551B29fb9975A8DF62aa21; //
        logics.accessControlLogic = 0xD4555acE57801b5Cd68806949C80B26E2fFae014; //
        logics.entryPointLogic = 0x94991eD3031770fF147a342dE3bdE29d122b1943; //
        logics.executionLogic = 0x2d6F7F8a95499065eadb143e876494CD98AAF397; //
        logics.vaultLogic = 0x77c2c3eA05BA3D1C049CE95b42BD9ddeC31494f0; //
        logics.nativeWrapper = 0xC389aabfF3b89C47834Ea53E5977df6A8F912Bf7; //
        logics.uniswapLogic = 0x5bc30537435BD36Fa07eea85e99B109Ce8884d9E; //
        logics.pancakeswapLogic = address(1); // not used
        logics.timeCheckerLogic = 0xd17d47ef7BF955F49F0AfFd7be3301544e8dBB9F; //
        logics
            .priceCheckerLogicUniswap = 0xB794829997d0735640a03eF991ff28cd1a4425EF; //
        logics
            .priceDifferenceCheckerLogicUniswap = 0x34Ce7277f3Aa85c2e0C47BC96f9FcC168aC2d215; //
        logics.priceCheckerLogicPancakeswap = address(1); // not used
        logics.priceDifferenceCheckerLogicPancakeswap = address(1); // not used
        logics
            .deltaNeutralStrategyLogic = 0xDFbb101eE8e958961e08B139Db3085f0E9Ac8ed6; //
        logics.aaveCheckerLogic = 0x40613D29b97B2fcb85F9a3EcdFFa3D5849aD91be; //
        logics.aaveActionLogic = 0x451C99400b932e6430C640F4533049860dE34334; //
        logics.stargateLogic = 0xA9dd5424Dd731943466474C358B711Bce4F7160D; //
        logics.layerZeroLogic = 0x6c07D39042b2480a512675fdcc10A20756ba2d7B; //
        logics
            .celerCircleBridgeLogic = 0x73D9eb84BaE00A3767C090DB6e7d0C39663e919F; //
        logics
            .uniswapDexCheckerLogic = 0x5A5b365c72D81B8CBFb69996C03eb0d4DBC4A386; //
        logics.pancakeswapDexCheckerLogic = address(1); // not used

        // Prod
        logics
            .versionUpgradeLogicProd = 0x6E61122e5D1201f7B73Cb60Af9dc8F3b6b2389A8; //
        logics.entryPointLogicProd = 0x497442BAD459c98182AB6242671f481C4feC2426; //
        logics.executionLogicProd = address(0); //
        logics.stargateLogicProd = 0xFEAAAC6C49206EF203AB417915effBB50Dc8C1f9; //
        logics.layerZeroLogicProd = 0xAA382401E12b52c8D19e77D94E5f83c8929513b0; //

        Modules memory modules;
        modules.partnerFeeModule = address(1); // not needed rn

        PartnerFeesContracts memory partnerFeesContracts;
        partnerFeesContracts.partnerFees = address(1); // not needed rn

        return
            Contracts({
                vaultFactoryProxyAdmin: ProxyAdmin(
                    0x2D75C403384C6Ce374ba8B27451eF0F4BcD77c2E //
                ),
                vaultFactoryImplementation: 0x7a5bEd09dF3A62218ebA3291e32AfEc110Bc5bEE,
                vaultFactoryImplementationProd: address(0),
                vaultFactoryProxy: ITransparentUpgradeableProxy(
                    0xF03C8CaB74b5721eB81210592C9B06f662e9951E //
                ),
                vaultFactoryProxyProd: ITransparentUpgradeableProxy(
                    0xaB5F025297E40bd5ECf340d1709008eFF230C6cA //
                ),
                vaultProxyAdmin: VaultProxyAdmin(
                    0x0F320AF6CC51b1a64aab6a9f75C505CB7d9791Cc //
                ),
                vaultProxyAdminProd: VaultProxyAdmin(
                    0x2eEa83b0347DbC80d66a26Ce0DcD5fB0438A7C3C //
                ),
                dittoOracle: IDittoOracleV3(
                    0xCeEED49D9e707CD8d3c657387d65C14E72c10e9F //
                ),
                dittoBridgeReceiver: DittoBridgeReceiver(
                    0xB8A56D5cA1FFAa883A1b17eF8604B6d53c9D5Ee7 //
                ),
                dittoBridgeReceiverProd: DittoBridgeReceiver(
                    0xA758A4F9850afbCD000125D53ef19D45a311d6F8 //
                ),
                protocolFees: ProtocolFees(
                    0xF77685eE181defDE68E273399bc37750927eFeD5 //
                ),
                protocolFeesProd: ProtocolFees(
                    0xC0bb9aBA8D3f9ee0E7E1B1fDa8a63705e9D80fF5 //
                ),
                protocolModuleList: 0xb686A36f8F755cb65623f2cA0A58deD18BB4e97B, //
                protocolModuleListProd: 0x2E34A6b1E395824B7A0a201E3B63cE6295904560, //
                wrappedNative: IWETH9(
                    0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
                ),
                uniswapRouter: IV3SwapRouter(
                    0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
                ),
                uniswapFactory: IUniswapV3Factory(
                    0x1F98431c8aD98523631AE4a59f267346ea31F984
                ),
                uniswapNFTPositionManager: INonfungiblePositionManager(
                    0xC36442b4a4522E871399CD717aBDD847Ab11FE88
                ),
                pancakeswapRouter: IV3SwapRouter(address(0)),
                pancakeswapFactory: IUniswapV3Factory(address(0)),
                pancakeswapNFTPositionManager: INonfungiblePositionManager(
                    address(0)
                ),
                aaveAddressesProvider: IPoolAddressesProvider(
                    0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb
                ),
                automateGelato: IAutomate(
                    0x2A6C106ae13B558BB9E2Ec64Bd2f1f7BEFF3A5E0
                ),
                stargateRouter: 0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9,
                layerZeroEndpoint: 0x3c2269811836af69497E5F486A85D7316753cf62,
                celerCircleBridgeProxy: 0xB876cc05c3C3C8ECBA65dAc4CF69CaF871F2e0DD,
                usdc: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359,
                entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789,
                entryPointCreator: 0x7fc98430eAEdbb6070B35B39D798725049088348,
                logics: logics,
                lens: lens,
                modules: modules,
                partnerFeesContracts: partnerFeesContracts
            });
    }

    // Mumbai
    function _80001() internal pure returns (Contracts memory reg) {
        Lens memory lens;

        lens.dexLogicLens = DexLogicLens(
            address(1) // not used
        );
        lens.aaveLogicLens = AaveLogicLens(
            address(1) // not used
        );

        Logics memory logics;

        logics.vaultUpgradeLogic = address(0); //
        logics.accountAbstractionLogic = address(0); //
        logics.versionUpgradeLogic = address(0); //
        logics.accessControlLogic = address(0); //
        logics.entryPointLogic = address(0); //
        logics.executionLogic = address(0); //
        logics.vaultLogic = address(0); //
        logics.nativeWrapper = address(0); //
        logics.uniswapLogic = address(0); //
        logics.pancakeswapLogic = address(1); // not used
        logics.timeCheckerLogic = address(0); //
        logics
            .priceCheckerLogicUniswap = address(0); //
        logics
            .priceDifferenceCheckerLogicUniswap = address(0); //
        logics.priceCheckerLogicPancakeswap = address(1); // not used
        logics.priceDifferenceCheckerLogicPancakeswap = address(1); // not used
        logics.deltaNeutralStrategyLogic = address(1); // not used
        logics.aaveCheckerLogic = address(1); // not used
        logics.aaveActionLogic = address(1); // not used
        logics.stargateLogic = address(1); // not used
        logics.layerZeroLogic = address(0); //
        logics.celerCircleBridgeLogic = address(1); // not used
        logics
            .uniswapDexCheckerLogic = address(0); //
        logics.pancakeswapDexCheckerLogic = address(1); // not used

        // Prod
        logics
            .versionUpgradeLogicProd = address(0); //
        logics.entryPointLogicProd = address(0); //
        logics.executionLogicProd = address(0); //
        logics.stargateLogicProd = address(1); // not used
        logics.layerZeroLogicProd = address(0); //

        Modules memory modules;
        modules.partnerFeeModule = address(1); // not needed rn

        PartnerFeesContracts memory partnerFeesContracts;
        partnerFeesContracts.partnerFees = address(1); // not needed rn

        return
            Contracts({
                vaultFactoryProxyAdmin: ProxyAdmin(
                    address(0) //
                ),
                vaultFactoryImplementation: address(0),
                vaultFactoryImplementationProd: address(0),
                vaultFactoryProxy: ITransparentUpgradeableProxy(
                    address(0) //
                ),
                vaultFactoryProxyProd: ITransparentUpgradeableProxy(
                    address(0) //
                ),
                vaultProxyAdmin: VaultProxyAdmin(
                    address(0) //
                ),
                vaultProxyAdminProd: VaultProxyAdmin(
                    address(0) //
                ),
                dittoOracle: IDittoOracleV3(
                    address(0) //
                ),
                dittoBridgeReceiver: DittoBridgeReceiver(
                    address(0) //
                ),
                dittoBridgeReceiverProd: DittoBridgeReceiver(
                    address(0) //
                ),
                protocolFees: ProtocolFees(
                    0xB4d13F81864f99BdfFCCeE513803b0Be236d71D1 //
                ),
                protocolFeesProd: ProtocolFees(
                    address(0) //
                ),
                protocolModuleList: address(0), //
                protocolModuleListProd: address(0), //
                wrappedNative: IWETH9(
                    address(0)
                ),
                uniswapRouter: IV3SwapRouter(
                    address(0)
                ),
                uniswapFactory: IUniswapV3Factory(
                    address(0)
                ),
                uniswapNFTPositionManager: INonfungiblePositionManager(
                    address(0)
                ),
                pancakeswapRouter: IV3SwapRouter(address(0)),
                pancakeswapFactory: IUniswapV3Factory(address(0)),
                pancakeswapNFTPositionManager: INonfungiblePositionManager(
                    address(0)
                ),
                aaveAddressesProvider: IPoolAddressesProvider(address(0)),
                automateGelato: IAutomate(0x2A6C106ae13B558BB9E2Ec64Bd2f1f7BEFF3A5E0),
                stargateRouter: address(0),
                layerZeroEndpoint: address(0),
                celerCircleBridgeProxy: address(0),
                usdc: address(0),
                entryPoint: address(0),
                entryPointCreator: address(0),
                logics: logics,
                lens: lens,
                modules: modules,
                partnerFeesContracts: partnerFeesContracts
            });
    }

    // BNB
    function _56() internal pure returns (Contracts memory) {
        Lens memory lens;

        lens.dexLogicLens = DexLogicLens(
            0xfEF9f366D26B1F258F840c5FebBC56b1d9251968 //
        );

        lens.aaveLogicLens = AaveLogicLens(
            address(1) // not used
        );

        Logics memory logics;

        logics.vaultUpgradeLogic = 0xB5047973F9922d04d7d69dC5A2DCd350A51A1833; //
        logics.accountAbstractionLogic = address(0); //
        logics.versionUpgradeLogic = 0xE1390425947E3EDb9E4140D47B3416234e0b8f9f; //
        logics.accessControlLogic = address(0); //
        logics.entryPointLogic = 0xAA382401E12b52c8D19e77D94E5f83c8929513b0; //
        logics.executionLogic = address(0); //
        logics.vaultLogic = 0x6813268601CeE8823cDcB067b3810f1A44332041; //
        logics.nativeWrapper = 0x6dc6618be03c1206822783799BB2B76d99C19D43; //
        logics.uniswapLogic = 0x3b1dC0C1150084FD9409b7C710b5b25b9E6fC1cb; //
        logics.pancakeswapLogic = 0x5bc30537435BD36Fa07eea85e99B109Ce8884d9E; //
        logics.timeCheckerLogic = 0xC389aabfF3b89C47834Ea53E5977df6A8F912Bf7; //
        logics
            .priceCheckerLogicUniswap = 0x1B61420aeA5f653cDF05be35dB033f402B2fb439; //
        logics
            .priceDifferenceCheckerLogicUniswap = 0x94991eD3031770fF147a342dE3bdE29d122b1943; //
        logics
            .priceCheckerLogicPancakeswap = 0xB794829997d0735640a03eF991ff28cd1a4425EF; //
        logics
            .priceDifferenceCheckerLogicPancakeswap = 0x34Ce7277f3Aa85c2e0C47BC96f9FcC168aC2d215; //
        logics.deltaNeutralStrategyLogic = address(1); // not used
        logics.aaveCheckerLogic = address(1); // not used
        logics.aaveActionLogic = address(1); // not used
        logics.stargateLogic = 0x6d07Ade94Fe6a673403fCB9b85ACbF04Faf4feC9; //
        logics.layerZeroLogic = 0x71117ef2ab65D1272605C2CCD87CB03F545AfE15; //
        logics.celerCircleBridgeLogic = address(1); // not used
        logics
            .uniswapDexCheckerLogic = 0xb399b7453762b2C7C755D21AE3810b575754bF52; //
        logics
            .pancakeswapDexCheckerLogic = 0x5cEE7F75B20192C5b527aAa7Fd0Fa91389C3CD1F; //

        // Prod
        logics
            .versionUpgradeLogicProd = 0x6c07D39042b2480a512675fdcc10A20756ba2d7B; //
        logics.entryPointLogicProd = 0xd25c77Ed795b2998B57F1a751702D7989c9450b9; //
        logics.executionLogicProd = address(0); //
        logics.stargateLogicProd = 0xd04037655Ce3F8f09769f6FcCC879dFC1D2Fad65; //
        logics.layerZeroLogicProd = 0x57df426E542FebB9DFA82e11b79478e9721261BA; //

        Modules memory modules;
        modules.partnerFeeModule = address(1); // not needed rn

        PartnerFeesContracts memory partnerFeesContracts;
        partnerFeesContracts.partnerFees = address(1); // not needed rn

        return
            Contracts({
                vaultFactoryProxyAdmin: ProxyAdmin(
                    0x2D75C403384C6Ce374ba8B27451eF0F4BcD77c2E //
                ),
                vaultFactoryImplementation: address(0),
                vaultFactoryImplementationProd: address(0),
                vaultFactoryProxy: ITransparentUpgradeableProxy(
                    0xF03C8CaB74b5721eB81210592C9B06f662e9951E //
                ),
                vaultFactoryProxyProd: ITransparentUpgradeableProxy(
                    0xaB5F025297E40bd5ECf340d1709008eFF230C6cA //
                ),
                vaultProxyAdmin: VaultProxyAdmin(
                    0x0F320AF6CC51b1a64aab6a9f75C505CB7d9791Cc //
                ),
                vaultProxyAdminProd: VaultProxyAdmin(
                    0x2eEa83b0347DbC80d66a26Ce0DcD5fB0438A7C3C //
                ),
                dittoOracle: IDittoOracleV3(
                    0xCeEED49D9e707CD8d3c657387d65C14E72c10e9F //
                ),
                dittoBridgeReceiver: DittoBridgeReceiver(
                    0xB8A56D5cA1FFAa883A1b17eF8604B6d53c9D5Ee7 //
                ),
                dittoBridgeReceiverProd: DittoBridgeReceiver(
                    0xA758A4F9850afbCD000125D53ef19D45a311d6F8 //
                ),
                protocolFees: ProtocolFees(
                    0xF77685eE181defDE68E273399bc37750927eFeD5 //
                ),
                protocolFeesProd: ProtocolFees(
                    0xC0bb9aBA8D3f9ee0E7E1B1fDa8a63705e9D80fF5 //
                ),
                protocolModuleList: 0x656ef3d09f2ed8912D892428e701Eb44Fcf1468a,
                protocolModuleListProd: 0xb686A36f8F755cb65623f2cA0A58deD18BB4e97B,
                wrappedNative: IWETH9(
                    0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c
                ),
                uniswapRouter: IV3SwapRouter(
                    0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2
                ),
                uniswapFactory: IUniswapV3Factory(
                    0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7
                ),
                uniswapNFTPositionManager: INonfungiblePositionManager(
                    0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613
                ),
                pancakeswapRouter: IV3SwapRouter(
                    0x13f4EA83D0bd40E75C8222255bc855a974568Dd4
                ),
                pancakeswapFactory: IUniswapV3Factory(
                    0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865
                ),
                pancakeswapNFTPositionManager: INonfungiblePositionManager(
                    0x46A15B0b27311cedF172AB29E4f4766fbE7F4364
                ),
                aaveAddressesProvider: IPoolAddressesProvider(address(0)),
                automateGelato: IAutomate(
                    0x2A6C106ae13B558BB9E2Ec64Bd2f1f7BEFF3A5E0
                ),
                stargateRouter: 0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9,
                layerZeroEndpoint: 0x3c2269811836af69497E5F486A85D7316753cf62,
                celerCircleBridgeProxy: address(0),
                usdc: address(0),
                entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789,
                entryPointCreator: 0x7fc98430eAEdbb6070B35B39D798725049088348,
                logics: logics,
                lens: lens,
                modules: modules,
                partnerFeesContracts: partnerFeesContracts
            });
    }

    // Arbitrum
    function _42161() internal pure returns (Contracts memory) {
        Lens memory lens;

        lens.dexLogicLens = DexLogicLens(
            0x0F75cEf935D8A4D30E6dC95A385d6bCCC657678E //
        );
        lens.aaveLogicLens = AaveLogicLens(
            0x953BAaBbC3b6034571417BF78508799E7B1Ebf3E //
        );

        Logics memory logics;

        logics.vaultUpgradeLogic = 0xB5047973F9922d04d7d69dC5A2DCd350A51A1833; //
        logics
            .accountAbstractionLogic = 0xAA382401E12b52c8D19e77D94E5f83c8929513b0; //
        logics.versionUpgradeLogic = 0x48f90754Da260d77300C84e0232bBce88A9201aC; //
        logics.accessControlLogic = 0x64B7064C2d645C675Ed71c198A231845F94da9AD; //
        logics.entryPointLogic = 0x4905454A0A80aAD00b167b522FaF3a1a86ca409b; //
        logics.executionLogic = 0x1d0491e236922e7A89691ff3Cc57dA644aC9c0f8; //
        logics.vaultLogic = 0x00271479c7491CdfE6f8115763CA897505246Dbd; //
        logics.nativeWrapper = 0x0eFBcC601f69e0b7B975BA1eCE20a428feb74e09; //
        logics.uniswapLogic = 0x6d07Ade94Fe6a673403fCB9b85ACbF04Faf4feC9; //
        logics.pancakeswapLogic = address(1); // not used
        logics.timeCheckerLogic = 0x19c3b388BcaF974e323417D893d39fB6FcF9800a; //
        logics
            .priceCheckerLogicUniswap = 0x71117ef2ab65D1272605C2CCD87CB03F545AfE15; //
        logics
            .priceDifferenceCheckerLogicUniswap = 0xb399b7453762b2C7C755D21AE3810b575754bF52; //
        logics.priceCheckerLogicPancakeswap = address(1); // not used
        logics.priceDifferenceCheckerLogicPancakeswap = address(1); // not used
        logics
            .deltaNeutralStrategyLogic = 0x5cEE7F75B20192C5b527aAa7Fd0Fa91389C3CD1F; //
        logics.aaveCheckerLogic = 0x7c8D30FA130B8097d6019Ea2fb6cAe5cDc81cf71; //
        logics.aaveActionLogic = 0x1B33BD3029616d62B452FD37D6A20526b57de14b; //
        logics.stargateLogic = 0x253d2a76071eeD1729523Aa92ad7498985493481; //
        logics.layerZeroLogic = 0x6813268601CeE8823cDcB067b3810f1A44332041; //
        logics
            .celerCircleBridgeLogic = 0x6dc6618be03c1206822783799BB2B76d99C19D43; //
        logics
            .uniswapDexCheckerLogic = 0x69D57dC47561c3bf5C93Cc8a895B00E214C1DFD0; //
        logics.pancakeswapDexCheckerLogic = address(1); // not used

        // Prod
        logics
            .versionUpgradeLogicProd = 0x73b302b4b7ee44afC3e50Dceb898E0DE9346D39E; //
        logics.entryPointLogicProd = 0x244Bb9D0D61D2A56Edc67B2891fDa4F28931c8E8; //
        logics.executionLogicProd = address(0); //
        logics.stargateLogicProd = 0xF69158573224A096f1cFBB9fbb639f9582Ef395B; //
        logics.layerZeroLogicProd = 0xFf2788e2c24774FB40396303F5543dEa67f5AE04; //

        Modules memory modules;
        modules.partnerFeeModule = address(0);

        PartnerFeesContracts memory partnerFeesContracts;
        partnerFeesContracts.partnerFees = address(0); // not needed rn

        return
            Contracts({
                vaultFactoryProxyAdmin: ProxyAdmin(
                    0x2D75C403384C6Ce374ba8B27451eF0F4BcD77c2E //
                ),
                vaultFactoryImplementation: 0x6E61122e5D1201f7B73Cb60Af9dc8F3b6b2389A8,
                vaultFactoryImplementationProd: address(0),
                vaultFactoryProxy: ITransparentUpgradeableProxy(
                    0xF03C8CaB74b5721eB81210592C9B06f662e9951E //
                ),
                vaultFactoryProxyProd: ITransparentUpgradeableProxy(
                    0xaB5F025297E40bd5ECf340d1709008eFF230C6cA //
                ),
                vaultProxyAdmin: VaultProxyAdmin(
                    0x0F320AF6CC51b1a64aab6a9f75C505CB7d9791Cc //
                ),
                vaultProxyAdminProd: VaultProxyAdmin(
                    0x2eEa83b0347DbC80d66a26Ce0DcD5fB0438A7C3C //
                ),
                dittoOracle: IDittoOracleV3(
                    0xE1390425947E3EDb9E4140D47B3416234e0b8f9f //
                ),
                dittoBridgeReceiver: DittoBridgeReceiver(
                    0xB8A56D5cA1FFAa883A1b17eF8604B6d53c9D5Ee7 //
                ),
                dittoBridgeReceiverProd: DittoBridgeReceiver(
                    0xA758A4F9850afbCD000125D53ef19D45a311d6F8 //
                ),
                protocolFees: ProtocolFees(
                    0xF77685eE181defDE68E273399bc37750927eFeD5 //
                ),
                protocolFeesProd: ProtocolFees(
                    0x9A18a1de43330c7D32959032253Dc320520d9dD6 //
                ),
                protocolModuleList: 0x4738e72207BfABf664aabCe70a93c29ACb4C0B6D, //
                protocolModuleListProd: 0xA9dd5424Dd731943466474C358B711Bce4F7160D, //
                wrappedNative: IWETH9(
                    0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
                ),
                uniswapRouter: IV3SwapRouter(
                    0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
                ),
                uniswapFactory: IUniswapV3Factory(
                    0x1F98431c8aD98523631AE4a59f267346ea31F984
                ),
                uniswapNFTPositionManager: INonfungiblePositionManager(
                    0xC36442b4a4522E871399CD717aBDD847Ab11FE88
                ),
                pancakeswapRouter: IV3SwapRouter(address(0)),
                pancakeswapFactory: IUniswapV3Factory(address(0)),
                pancakeswapNFTPositionManager: INonfungiblePositionManager(
                    address(0)
                ),
                aaveAddressesProvider: IPoolAddressesProvider(
                    0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb
                ),
                automateGelato: IAutomate(
                    0x2A6C106ae13B558BB9E2Ec64Bd2f1f7BEFF3A5E0
                ),
                stargateRouter: 0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9,
                layerZeroEndpoint: 0x3c2269811836af69497E5F486A85D7316753cf62,
                celerCircleBridgeProxy: 0x054B95b60BFFACe948Fa4548DA8eE2e212fb7C0a,
                usdc: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
                entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789,
                entryPointCreator: 0x7fc98430eAEdbb6070B35B39D798725049088348,
                logics: logics,
                lens: lens,
                modules: modules,
                partnerFeesContracts: partnerFeesContracts
            });
    }

    // Avalanche
    function _43114() internal pure returns (Contracts memory) {
        Lens memory lens;

        lens.dexLogicLens = DexLogicLens(
            0xfEF9f366D26B1F258F840c5FebBC56b1d9251968 //
        );
        lens.aaveLogicLens = AaveLogicLens(
            0x66108A5d64798957A06d1e7F3b5880e97E302897 //
        );

        Logics memory logics;

        logics.vaultUpgradeLogic = 0xB5047973F9922d04d7d69dC5A2DCd350A51A1833; //
        logics.accountAbstractionLogic = address(0); //
        logics.versionUpgradeLogic = 0x69D57dC47561c3bf5C93Cc8a895B00E214C1DFD0; //
        logics.accessControlLogic = address(0); //
        logics.entryPointLogic = 0xC21c366AaCf69Ee5157db48047E94CC607A2c5BE; //
        logics.executionLogic = address(0); //
        logics.vaultLogic = 0xd17d47ef7BF955F49F0AfFd7be3301544e8dBB9F; //
        logics.nativeWrapper = 0xcB0240Ba3F43723817253FdBAD8C9A7C1c49641F; //
        logics.uniswapLogic = 0x5cEE7F75B20192C5b527aAa7Fd0Fa91389C3CD1F; //
        logics.pancakeswapLogic = address(1); // not used
        logics.timeCheckerLogic = 0x57B7b34aD913775868eF4DBF2a9e899C2aDAEaE4; //
        logics
            .priceCheckerLogicUniswap = 0x7c8D30FA130B8097d6019Ea2fb6cAe5cDc81cf71; //
        logics
            .priceDifferenceCheckerLogicUniswap = 0x3B631ba46C7E0D058F5f34699c8912Cb01b87d2e; //
        logics.priceCheckerLogicPancakeswap = address(1); // not used
        logics.priceDifferenceCheckerLogicPancakeswap = address(1); // not used
        logics
            .deltaNeutralStrategyLogic = 0xbf78b516B37A06F39f551B29fb9975A8DF62aa21; //
        logics.aaveCheckerLogic = 0x7376A1cfA0b2D899155A066DF5e9643Ce280EeFA; //
        logics.aaveActionLogic = 0xF69158573224A096f1cFBB9fbb639f9582Ef395B; //
        logics.stargateLogic = 0xFf2788e2c24774FB40396303F5543dEa67f5AE04; //
        logics.layerZeroLogic = 0x0ebd83871160FeBc3736d4Ecfa50ee474DBF2d76; //
        logics
            .celerCircleBridgeLogic = 0xB5DC840Cc0B26CA136cA91c72656baa0948E384D; //
        logics
            .uniswapDexCheckerLogic = 0x9317c7fDe9B39bd7Af49e0c957106fa4371d76D6; //
        logics.pancakeswapDexCheckerLogic = address(1); // not used

        // Prod
        logics
            .versionUpgradeLogicProd = 0x244Bb9D0D61D2A56Edc67B2891fDa4F28931c8E8; //
        logics.entryPointLogicProd = 0x9B5056cB0378b461924DF358746BB0F7A57c0524; //
        logics.executionLogicProd = address(0); //
        logics.stargateLogicProd = 0x8dd11644985B03EA14281d4f708A7Bbe28cF6d1b; //
        logics.layerZeroLogicProd = 0xb7595CaF0d362bFBF89D9E64e1583B8238841CeB; //

        Modules memory modules;
        modules.partnerFeeModule = address(1); // not needed rn

        PartnerFeesContracts memory partnerFeesContracts;
        partnerFeesContracts.partnerFees = address(1); // not needed rn

        return
            Contracts({
                vaultFactoryProxyAdmin: ProxyAdmin(
                    0x2D75C403384C6Ce374ba8B27451eF0F4BcD77c2E //
                ),
                vaultFactoryImplementation: address(0),
                vaultFactoryImplementationProd: address(0),
                vaultFactoryProxy: ITransparentUpgradeableProxy(
                    0xF03C8CaB74b5721eB81210592C9B06f662e9951E //
                ),
                vaultFactoryProxyProd: ITransparentUpgradeableProxy(
                    0xaB5F025297E40bd5ECf340d1709008eFF230C6cA //
                ),
                vaultProxyAdmin: VaultProxyAdmin(
                    0x0F320AF6CC51b1a64aab6a9f75C505CB7d9791Cc //
                ),
                vaultProxyAdminProd: VaultProxyAdmin(
                    0x2eEa83b0347DbC80d66a26Ce0DcD5fB0438A7C3C //
                ),
                dittoOracle: IDittoOracleV3(
                    0x71117ef2ab65D1272605C2CCD87CB03F545AfE15 //
                ),
                dittoBridgeReceiver: DittoBridgeReceiver(
                    0xB8A56D5cA1FFAa883A1b17eF8604B6d53c9D5Ee7 //
                ),
                dittoBridgeReceiverProd: DittoBridgeReceiver(
                    0xA758A4F9850afbCD000125D53ef19D45a311d6F8 //
                ),
                protocolFees: ProtocolFees(
                    0xF77685eE181defDE68E273399bc37750927eFeD5 //
                ),
                protocolFeesProd: ProtocolFees(
                    0x9A18a1de43330c7D32959032253Dc320520d9dD6 //
                ),
                protocolModuleList: 0xb399b7453762b2C7C755D21AE3810b575754bF52, //
                protocolModuleListProd: 0x5A5b365c72D81B8CBFb69996C03eb0d4DBC4A386, //
                wrappedNative: IWETH9(
                    0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7
                ),
                // https://gov.uniswap.org/t/deploy-uniswap-v3-on-avalanche/20587/18
                uniswapRouter: IV3SwapRouter(
                    0xbb00FF08d01D300023C629E8fFfFcb65A5a578cE
                ),
                uniswapFactory: IUniswapV3Factory(
                    0x740b1c1de25031C31FF4fC9A62f554A55cdC1baD
                ),
                uniswapNFTPositionManager: INonfungiblePositionManager(
                    0x655C406EBFa14EE2006250925e54ec43AD184f8B
                ),
                pancakeswapRouter: IV3SwapRouter(address(0)),
                pancakeswapFactory: IUniswapV3Factory(address(0)),
                pancakeswapNFTPositionManager: INonfungiblePositionManager(
                    address(0)
                ),
                aaveAddressesProvider: IPoolAddressesProvider(
                    0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb
                ),
                automateGelato: IAutomate(
                    0x2A6C106ae13B558BB9E2Ec64Bd2f1f7BEFF3A5E0
                ),
                stargateRouter: 0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9,
                layerZeroEndpoint: 0x3c2269811836af69497E5F486A85D7316753cf62,
                celerCircleBridgeProxy: 0x9744ae566c64B6B6f7F9A4dD50f7496Df6Fef990,
                usdc: 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E,
                entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789,
                entryPointCreator: 0x7fc98430eAEdbb6070B35B39D798725049088348,
                logics: logics,
                lens: lens,
                modules: modules,
                partnerFeesContracts: partnerFeesContracts
            });
    }

    // Celo
    function _42220() internal pure returns (Contracts memory reg) {
        Lens memory lens;

        lens.dexLogicLens = DexLogicLens(
            0xb2e04b05bff12eE15e47B6eA767A61995c50F509 //
        );
        lens.aaveLogicLens = AaveLogicLens(
            address(1) // not used
        );

        Logics memory logics;

        logics.vaultUpgradeLogic = 0xB5047973F9922d04d7d69dC5A2DCd350A51A1833; //
        logics.accountAbstractionLogic = address(0); //
        logics.versionUpgradeLogic = 0x162eE1F1b1d15c8908344f9991A34E526E888c75; //
        logics.accessControlLogic = address(0); //
        logics.entryPointLogic = 0xBC2DDDa755178Ce1f0AB78590744ee65ebF76b35; //
        logics.executionLogic = address(0); //
        logics.vaultLogic = 0xd7713E7525476b938E889A93e38025e26F5C51cd; //
        logics.nativeWrapper = address(1); // not used
        logics.uniswapLogic = 0x253d2a76071eeD1729523Aa92ad7498985493481; //
        logics.pancakeswapLogic = address(1); // not used
        logics.timeCheckerLogic = 0x93926188A0C4c681193470Dd36f468D30a5705C2; //
        logics
            .priceCheckerLogicUniswap = 0x6813268601CeE8823cDcB067b3810f1A44332041; //
        logics
            .priceDifferenceCheckerLogicUniswap = 0x6dc6618be03c1206822783799BB2B76d99C19D43; //
        logics.priceCheckerLogicPancakeswap = address(1); // not used
        logics.priceDifferenceCheckerLogicPancakeswap = address(1); // not used
        logics.deltaNeutralStrategyLogic = address(1); // not used
        logics.aaveCheckerLogic = address(1); // not used
        logics.aaveActionLogic = address(1); // not used
        logics.stargateLogic = address(1); // not used
        logics.layerZeroLogic = 0x7E5411c3075B2c4387B693d669B7c6bCb97a8072; //
        logics.celerCircleBridgeLogic = address(1); // not used
        logics
            .uniswapDexCheckerLogic = 0xF4CbA02c42d21eBe833379Af0B1579458634388d; //
        logics.pancakeswapDexCheckerLogic = address(1); // not used

        // Prod
        logics
            .versionUpgradeLogicProd = 0x181061Ad3d55376E3D0822F3F6f55e5d3a565501; //
        logics.entryPointLogicProd = 0x48f90754Da260d77300C84e0232bBce88A9201aC; //
        logics.executionLogicProd = address(0); //
        logics.stargateLogicProd = address(1); // not used
        logics.layerZeroLogicProd = 0x5b382e1eD58eC00987aC32c67029E1465918C18a; //

        Modules memory modules;
        modules.partnerFeeModule = address(1); // not needed rn

        PartnerFeesContracts memory partnerFeesContracts;
        partnerFeesContracts.partnerFees = address(1); // not needed rn

        return
            Contracts({
                vaultFactoryProxyAdmin: ProxyAdmin(
                    0x2D75C403384C6Ce374ba8B27451eF0F4BcD77c2E //
                ),
                vaultFactoryImplementation: address(0),
                vaultFactoryImplementationProd: address(0),
                vaultFactoryProxy: ITransparentUpgradeableProxy(
                    0xF03C8CaB74b5721eB81210592C9B06f662e9951E //
                ),
                vaultFactoryProxyProd: ITransparentUpgradeableProxy(
                    0xaB5F025297E40bd5ECf340d1709008eFF230C6cA //
                ),
                vaultProxyAdmin: VaultProxyAdmin(
                    0x0F320AF6CC51b1a64aab6a9f75C505CB7d9791Cc //
                ),
                vaultProxyAdminProd: VaultProxyAdmin(
                    0x2eEa83b0347DbC80d66a26Ce0DcD5fB0438A7C3C //
                ),
                dittoOracle: IDittoOracleV3(
                    0x419b2804F05D69cC2234541D65739B3381A6d8d3 //
                ),
                dittoBridgeReceiver: DittoBridgeReceiver(
                    0xB8A56D5cA1FFAa883A1b17eF8604B6d53c9D5Ee7 //
                ),
                dittoBridgeReceiverProd: DittoBridgeReceiver(
                    0xA758A4F9850afbCD000125D53ef19D45a311d6F8 //
                ),
                protocolFees: ProtocolFees(
                    0xc043058B9ADbc55a70d7D8e2D2B8B772795F743C //
                ),
                protocolFeesProd: ProtocolFees(
                    0x9B6bCdC0bC9D6821a4cED94dA6b954ce44EA67a5 //
                ),
                protocolModuleList: 0x1B33BD3029616d62B452FD37D6A20526b57de14b, //
                protocolModuleListProd: 0xC389aabfF3b89C47834Ea53E5977df6A8F912Bf7, //
                wrappedNative: IWETH9(address(0)),
                uniswapRouter: IV3SwapRouter(
                    0x5615CDAb10dc425a742d643d949a7F474C01abc4
                ),
                uniswapFactory: IUniswapV3Factory(
                    0xAfE208a311B21f13EF87E33A90049fC17A7acDEc
                ),
                uniswapNFTPositionManager: INonfungiblePositionManager(
                    0x3d79EdAaBC0EaB6F08ED885C05Fc0B014290D95A
                ),
                pancakeswapRouter: IV3SwapRouter(address(0)),
                pancakeswapFactory: IUniswapV3Factory(address(0)),
                pancakeswapNFTPositionManager: INonfungiblePositionManager(
                    address(0)
                ),
                aaveAddressesProvider: IPoolAddressesProvider(address(0)),
                automateGelato: IAutomate(address(0)),
                stargateRouter: address(0),
                layerZeroEndpoint: 0x3A73033C0b1407574C76BdBAc67f126f6b4a9AA9,
                celerCircleBridgeProxy: address(0),
                usdc: address(0),
                entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789,
                entryPointCreator: 0x7fc98430eAEdbb6070B35B39D798725049088348,
                logics: logics,
                lens: lens,
                modules: modules,
                partnerFeesContracts: partnerFeesContracts
            });
    }

    // Klaytn
    function _8217() internal pure returns (Contracts memory reg) {
        Lens memory lens;

        lens.dexLogicLens = DexLogicLens(
            0xBC2DDDa755178Ce1f0AB78590744ee65ebF76b35 //
        );
        lens.aaveLogicLens = AaveLogicLens(
            address(1) // not used
        );

        Logics memory logics;

        logics.vaultUpgradeLogic = 0xB5047973F9922d04d7d69dC5A2DCd350A51A1833; //
        logics.accountAbstractionLogic = address(0); //
        logics.versionUpgradeLogic = 0x81536efF4B03B468D1f6F37621Ec0a96E51052b4; //
        logics.accessControlLogic = address(0); //
        logics.entryPointLogic = 0xCf0fbDECd154E0a60b5b521b434DD4aF6dA57D1E; //
        logics.executionLogic = address(0); //
        logics.vaultLogic = 0xC097f59bfD97C6FC667F4ba4Bed780e2f9d10eCf; //
        logics.nativeWrapper = 0xdD6977b372f9fDA241A77F5FbA16E89DB67532BC; //
        logics.uniswapLogic = 0x69D57dC47561c3bf5C93Cc8a895B00E214C1DFD0; //
        logics.pancakeswapLogic = address(1); // not used
        logics.timeCheckerLogic = 0xF4CbA02c42d21eBe833379Af0B1579458634388d; //
        logics
            .priceCheckerLogicUniswap = 0x77c2c3eA05BA3D1C049CE95b42BD9ddeC31494f0; //
        logics
            .priceDifferenceCheckerLogicUniswap = 0xC389aabfF3b89C47834Ea53E5977df6A8F912Bf7; //
        logics.priceCheckerLogicPancakeswap = address(1); // not used
        logics.priceDifferenceCheckerLogicPancakeswap = address(1); // not used
        logics.deltaNeutralStrategyLogic = address(1); // not used
        logics.aaveCheckerLogic = address(1); // not used
        logics.aaveActionLogic = address(1); // not used
        logics.stargateLogic = address(1); // not used
        logics.layerZeroLogic = 0xa75ceCaa8Cc3Af343ca42EA97B0327F3fB7aB26A; //
        logics.celerCircleBridgeLogic = address(1); // not used
        logics
            .uniswapDexCheckerLogic = 0x9596D9BE211Bd9cf93c18bA3E7c19694f01B34A0; //
        logics.pancakeswapDexCheckerLogic = address(1); // not used

        // Prod
        logics
            .versionUpgradeLogicProd = 0xC016C463C93eD4C8CE99c3bDf7b111388f61Ad14; //
        logics.entryPointLogicProd = 0x901c7807eE24fc91CE56FcCd1575f461Ac08536F; //
        logics.executionLogicProd = address(0); //
        logics.stargateLogicProd = address(1); // not used
        logics.layerZeroLogicProd = 0x0eFBcC601f69e0b7B975BA1eCE20a428feb74e09; //

        Modules memory modules;
        modules.partnerFeeModule = address(1); // not needed rn

        PartnerFeesContracts memory partnerFeesContracts;
        partnerFeesContracts.partnerFees = address(1); // not needed rn

        return
            Contracts({
                vaultFactoryProxyAdmin: ProxyAdmin(
                    0x2D75C403384C6Ce374ba8B27451eF0F4BcD77c2E //
                ),
                vaultFactoryImplementation: address(0),
                vaultFactoryImplementationProd: address(0),
                vaultFactoryProxy: ITransparentUpgradeableProxy(
                    0xF03C8CaB74b5721eB81210592C9B06f662e9951E //
                ),
                vaultFactoryProxyProd: ITransparentUpgradeableProxy(
                    0xaB5F025297E40bd5ECf340d1709008eFF230C6cA //
                ),
                vaultProxyAdmin: VaultProxyAdmin(
                    0x0F320AF6CC51b1a64aab6a9f75C505CB7d9791Cc //
                ),
                vaultProxyAdminProd: VaultProxyAdmin(
                    0x2eEa83b0347DbC80d66a26Ce0DcD5fB0438A7C3C //
                ),
                dittoOracle: IDittoOracleV3(
                    0x6813268601CeE8823cDcB067b3810f1A44332041 //
                ),
                dittoBridgeReceiver: DittoBridgeReceiver(
                    0xB8A56D5cA1FFAa883A1b17eF8604B6d53c9D5Ee7 //
                ),
                dittoBridgeReceiverProd: DittoBridgeReceiver(
                    0xA758A4F9850afbCD000125D53ef19D45a311d6F8 //
                ),
                protocolFees: ProtocolFees(
                    0x58B54Fb2c2F8c0264d176819DF8B91738683cf1f //
                ),
                protocolFeesProd: ProtocolFees(
                    0x9B6bCdC0bC9D6821a4cED94dA6b954ce44EA67a5 //
                ),
                protocolModuleList: 0x6dc6618be03c1206822783799BB2B76d99C19D43, //
                protocolModuleListProd: 0xcB0240Ba3F43723817253FdBAD8C9A7C1c49641F, //
                wrappedNative: IWETH9(
                    0x19Aac5f612f524B754CA7e7c41cbFa2E981A4432
                ),
                uniswapRouter: IV3SwapRouter(
                    0x585D515cC24a57FAAb74d3998E0E0bff3a1c99E6
                ),
                uniswapFactory: IUniswapV3Factory(
                    0xA15Be7e90df29A4aeaD0C7Fc86f7a9fBe6502Ac9
                ),
                uniswapNFTPositionManager: INonfungiblePositionManager(
                    0x51D233B5aE7820030A29c75d6788403B8B5d317B
                ),
                pancakeswapRouter: IV3SwapRouter(address(0)),
                pancakeswapFactory: IUniswapV3Factory(address(0)),
                pancakeswapNFTPositionManager: INonfungiblePositionManager(
                    address(0)
                ),
                aaveAddressesProvider: IPoolAddressesProvider(address(0)),
                automateGelato: IAutomate(address(0)),
                stargateRouter: address(0),
                layerZeroEndpoint: 0x9740FF91F1985D8d2B71494aE1A2f723bb3Ed9E4,
                celerCircleBridgeProxy: address(0),
                usdc: address(0),
                entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789,
                entryPointCreator: 0x7fc98430eAEdbb6070B35B39D798725049088348,
                logics: logics,
                lens: lens,
                modules: modules,
                partnerFeesContracts: partnerFeesContracts
            });
    }


    function contractsByChainId(
        uint256 chainId
    ) internal pure returns (Contracts memory) {
        if (chainId == 137) {
            return _137();
        } else if (chainId == 56) {
            return _56();
        } else if (chainId == 42161) {
            return _42161();
        } else if (chainId == 43114) {
            return _43114();
        } else if (chainId == 42220) {
            return _42220();
        } else if (chainId == 8217) {
            return _8217();
        } else if (chainId == 80001) {
            return _80001();
        } else {
            revert InvalidChainId();
        }
    }
}
