// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {AccessControlLogic} from "../../src/vault/logics/AccessControlLogic.sol";

contract DeployAccessControlLogic is Script {

    function run() external returns (address) {

        address accessControlLogic = deployAccessControlLogic();
        return accessControlLogic;
    }

    function deployAccessControlLogic() internal returns (address) {

        vm.startBroadcast();
        AccessControlLogic accessControlLogic = new AccessControlLogic();
        vm.stopBroadcast();
        return address(accessControlLogic);
    }
}


// forge script script/deploy/DeployAccessControlLogic.s.sol:DeployAccessControlLogic --rpc-url $MUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $POL_API_KEY --verify -vv
