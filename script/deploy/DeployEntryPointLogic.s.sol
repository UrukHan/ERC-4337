// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {EntryPointLogic} from "../../src/vault/logics/EntryPointLogic.sol";
import {IAutomate} from "@gelato/contracts/integrations/Types.sol";
import {IProtocolFees} from "../../src/IProtocolFees.sol";

contract DeployEntryPointLogic is Script {

    function run() external returns (address) {

        address entryPointLogic = deployEntryPointLogic();
        return entryPointLogic;
    }

    function deployEntryPointLogic() internal returns (address) {

        vm.startBroadcast();
        EntryPointLogic entryPointLogic = new EntryPointLogic(IAutomate(0x2A6C106ae13B558BB9E2Ec64Bd2f1f7BEFF3A5E0),
                                                                IProtocolFees(0xB4d13F81864f99BdfFCCeE513803b0Be236d71D1));
        vm.stopBroadcast();
        return address(entryPointLogic);
    }
}


// forge script script/deploy/DeployEntryPointLogic.s.sol:DeployEntryPointLogic --rpc-url $MUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $POL_API_KEY --verify -vv
