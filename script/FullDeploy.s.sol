// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {ProxyAdmin, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DittoOracleV3} from "../src/DittoOracleV3.sol";
import {DittoBridgeReceiver} from "../src/DittoBridgeReceiver.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {Vault} from "../src/vault/Vault.sol";
import {UpgradeLogic} from "../src/vault/UpgradeLogic.sol";
import {VaultProxyAdmin} from "../src/VaultProxyAdmin.sol";

import {ProtocolFees} from "../src/ProtocolFees.sol";
import {ProtocolModuleList} from "../src/ProtocolModuleList.sol";

import {AccountAbstractionLogic} from "../src/vault/logics/AccountAbstractionLogic.sol";

import {VersionUpgradeLogic} from "../src/vault/logics/VersionUpgradeLogic.sol";
import {AccessControlLogic} from "../src/vault/logics/AccessControlLogic.sol";
import {EntryPointLogic} from "../src/vault/logics/EntryPointLogic.sol";
import {EntryPointLogicArbitrum} from "../src/vault/logics/arbitrumLogics/EntryPointLogicArbitrum.sol";
import {ExecutionLogic} from "../src/vault/logics/ExecutionLogic.sol";
import {ExecutionLogicArbitrum} from "../src/vault/logics/arbitrumLogics/ExecutionLogicArbitrum.sol";
import {VaultLogic} from "../src/vault/logics/VaultLogic.sol";
import {NativeWrapper} from "../src/vault/logics/OurLogic/helpers/NativeWrapper.sol";

import {UniswapLogic} from "../src/vault/logics/OurLogic/dexAutomation/UniswapLogic.sol";
import {PancakeswapLogic} from "../src/vault/logics/OurLogic/dexAutomation/PancakeswapLogic.sol";

import {DeltaNeutralStrategyLogic} from "../src/vault/logics/OurLogic/DeltaNeutralStrategyLogic.sol";
import {AaveActionLogic} from "../src/vault/logics/OurLogic/AaveActionLogic.sol";

import {AaveCheckerLogic} from "../src/vault/logics/Checkers/AaveCheckerLogic.sol";
import {DexCheckerLogicPancakeswap} from "../src/vault/logics/Checkers/DexCheckerLogicPancakeswap.sol";
import {DexCheckerLogicUniswap} from "../src/vault/logics/Checkers/DexCheckerLogicUniswap.sol";
import {PriceCheckerLogicPancakeswap} from "../src/vault/logics/Checkers/PriceCheckerLogicPancakeswap.sol";
import {PriceCheckerLogicUniswap} from "../src/vault/logics/Checkers/PriceCheckerLogicUniswap.sol";
import {PriceDifferenceCheckerLogicPancakeswap} from "../src/vault/logics/Checkers/PriceDifferenceCheckerLogicPancakeswap.sol";
import {PriceDifferenceCheckerLogicUniswap} from "../src/vault/logics/Checkers/PriceDifferenceCheckerLogicUniswap.sol";
import {TimeCheckerLogic} from "../src/vault/logics/Checkers/TimeCheckerLogic.sol";

import {StargateLogic} from "../src/vault/logics/OurLogic/bridges/StargateLogic.sol";
import {LayerZeroLogic} from "../src/vault/logics/OurLogic/bridges/LayerZeroLogic.sol";
import {CelerCircleBridgeLogic} from "../src/vault/logics/OurLogic/bridges/CelerCircleBridgeLogic.sol";

import {AaveLogicLens} from "../src/lens/AaveLogicLens.sol";
import {DexLogicLens} from "../src/lens/DexLogicLens.sol";

import {PartnerFeeModule} from "../src/vault/modules/PartnerFeeModule.sol";
import {PartnerFee} from "../src/vault/modules/PartnerFee.sol";

import {DeployEngine} from "./DeployEngine.sol";
import {Registry} from "./Registry.sol";

