// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";

import {VaultFactory} from "../src/VaultFactory.sol";
import {Registry} from "./Registry.sol";

contract ProxyVaultFactory is Script {
    function run(bool prod) external virtual {
        Registry.Contracts memory reg = Registry.contractsByChainId(
            block.chainid
        );

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        if (prod) {
            VaultFactory vaultFactory = new VaultFactory(
                reg.logics.vaultUpgradeLogic,
                address(reg.vaultProxyAdminProd)
            );

            reg.vaultFactoryProxyAdmin.upgrade(
                reg.vaultFactoryProxyProd,
                address(vaultFactory)
            );

            VaultFactory(address(reg.vaultFactoryProxy)).versions();
            // VaultFactory(address(reg.vaultFactoryProxyProd))
            // .setBridgeReceiverContract(
            // address(reg.dittoBridgeReceiverProd)
            // );
        } else {
            VaultFactory vaultFactory = new VaultFactory(
                reg.logics.vaultUpgradeLogic,
                address(reg.vaultProxyAdmin)
            );

            reg.vaultFactoryProxyAdmin.upgrade(
                reg.vaultFactoryProxy,
                address(vaultFactory)
            );

            VaultFactory(address(reg.vaultFactoryProxy)).versions();
            // VaultFactory(address(reg.vaultFactoryProxy))
            // .setBridgeReceiverContract(address(reg.dittoBridgeReceiver));
        }

        vm.stopBroadcast();
    }
}
