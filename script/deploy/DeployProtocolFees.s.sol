// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {ProtocolFees} from "../../src/ProtocolFees.sol";

contract DeployProtocolFees is Script {

    function run() external returns (address) {

        address protocolFees = deployProtocolFees();
        return protocolFees;
    }

    function deployProtocolFees() internal returns (address) {

        vm.startBroadcast();
        ProtocolFees protocolFees = new ProtocolFees(0x1C3f50CA4f8b96fAa6ab1020D9C54a44ADfAc814);
        vm.stopBroadcast();
        return address(protocolFees);
    }
}


// forge script script/deploy/DeployProtocolFees.s.sol:DeployProtocolFees --rpc-url $MUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $POL_API_KEY --verify -vv