contract FullDeploy is Script {
    bytes32 constant salt = keccak256("DEV-1");

    bytes32 saltProd = keccak256("BETA-1");

    bool prod;

    function run(bool addImpl, bool _prod) external virtual {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        vm.startBroadcast(deployer);

        prod = _prod;

        Registry.Contracts memory reg = deployFactory();
        reg = deploySystemContracts(false, reg);
        reg = deployAndAddModules(false, reg, deployer);

        if (addImpl) {
            addImplementation(reg, false, deployer);
        }

        vm.stopBroadcast();
    }

    function deployFactory() public returns (Registry.Contracts memory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        Registry.Contracts memory reg = Registry.contractsByChainId(
            block.chainid
        );

        if (address(reg.vaultFactoryProxyAdmin) == address(0)) {
            reg.vaultFactoryProxyAdmin = new ProxyAdmin();
        }

        if (
            prod
                ? address(reg.vaultFactoryProxyProd) == address(0)
                : address(reg.vaultFactoryProxy) == address(0)
        ) {
            if (reg.logics.vaultUpgradeLogic == address(0)) {
                // upgrade logic
                reg.logics.vaultUpgradeLogic = address(new UpgradeLogic());
            }

            if (prod) {
                if (address(reg.vaultProxyAdminProd) == address(0)) {
                    // proxy admin
                    // must be same on all networks (w/o salt)
                    reg.vaultProxyAdminProd = new VaultProxyAdmin(
                        0xaB5F025297E40bd5ECf340d1709008eFF230C6cA // <-- prod factory
                        // (put ur address here)
                    );
                }
            } else {
                if (address(reg.vaultProxyAdmin) == address(0)) {
                    // proxy admin
                    // must be same on all networks (w/o salt)
                    reg.vaultProxyAdmin = new VaultProxyAdmin(
                        0xF03C8CaB74b5721eB81210592C9B06f662e9951E // <-- dev factory
                        // (put ur address here)
                    );
                }
            }

            // vault factory
            VaultFactory _vaultFactory = new VaultFactory{
                salt: prod ? saltProd : salt
            }(
                reg.logics.vaultUpgradeLogic,
                prod
                    ? address(reg.vaultProxyAdminProd)
                    : address(reg.vaultProxyAdmin)
            );

            _vaultFactory.upgradeLogic();
            _vaultFactory.vaultProxyAdmin();

            if (prod) {
                reg.vaultFactoryProxyProd = ITransparentUpgradeableProxy(
                    address(
                        new TransparentUpgradeableProxy{salt: saltProd}(
                            address(_vaultFactory),
                            // make sure that the vaultFactoryProxyAdmin is not address(0)
                            // from dev
                            address(reg.vaultFactoryProxyAdmin),
                            abi.encodeCall(
                                VaultFactory.initialize,
                                (vm.addr(deployerPrivateKey))
                            )
                        )
                    )
                );
            } else {
                reg.vaultFactoryProxy = ITransparentUpgradeableProxy(
                    address(
                        new TransparentUpgradeableProxy(
                            address(_vaultFactory),
                            address(reg.vaultFactoryProxyAdmin),
                            abi.encodeCall(
                                VaultFactory.initialize,
                                (vm.addr(deployerPrivateKey))
                            )
                        )
                    )
                );
            }
        }

        if (prod) {
            if (address(reg.protocolFeesProd) == address(0)) {
                // prod protocol fees
                reg.protocolFeesProd = new ProtocolFees{salt: saltProd}(
                    vm.addr(deployerPrivateKey)
                );
            }

            if (address(reg.dittoBridgeReceiverProd) == address(0)) {
                reg.dittoBridgeReceiverProd = new DittoBridgeReceiver{
                    salt: saltProd
                }(
                    address(reg.vaultFactoryProxyProd),
                    vm.addr(deployerPrivateKey)
                );

                reg.dittoBridgeReceiverProd.setBridgeContracts(
                    reg.stargateRouter,
                    reg.layerZeroEndpoint
                );

                reg.dittoBridgeReceiverProd.stargateComposer();
                reg.dittoBridgeReceiverProd.layerZeroEndpoint();
            }
        } else {
            if (address(reg.protocolFees) == address(0)) {
                // dev protocol fees
                reg.protocolFees = new ProtocolFees{salt: salt}(
                    vm.addr(deployerPrivateKey)
                );
            }

            if (address(reg.dittoBridgeReceiver) == address(0)) {
                reg.dittoBridgeReceiver = new DittoBridgeReceiver{salt: salt}(
                    address(reg.vaultFactoryProxy),
                    vm.addr(deployerPrivateKey)
                );

                reg.dittoBridgeReceiver.setBridgeContracts(
                    reg.stargateRouter,
                    reg.layerZeroEndpoint
                );

                reg.dittoBridgeReceiver.stargateComposer();
                reg.dittoBridgeReceiver.layerZeroEndpoint();
            }
        }

        return reg;
    }

    function addImplementation(
        Registry.Contracts memory reg,
        bool test,
        address owner
    ) public returns (VaultFactory vaultFactory, Vault vault) {
        (bytes4[] memory selectors, address[] memory logicAddresses) = _getData(
            reg.logics
        );

        if (address(reg.vaultFactoryProxyAdmin) == address(0) || test) {
            reg.vaultFactoryProxyAdmin = new ProxyAdmin();
        }

        if (address(reg.vaultFactoryProxy) == address(0) || test) {
            VaultFactory _vaultFactory = new VaultFactory(
                reg.logics.vaultUpgradeLogic,
                address(reg.vaultProxyAdmin)
            );

            reg.vaultFactoryProxy = ITransparentUpgradeableProxy(
                address(
                    new TransparentUpgradeableProxy(
                        address(_vaultFactory),
                        address(reg.vaultFactoryProxyAdmin),
                        abi.encodeCall(VaultFactory.initialize, (owner))
                    )
                )
            );
        }

        vaultFactory = VaultFactory(
            address(prod ? reg.vaultFactoryProxyProd : reg.vaultFactoryProxy)
        );

        if (prod) {
            console2.log("protocolModuleListProd", reg.protocolModuleListProd);
        } else {
            console2.log("protocolModuleList", reg.protocolModuleList);
        }

        vault = new Vault(
            selectors,
            logicAddresses,
            prod ? reg.protocolModuleListProd : reg.protocolModuleList
        );

        vaultFactory.addNewImplementation(address(vault));

        vaultFactory.versions();
    }

    function deploySystemContracts(
        bool test,
        Registry.Contracts memory reg
    ) public returns (Registry.Contracts memory) {
        if (address(reg.dittoOracle) == address(0)) {
            reg.dittoOracle = new DittoOracleV3();
        }

        if (prod) {
            if (reg.protocolModuleListProd == address(0)) {
                reg.protocolModuleListProd = address(new ProtocolModuleList());
            }
        } else {
            if (reg.protocolModuleList == address(0) || test) {
                reg.protocolModuleList = address(new ProtocolModuleList());
            }
        }
        if (address(reg.lens.dexLogicLens) == address(0)) {
            reg.lens.dexLogicLens = new DexLogicLens();
        }
        if (address(reg.lens.aaveLogicLens) == address(0)) {
            reg.lens.aaveLogicLens = new AaveLogicLens(
                reg.aaveAddressesProvider
            );
        }

        // common logic
        reg.logics.vaultUpgradeLogic = reg.logics.vaultUpgradeLogic ==
            address(0) ||
            test
            ? address(new UpgradeLogic())
            : reg.logics.vaultUpgradeLogic;

        reg.logics.accountAbstractionLogic = reg
            .logics
            .accountAbstractionLogic ==
            address(0) ||
            test
            ? address(new AccountAbstractionLogic(reg.entryPoint))
            : reg.logics.accountAbstractionLogic;

        if (prod) {
            console.log(
                "vaultFactoryProxyProd",
                address(reg.vaultFactoryProxyProd)
            );
            reg.logics.versionUpgradeLogicProd = reg
                .logics
                .versionUpgradeLogicProd == address(0)
                ? address(
                    new VersionUpgradeLogic(
                        VaultFactory(address(reg.vaultFactoryProxyProd))
                    )
                )
                : reg.logics.versionUpgradeLogicProd;
        } else {
            console.log("vaultFactoryProxy", address(reg.vaultFactoryProxy));
            reg.logics.versionUpgradeLogic = reg.logics.versionUpgradeLogic ==
                address(0)
                ? address(
                    new VersionUpgradeLogic(
                        VaultFactory(address(reg.vaultFactoryProxy))
                    )
                )
                : reg.logics.versionUpgradeLogic;
        }

        reg.logics.accessControlLogic = reg.logics.accessControlLogic ==
            address(0) ||
            test
            ? address(new AccessControlLogic())
            : reg.logics.accessControlLogic;

        if (prod) {
            console.log("protocolFeesProd", address(reg.protocolFeesProd));
            reg.logics.entryPointLogicProd = reg.logics.entryPointLogicProd ==
                address(0)
                ? block.chainid == 42161
                    ? address(
                        new EntryPointLogicArbitrum(
                            reg.automateGelato,
                            reg.protocolFeesProd
                        )
                    )
                    : address(
                        new EntryPointLogic(
                            reg.automateGelato,
                            reg.protocolFeesProd
                        )
                    )
                : reg.logics.entryPointLogicProd;

            reg.logics.executionLogicProd = reg.logics.executionLogicProd ==
                address(0)
                ? block.chainid == 42161
                    ? address(new ExecutionLogicArbitrum(reg.protocolFeesProd))
                    : address(new ExecutionLogic(reg.protocolFeesProd))
                : reg.logics.executionLogicProd;
        } else {
            console.log("protocolFees", address(reg.protocolFees));
            reg.logics.entryPointLogic = reg.logics.entryPointLogic ==
                address(0) ||
                test
                ? block.chainid == 42161
                    ? address(
                        new EntryPointLogicArbitrum(
                            reg.automateGelato,
                            reg.protocolFees
                        )
                    )
                    : address(
                        new EntryPointLogic(
                            reg.automateGelato,
                            reg.protocolFees
                        )
                    )
                : reg.logics.entryPointLogic;

            reg.logics.executionLogic = reg.logics.executionLogic ==
                address(0) ||
                test
                ? block.chainid == 42161
                    ? address(new ExecutionLogicArbitrum(reg.protocolFees))
                    : address(new ExecutionLogic(reg.protocolFees))
                : reg.logics.executionLogic;
        }

        reg.logics.vaultLogic = reg.logics.vaultLogic == address(0) || test
            ? address(new VaultLogic())
            : reg.logics.vaultLogic;

        reg.logics.nativeWrapper = reg.logics.nativeWrapper == address(0) ||
            (test && reg.logics.nativeWrapper != address(1))
            ? address(new NativeWrapper(reg.wrappedNative))
            : reg.logics.nativeWrapper;

        // uniswap
        reg.logics.uniswapLogic = reg.logics.uniswapLogic == address(0) || test
            ? address(
                new UniswapLogic(
                    reg.uniswapNFTPositionManager,
                    reg.uniswapRouter,
                    reg.uniswapFactory,
                    reg.wrappedNative
                )
            )
            : reg.logics.uniswapLogic;

        reg.logics.pancakeswapLogic = reg.logics.pancakeswapLogic ==
            address(0) ||
            (test && reg.logics.pancakeswapLogic != address(1))
            ? address(
                new PancakeswapLogic(
                    reg.pancakeswapNFTPositionManager,
                    reg.pancakeswapRouter,
                    reg.pancakeswapFactory,
                    reg.wrappedNative
                )
            )
            : reg.logics.pancakeswapLogic;

        // time checker
        reg.logics.timeCheckerLogic = reg.logics.timeCheckerLogic ==
            address(0) ||
            test
            ? address(new TimeCheckerLogic())
            : reg.logics.timeCheckerLogic;

        // price checkers
        reg.logics.priceCheckerLogicUniswap = reg
            .logics
            .priceCheckerLogicUniswap ==
            address(0) ||
            test
            ? address(
                new PriceCheckerLogicUniswap(
                    reg.dittoOracle,
                    address(reg.uniswapFactory)
                )
            )
            : reg.logics.priceCheckerLogicUniswap;

        reg.logics.priceDifferenceCheckerLogicUniswap = reg
            .logics
            .priceDifferenceCheckerLogicUniswap ==
            address(0) ||
            test
            ? address(
                new PriceDifferenceCheckerLogicUniswap(
                    reg.dittoOracle,
                    address(reg.uniswapFactory)
                )
            )
            : reg.logics.priceDifferenceCheckerLogicUniswap;

        reg.logics.priceCheckerLogicPancakeswap = reg
            .logics
            .priceCheckerLogicPancakeswap ==
            address(0) ||
            (test && reg.logics.priceCheckerLogicPancakeswap != address(1))
            ? address(
                new PriceCheckerLogicPancakeswap(
                    reg.dittoOracle,
                    address(reg.pancakeswapFactory)
                )
            )
            : reg.logics.priceCheckerLogicPancakeswap;

        reg.logics.priceDifferenceCheckerLogicPancakeswap = reg
            .logics
            .priceDifferenceCheckerLogicPancakeswap ==
            address(0) ||
            (test &&
                reg.logics.priceDifferenceCheckerLogicPancakeswap != address(1))
            ? address(
                new PriceDifferenceCheckerLogicPancakeswap(
                    reg.dittoOracle,
                    address(reg.pancakeswapFactory)
                )
            )
            : reg.logics.priceDifferenceCheckerLogicPancakeswap;

        // aave + uni
        reg.logics.deltaNeutralStrategyLogic = reg
            .logics
            .deltaNeutralStrategyLogic ==
            address(0) ||
            (test && reg.logics.deltaNeutralStrategyLogic != address(1))
            ? address(
                new DeltaNeutralStrategyLogic(
                    reg.aaveAddressesProvider,
                    reg.uniswapFactory,
                    reg.uniswapNFTPositionManager,
                    reg.wrappedNative,
                    reg.uniswapRouter
                )
            )
            : reg.logics.deltaNeutralStrategyLogic;

        // aave
        reg.logics.aaveCheckerLogic = reg.logics.aaveCheckerLogic ==
            address(0) ||
            (test && reg.logics.aaveCheckerLogic != address(1))
            ? address(new AaveCheckerLogic(reg.aaveAddressesProvider))
            : reg.logics.aaveCheckerLogic;

        reg.logics.aaveActionLogic = reg.logics.aaveActionLogic == address(0) ||
            (test && reg.logics.aaveActionLogic != address(1))
            ? address(
                new AaveActionLogic(
                    reg.aaveAddressesProvider,
                    reg.uniswapRouter
                )
            )
            : reg.logics.aaveActionLogic;

        // bridges
        if (prod) {
            console.log(
                "dittoBridgeReceiverProd",
                address(reg.dittoBridgeReceiverProd)
            );
            reg.logics.stargateLogicProd = reg.logics.stargateLogicProd ==
                address(0)
                ? address(
                    new StargateLogic(
                        reg.stargateRouter,
                        address(reg.dittoBridgeReceiverProd)
                    )
                )
                : reg.logics.stargateLogicProd;

            reg.logics.layerZeroLogicProd = reg.logics.layerZeroLogicProd ==
                address(0)
                ? address(
                    new LayerZeroLogic(
                        reg.layerZeroEndpoint,
                        address(reg.dittoBridgeReceiverProd)
                    )
                )
                : reg.logics.layerZeroLogicProd;
        } else {
            console.log(
                "dittoBridgeReceiver",
                address(reg.dittoBridgeReceiver)
            );
            reg.logics.stargateLogic = reg.logics.stargateLogic == address(0)
                ? address(
                    new StargateLogic(
                        reg.stargateRouter,
                        address(reg.dittoBridgeReceiver)
                    )
                )
                : reg.logics.stargateLogic;

            reg.logics.layerZeroLogic = reg.logics.layerZeroLogic == address(0)
                ? address(
                    new LayerZeroLogic(
                        reg.layerZeroEndpoint,
                        address(reg.dittoBridgeReceiver)
                    )
                )
                : reg.logics.layerZeroLogic;
        }

        reg.logics.celerCircleBridgeLogic = reg.logics.celerCircleBridgeLogic ==
            address(0)
            ? address(
                new CelerCircleBridgeLogic(reg.celerCircleBridgeProxy, reg.usdc)
            )
            : reg.logics.celerCircleBridgeLogic;

        // uniswap dex checker
        reg.logics.uniswapDexCheckerLogic = reg.logics.uniswapDexCheckerLogic ==
            address(0) ||
            test
            ? address(
                new DexCheckerLogicUniswap(
                    reg.uniswapFactory,
                    reg.uniswapNFTPositionManager
                )
            )
            : reg.logics.uniswapDexCheckerLogic;

        reg.logics.pancakeswapDexCheckerLogic = reg
            .logics
            .pancakeswapDexCheckerLogic ==
            address(0) ||
            (test && reg.logics.pancakeswapDexCheckerLogic != address(1))
            ? address(
                new DexCheckerLogicPancakeswap(
                    reg.pancakeswapFactory,
                    reg.pancakeswapNFTPositionManager
                )
            )
            : reg.logics.pancakeswapDexCheckerLogic;

        return reg;
    }

    function deployAndAddModules(
        bool test,
        Registry.Contracts memory reg,
        address initialOwner
    ) public returns (Registry.Contracts memory) {
        if (prod) {} else {
            reg.partnerFeesContracts.partnerFees = (reg
                .partnerFeesContracts
                .partnerFees ==
                address(0) ||
                test)
                ? address(new PartnerFee(initialOwner))
                : reg.partnerFeesContracts.partnerFees;

            reg.modules.partnerFeeModule = (reg.modules.partnerFeeModule ==
                address(0) ||
                test)
                ? address(
                    new PartnerFeeModule(reg.partnerFeesContracts.partnerFees)
                )
                : reg.modules.partnerFeeModule;

            if (
                !ProtocolModuleList(reg.protocolModuleList).listedModule(
                    reg.modules.partnerFeeModule
                )
            ) {
                bytes4[] memory selectors = new bytes4[](1);
                selectors[0] = PartnerFeeModule.partnerFeeMulticall.selector;

                ProtocolModuleList(reg.protocolModuleList).addModule(
                    reg.modules.partnerFeeModule,
                    selectors
                );
            }
        }

        return reg;
    }

    // -----------------------------

    function _getData(
        Registry.Logics memory logics
    ) internal view returns (bytes4[] memory, address[] memory) {
        bytes4[] memory selectors = new bytes4[](250);
        address[] memory logicAddresses = new address[](250);

        uint256 i;
        uint256 j;

        // AA
        selectors[i++] = AccountAbstractionLogic.entryPointAA.selector;
        selectors[i++] = AccountAbstractionLogic.validateUserOp.selector;
        selectors[i++] = AccountAbstractionLogic.getNonceAA.selector;
        selectors[i++] = AccountAbstractionLogic.getDepositAA.selector;
        selectors[i++] = AccountAbstractionLogic.executeViaEntryPoint.selector;
        selectors[i++] = AccountAbstractionLogic.addDepositAA.selector;
        selectors[i++] = AccountAbstractionLogic.withdrawDepositToAA.selector;
        console2.log("accountAbstractionLogic", logics.accountAbstractionLogic);
        for (uint256 k; k < 7; ++k) {
            logicAddresses[j++] = logics.accountAbstractionLogic;
        }

        // common logic
        selectors[i++] = VersionUpgradeLogic.upgradeVersion.selector;
        if (prod) {
            console2.log(
                "versionUpgradeLogicProd",
                logics.versionUpgradeLogicProd
            );
            logicAddresses[j++] = logics.versionUpgradeLogicProd;
        } else {
            console2.log("versionUpgradeLogic", logics.versionUpgradeLogic);
            logicAddresses[j++] = logics.versionUpgradeLogic;
        }

        selectors[i++] = AccessControlLogic.initializeCreatorAndId.selector;
        selectors[i++] = AccessControlLogic.transferOwnership.selector;
        selectors[i++] = AccessControlLogic
            .setCrossChainLogicInactiveStatus
            .selector;
        selectors[i++] = AccessControlLogic.crossChainLogicIsActive.selector;
        selectors[i++] = AccessControlLogic.hasRole.selector;
        selectors[i++] = AccessControlLogic.creatorAndId.selector;
        selectors[i++] = AccessControlLogic.owner.selector;
        selectors[i++] = AccessControlLogic.isValidSignature.selector;
        selectors[i++] = AccessControlLogic.grantRole.selector;
        selectors[i++] = AccessControlLogic.getVaultProxyAdminAddress.selector;
        selectors[i++] = AccessControlLogic.revokeRole.selector;
        selectors[i++] = AccessControlLogic.renounceRole.selector;
        console2.log("accessControlLogic", logics.accessControlLogic);
        for (uint256 k; k < 12; ++k) {
            logicAddresses[j++] = logics.accessControlLogic;
        }

        selectors[i++] = EntryPointLogic.activateVault.selector;
        selectors[i++] = EntryPointLogic.deactivateVault.selector;
        selectors[i++] = EntryPointLogic.activateWorkflow.selector;
        selectors[i++] = EntryPointLogic.deactivateWorkflow.selector;
        selectors[i++] = EntryPointLogic.isActive.selector;
        selectors[i++] = EntryPointLogic.addWorkflowAndGelatoTask.selector;
        selectors[i++] = EntryPointLogic.addWorkflow.selector;
        selectors[i++] = EntryPointLogic.getNextWorkflowKey.selector;
        selectors[i++] = EntryPointLogic.getWorkflow.selector;
        selectors[i++] = EntryPointLogic.run.selector;
        selectors[i++] = EntryPointLogic.runGelato.selector;
        selectors[i++] = EntryPointLogic.canExecWorkflowCheck.selector;
        selectors[i++] = EntryPointLogic.dedicatedMessageSender.selector;
        selectors[i++] = EntryPointLogic.createTask.selector;
        selectors[i++] = EntryPointLogic.cancelTask.selector;
        selectors[i++] = EntryPointLogic.getTaskId.selector;
        if (prod) {
            console2.log("entryPointLogicProd", logics.entryPointLogicProd);
            for (uint256 k; k < 16; ++k) {
                logicAddresses[j++] = logics.entryPointLogicProd;
            }
        } else {
            console2.log("entryPointLogic", logics.entryPointLogic);
            for (uint256 k; k < 16; ++k) {
                logicAddresses[j++] = logics.entryPointLogic;
            }
        }

        selectors[i++] = ExecutionLogic.onERC721Received.selector;
        selectors[i++] = ExecutionLogic.execute.selector;
        selectors[i++] = ExecutionLogic.multicall.selector;
        selectors[i++] = ExecutionLogic.taxedMulticall.selector;
        if (prod) {
            console2.log("executionLogicProd", logics.executionLogicProd);
            for (uint256 k; k < 4; ++k) {
                logicAddresses[j++] = logics.executionLogicProd;
            }
        } else {
            console2.log("executionLogic", logics.executionLogic);
            for (uint256 k; k < 4; ++k) {
                logicAddresses[j++] = logics.executionLogic;
            }
        }

        selectors[i++] = VaultLogic.depositNative.selector;
        selectors[i++] = VaultLogic.withdrawNative.selector;
        selectors[i++] = VaultLogic.withdrawTotalNative.selector;
        selectors[i++] = VaultLogic.withdrawERC20.selector;
        selectors[i++] = VaultLogic.withdrawTotalERC20.selector;
        selectors[i++] = VaultLogic.depositERC20.selector;
        console2.log("vaultLogic", logics.vaultLogic);
        for (uint256 k; k < 6; ++k) {
            logicAddresses[j++] = logics.vaultLogic;
        }

        if (logics.nativeWrapper != address(1)) {
            selectors[i++] = NativeWrapper.wrapNative.selector;
            selectors[i++] = NativeWrapper.wrapNativeFromVaultBalance.selector;
            selectors[i++] = NativeWrapper.unwrapNative.selector;
            console2.log("nativeWrapper", logics.nativeWrapper);
            for (uint256 k; k < 3; ++k) {
                logicAddresses[j++] = logics.nativeWrapper;
            }
        }

        // dexes
        selectors[i++] = UniswapLogic.uniswapChangeTickRange.selector;
        selectors[i++] = UniswapLogic.uniswapMintNft.selector;
        selectors[i++] = UniswapLogic.uniswapAddLiquidity.selector;
        selectors[i++] = UniswapLogic.uniswapAutoCompound.selector;
        selectors[i++] = UniswapLogic.uniswapSwapExactInput.selector;
        selectors[i++] = UniswapLogic.uniswapSwapExactOutputSingle.selector;
        selectors[i++] = UniswapLogic.uniswapSwapToTargetR.selector;
        selectors[i++] = UniswapLogic.uniswapWithdrawPositionByShares.selector;
        selectors[i++] = UniswapLogic
            .uniswapWithdrawPositionByLiquidity
            .selector;
        selectors[i++] = UniswapLogic.uniswapCollectFees.selector;
        console2.log("uniswapLogic", logics.uniswapLogic);
        for (uint256 k; k < 10; ++k) {
            logicAddresses[j++] = logics.uniswapLogic;
        }

        if (logics.pancakeswapLogic != address(1)) {
            selectors[i++] = PancakeswapLogic
                .pancakeswapChangeTickRange
                .selector;
            selectors[i++] = PancakeswapLogic.pancakeswapMintNft.selector;
            selectors[i++] = PancakeswapLogic.pancakeswapAddLiquidity.selector;
            selectors[i++] = PancakeswapLogic.pancakeswapAutoCompound.selector;
            selectors[i++] = PancakeswapLogic
                .pancakeswapSwapExactInput
                .selector;
            selectors[i++] = PancakeswapLogic
                .pancakeswapSwapExactOutputSingle
                .selector;
            selectors[i++] = PancakeswapLogic.pancakeswapSwapToTargetR.selector;
            selectors[i++] = PancakeswapLogic
                .pancakeswapWithdrawPositionByShares
                .selector;
            selectors[i++] = PancakeswapLogic
                .pancakeswapWithdrawPositionByLiquidity
                .selector;
            selectors[i++] = PancakeswapLogic.pancakeswapCollectFees.selector;
            console2.log("pancakeswapLogic", logics.pancakeswapLogic);
            for (uint256 k; k < 10; ++k) {
                logicAddresses[j++] = logics.pancakeswapLogic;
            }
        }

        // time checker
        selectors[i++] = TimeCheckerLogic.timeCheckerInitialize.selector;
        selectors[i++] = TimeCheckerLogic.checkTime.selector;
        selectors[i++] = TimeCheckerLogic.checkTimeView.selector;
        selectors[i++] = TimeCheckerLogic.setTimePeriod.selector;
        selectors[i++] = TimeCheckerLogic.getLocalTimeCheckerStorage.selector;
        console2.log("timeCheckerLogic", logics.timeCheckerLogic);
        for (uint256 k; k < 5; ++k) {
            logicAddresses[j++] = logics.timeCheckerLogic;
        }

        // price checker uni
        selectors[i++] = PriceCheckerLogicUniswap
            .priceCheckerUniswapInitialize
            .selector;
        selectors[i++] = PriceCheckerLogicUniswap
            .uniswapCheckGTTargetRate
            .selector;
        selectors[i++] = PriceCheckerLogicUniswap
            .uniswapCheckGTETargetRate
            .selector;
        selectors[i++] = PriceCheckerLogicUniswap
            .uniswapCheckLTTargetRate
            .selector;
        selectors[i++] = PriceCheckerLogicUniswap
            .uniswapCheckLTETargetRate
            .selector;
        selectors[i++] = PriceCheckerLogicUniswap
            .uniswapChangeTokensAndFeePriceChecker
            .selector;
        selectors[i++] = PriceCheckerLogicUniswap
            .uniswapChangeTargetRate
            .selector;
        selectors[i++] = PriceCheckerLogicUniswap
            .uniswapGetLocalPriceCheckerStorage
            .selector;
        console2.log(
            "priceCheckerLogicUniswap",
            logics.priceCheckerLogicUniswap
        );
        for (uint256 k; k < 8; ++k) {
            logicAddresses[j++] = logics.priceCheckerLogicUniswap;
        }

        // price difference checker uni
        selectors[i++] = PriceDifferenceCheckerLogicUniswap
            .priceDifferenceCheckerUniswapInitialize
            .selector;
        selectors[i++] = PriceDifferenceCheckerLogicUniswap
            .uniswapCheckPriceDifference
            .selector;
        selectors[i++] = PriceDifferenceCheckerLogicUniswap
            .uniswapCheckPriceDifferenceView
            .selector;
        selectors[i++] = PriceDifferenceCheckerLogicUniswap
            .uniswapChangeTokensAndFeePriceDiffChecker
            .selector;
        selectors[i++] = PriceDifferenceCheckerLogicUniswap
            .uniswapChangePercentageDeviationE3
            .selector;
        selectors[i++] = PriceDifferenceCheckerLogicUniswap
            .uniswapGetLocalPriceDifferenceCheckerStorage
            .selector;
        console2.log(
            "priceDifferenceCheckerLogicUniswap",
            logics.priceDifferenceCheckerLogicUniswap
        );
        for (uint256 k; k < 6; ++k) {
            logicAddresses[j++] = logics.priceDifferenceCheckerLogicUniswap;
        }

        if (logics.priceCheckerLogicPancakeswap != address(1)) {
            selectors[i++] = PriceCheckerLogicPancakeswap
                .priceCheckerPancakeswapInitialize
                .selector;
            selectors[i++] = PriceCheckerLogicPancakeswap
                .pancakeswapCheckGTTargetRate
                .selector;
            selectors[i++] = PriceCheckerLogicPancakeswap
                .pancakeswapCheckGTETargetRate
                .selector;
            selectors[i++] = PriceCheckerLogicPancakeswap
                .pancakeswapCheckLTTargetRate
                .selector;
            selectors[i++] = PriceCheckerLogicPancakeswap
                .pancakeswapCheckLTETargetRate
                .selector;
            selectors[i++] = PriceCheckerLogicPancakeswap
                .pancakeswapChangeTokensAndFeePriceChecker
                .selector;
            selectors[i++] = PriceCheckerLogicPancakeswap
                .pancakeswapChangeTargetRate
                .selector;
            selectors[i++] = PriceCheckerLogicPancakeswap
                .pancakeswapGetLocalPriceCheckerStorage
                .selector;
            console2.log(
                "priceCheckerLogicPancakeswap",
                logics.priceCheckerLogicPancakeswap
            );
            for (uint256 k; k < 8; ++k) {
                logicAddresses[j++] = logics.priceCheckerLogicPancakeswap;
            }
        }

        if (logics.priceDifferenceCheckerLogicPancakeswap != address(1)) {
            // price difference checker cake
            selectors[i++] = PriceDifferenceCheckerLogicPancakeswap
                .priceDifferenceCheckerPancakeswapInitialize
                .selector;
            selectors[i++] = PriceDifferenceCheckerLogicPancakeswap
                .pancakeswapCheckPriceDifference
                .selector;
            selectors[i++] = PriceDifferenceCheckerLogicPancakeswap
                .pancakeswapCheckPriceDifferenceView
                .selector;
            selectors[i++] = PriceDifferenceCheckerLogicPancakeswap
                .pancakeswapChangeTokensAndFeePriceDiffChecker
                .selector;
            selectors[i++] = PriceDifferenceCheckerLogicPancakeswap
                .pancakeswapChangePercentageDeviationE3
                .selector;
            selectors[i++] = PriceDifferenceCheckerLogicPancakeswap
                .pancakeswapGetLocalPriceDifferenceCheckerStorage
                .selector;
            console2.log(
                "priceDifferenceCheckerLogicPancakeswap",
                logics.priceDifferenceCheckerLogicPancakeswap
            );
            for (uint256 k; k < 6; ++k) {
                logicAddresses[j++] = logics
                    .priceDifferenceCheckerLogicPancakeswap;
            }
        }

        if (logics.deltaNeutralStrategyLogic != address(1)) {
            // aave + uni
            selectors[i++] = DeltaNeutralStrategyLogic.initialize.selector;
            selectors[i++] = DeltaNeutralStrategyLogic
                .initializeWithMint
                .selector;
            selectors[i++] = DeltaNeutralStrategyLogic
                .healthFactorsAndNft
                .selector;
            selectors[i++] = DeltaNeutralStrategyLogic
                .getTotalSupplyTokenBalance
                .selector;
            selectors[i++] = DeltaNeutralStrategyLogic.setNewTargetHF.selector;
            selectors[i++] = DeltaNeutralStrategyLogic.deposit.selector;
            selectors[i++] = DeltaNeutralStrategyLogic.depositETH.selector;
            selectors[i++] = DeltaNeutralStrategyLogic.withdraw.selector;
            selectors[i++] = DeltaNeutralStrategyLogic.rebalance.selector;
            selectors[i++] = DeltaNeutralStrategyLogic.setNewNftId.selector;
            console2.log(
                "deltaNeutralStrategyLogic",
                logics.deltaNeutralStrategyLogic
            );
            for (uint256 k; k < 10; ++k) {
                logicAddresses[j++] = logics.deltaNeutralStrategyLogic;
            }
        }

        if (logics.aaveCheckerLogic != address(1)) {
            // aave checker logic
            selectors[i++] = AaveCheckerLogic.aaveCheckerInitialize.selector;
            selectors[i++] = AaveCheckerLogic.checkHF.selector;
            selectors[i++] = AaveCheckerLogic.setHFBoundaries.selector;
            selectors[i++] = AaveCheckerLogic.getHFBoundaries.selector;
            selectors[i++] = AaveCheckerLogic
                .getLocalAaveCheckerStorage
                .selector;
            console2.log("aaveCheckerLogic", logics.aaveCheckerLogic);
            for (uint256 k; k < 5; ++k) {
                logicAddresses[j++] = logics.aaveCheckerLogic;
            }
        }

        if (logics.aaveActionLogic != address(1)) {
            // aave action logic
            selectors[i++] = AaveActionLogic.borrowAaveAction.selector;
            selectors[i++] = AaveActionLogic.supplyAaveAction.selector;
            selectors[i++] = AaveActionLogic.repayAaveAction.selector;
            selectors[i++] = AaveActionLogic.withdrawAaveAction.selector;
            selectors[i++] = AaveActionLogic.emergencyRepayAave.selector;
            selectors[i++] = AaveActionLogic.executeOperation.selector;
            console2.log("aaveActionLogic", logics.aaveActionLogic);
            for (uint256 k; k < 6; ++k) {
                logicAddresses[j++] = logics.aaveActionLogic;
            }
        }

        if (logics.stargateLogic != address(1)) {
            // stargate
            selectors[i++] = StargateLogic.sendStargateMessage.selector;
            selectors[i++] = StargateLogic.stargateMultisender.selector;
            selectors[i++] = StargateLogic.stargateMulticall.selector;
            if (prod) {
                console.log("stargateLogicProd", logics.stargateLogicProd);
                for (uint256 k; k < 3; ++k) {
                    logicAddresses[j++] = logics.stargateLogicProd;
                }
            } else {
                console.log("stargateLogic", logics.stargateLogic);
                for (uint256 k; k < 3; ++k) {
                    logicAddresses[j++] = logics.stargateLogic;
                }
            }
        }

        // layer zero
        selectors[i++] = LayerZeroLogic.sendLayerZeroMessage.selector;
        selectors[i++] = LayerZeroLogic.layerZeroMulticall.selector;
        if (prod) {
            console.log("layerZeroLogicProd", logics.layerZeroLogicProd);
            logicAddresses[j++] = logics.layerZeroLogicProd;
            logicAddresses[j++] = logics.layerZeroLogicProd;
        } else {
            console.log("layerZeroLogic", logics.layerZeroLogic);
            logicAddresses[j++] = logics.layerZeroLogic;
            logicAddresses[j++] = logics.layerZeroLogic;
        }

        if (logics.celerCircleBridgeLogic != address(1)) {
            // celer circle
            selectors[i++] = CelerCircleBridgeLogic
                .sendCelerCircleMessage
                .selector;
            selectors[i++] = CelerCircleBridgeLogic
                .sendBatchCelerCircleMessage
                .selector;
            console.log(
                "celerCircleBridgeLogic",
                logics.celerCircleBridgeLogic
            );
            logicAddresses[j++] = logics.celerCircleBridgeLogic;
            logicAddresses[j++] = logics.celerCircleBridgeLogic;
        }

        // dex checker uniswap
        selectors[i++] = DexCheckerLogicUniswap
            .uniswapDexCheckerInitialize
            .selector;
        selectors[i++] = DexCheckerLogicUniswap
            .uniswapCheckOutOfTickRange
            .selector;
        selectors[i++] = DexCheckerLogicUniswap
            .uniswapCheckInTickRange
            .selector;
        selectors[i++] = DexCheckerLogicUniswap
            .uniswapCheckFeesExistence
            .selector;
        selectors[i++] = DexCheckerLogicUniswap
            .uniswapGetLocalDexCheckerStorage
            .selector;
        console2.log("uniswapDexCheckerLogic", logics.uniswapDexCheckerLogic);
        for (uint256 k; k < 5; ++k) {
            logicAddresses[j++] = logics.uniswapDexCheckerLogic;
        }

        if (logics.pancakeswapDexCheckerLogic != address(1)) {
            // dex checker pancakeswap
            selectors[i++] = DexCheckerLogicPancakeswap
                .pancakeswapDexCheckerInitialize
                .selector;
            selectors[i++] = DexCheckerLogicPancakeswap
                .pancakeswapCheckOutOfTickRange
                .selector;
            selectors[i++] = DexCheckerLogicPancakeswap
                .pancakeswapCheckInTickRange
                .selector;
            selectors[i++] = DexCheckerLogicPancakeswap
                .pancakeswapCheckFeesExistence
                .selector;
            selectors[i++] = DexCheckerLogicPancakeswap
                .pancakeswapGetLocalDexCheckerStorage
                .selector;
            console2.log(
                "pancakeswapDexCheckerLogic",
                logics.pancakeswapDexCheckerLogic
            );

            for (uint256 k; k < 5; ++k) {
                logicAddresses[j++] = logics.pancakeswapDexCheckerLogic;
            }
        }

        assembly {
            mstore(selectors, i)
            mstore(logicAddresses, j)
        }

        DeployEngine.quickSort(selectors, logicAddresses);

        return (selectors, logicAddresses);
    }
}
