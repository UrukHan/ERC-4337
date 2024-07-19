// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {VaultProxyAdmin} from "../../src/VaultProxyAdmin.sol";

contract DeployProxyAndFactory is Script {
    function run() external {
        vm.startBroadcast();

        ProxyAdmin proxyAdmin = new ProxyAdmin();
        EmptyContract emptyContract = new EmptyContract();
        TransparentUpgradeableProxy tempProxy = new TransparentUpgradeableProxy(
            address(emptyContract),
            address(proxyAdmin),
            ""
        );
        VaultProxyAdmin vaultProxyAdmin = new VaultProxyAdmin(address(tempProxy));
        VaultFactory vaultFactory = new VaultFactory(0xA3ebcfDb171F2d7b22a155bDdE0bF231771d2efc, address(vaultProxyAdmin));
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(address(tempProxy));
        proxyAdmin.upgrade(proxy, address(vaultFactory));
        bytes memory data = abi.encodeWithSignature("initialize(address)", msg.sender);
        
        (bool success, ) = address(proxy).call(data);
        require(success, "Initialization failed");

        vm.stopBroadcast();
    }
}
contract EmptyContract {}

// forge script script/deploy/DeployProxyAndFactory.s.sol:DeployProxyAndFactory --rpc-url $MUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $POL_API_KEY --verify -vv
