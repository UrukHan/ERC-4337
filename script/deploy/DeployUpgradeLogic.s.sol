// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {UpgradeLogic} from "../../src/vault/UpgradeLogic.sol";

contract DeployUpgradeLogic is Script {

    function run() external returns (address) {

        address upgradeLogic = deployUpgradeLogic();
        return upgradeLogic;
    }

    function deployUpgradeLogic() internal returns (address) {

        vm.startBroadcast();
        UpgradeLogic upgradeLogic = new UpgradeLogic();
        vm.stopBroadcast();
        return address(upgradeLogic);
    }
}


// forge script script/deploy/DeployUpgradeLogic.s.sol:DeployUpgradeLogic --rpc-url $MUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $POL_API_KEY --verify -vv
