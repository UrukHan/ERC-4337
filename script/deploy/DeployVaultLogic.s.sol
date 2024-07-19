// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {VaultLogic} from "../../src/vault/logics/VaultLogic.sol";

contract DeployVaultLogic is Script {

    function run() external returns (address) {

        address vaultLogic = deployVaultLogic();
        return vaultLogic;
    }

    function deployVaultLogic() internal returns (address) {

        vm.startBroadcast();
        VaultLogic vaultLogic = new VaultLogic();
        vm.stopBroadcast();
        return address(vaultLogic);
    }
}


// forge script script/deploy/DeployVaultLogic.s.sol:DeployVaultLogic --rpc-url $MUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $POL_API_KEY --verify -vv
