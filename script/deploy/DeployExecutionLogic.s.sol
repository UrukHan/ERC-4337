// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {ExecutionLogic} from "../../src/vault/logics/ExecutionLogic.sol";
import {IProtocolFees} from "../../src/IProtocolFees.sol";

contract DeployExecutionLogic is Script {

    function run() external returns (address) {

        address executionLogic = deployExecutionLogic();
        return executionLogic;
    }

    function deployExecutionLogic() internal returns (address) {

        vm.startBroadcast();
        ExecutionLogic executionLogic = new ExecutionLogic(IProtocolFees(0xB4d13F81864f99BdfFCCeE513803b0Be236d71D1));
        vm.stopBroadcast();
        return address(executionLogic);
    }
}


// forge script script/deploy/DeployExecutionLogic.s.sol:DeployExecutionLogic --rpc-url $MUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $POL_API_KEY --verify -vv
