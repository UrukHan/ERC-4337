// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {ProtocolModuleList} from "../../src/ProtocolModuleList.sol";

contract DeployProtocolModuleList is Script {

    function run() external returns (address) {

        address protocolModuleList = deployProtocolModuleList();
        return protocolModuleList;
    }

    function deployProtocolModuleList() internal returns (address) {

        vm.startBroadcast();
        ProtocolModuleList protocolModuleList = new ProtocolModuleList();
        vm.stopBroadcast();
        return address(protocolModuleList);
    }
}


// forge script script/deploy/DeployProtocolModuleList.s.sol:DeployProtocolModuleList --rpc-url $MUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $POL_API_KEY --verify -vv
