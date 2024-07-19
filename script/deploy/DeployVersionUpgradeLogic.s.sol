// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {VersionUpgradeLogic} from "../../src/vault/logics/VersionUpgradeLogic.sol";
import {IVaultFactory} from "../../src//IVaultFactory.sol";

contract DeployVersionUpgradeLogic is Script {

    function run() external returns (address) {

        address versionUpgradeLogic = deployVersionUpgradeLogic();
        return versionUpgradeLogic;
    }

    function deployVersionUpgradeLogic() internal returns (address) {

        vm.startBroadcast();
        VersionUpgradeLogic versionUpgradeLogic = new VersionUpgradeLogic(IVaultFactory(0xc01d969447cB30D92DE0D5b3145475bcaaFC8c65));
        vm.stopBroadcast();
        return address(versionUpgradeLogic);
    }
}


// forge script script/deploy/DeployVersionUpgradeLogic.s.sol:DeployVersionUpgradeLogic --rpc-url $MUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $POL_API_KEY --verify -vv
