// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/vault/interfaces/IEntryPointLogic.sol";
import "../src/vault/interfaces/IAccessControlLogic.sol";
import "../src/vault/interfaces/checkers/ITimeCheckerLogic.sol";
import "../src/vault/interfaces/IExecutionLogic.sol";
import "../src/IVaultFactory.sol";
import "../src/vault/interfaces/IVault.sol";

contract CallAddWorkflow is Script {

    IEntryPointLogic private entryPointLogic = IEntryPointLogic(0x1c9977D76B7d7E8dAf044878ecA400277B57C594);
    ITimeCheckerLogic private timeCheckerLogic = ITimeCheckerLogic(0xb4D5e2f534EC72FDfdBb4426F1785c7f97750675);
    //IExecutionLogic private executionLogic = IExecutionLogic(0xc29bc99C00E6Fea06AadB0677a0e01a7B8d41E43);
    IVaultFactory private vaultFactory = IVaultFactory(0xc01d969447cB30D92DE0D5b3145475bcaaFC8c65);
    IAccessControlLogic private accessControlLogic = IAccessControlLogic(0x7F37526006c14d251f6Ed5409E4cCb6d67f823f8);

    address private constant uniswapRouter = 0x8954AfA98594b838bda56FE4C12a09D7739D179b;
    address private constant WETH = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
    address private constant tokenOut = 0x5421838dfaC01bFc4f32D73600bcdddA3bF98697;
    
    address executor = 0x1C3f50CA4f8b96fAa6ab1020D9C54a44ADfAc814;
    
    bytes[] multicallData;
    
    function run() payable external {   
        vm.startBroadcast();
        
        //uint256 version = 2;
        //uint16 vaultId = 2; 
        address vaultAddress = 0x6AF2aeA882c8D5784732Bc8BCD333345B17598F8; //vaultFactory.deploy(version, vaultId);
 
        bytes4 swapSelector = bytes4(keccak256("swapExactETHForTokens(uint256,address[],address,uint256)"));
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = tokenOut;
        uint256 amountOutMin = 1;
        uint256 deadline = block.timestamp + 300;
        bytes memory swapData = abi.encodeWithSelector(swapSelector, amountOutMin, path, vaultAddress, deadline);

        IEntryPointLogic.Checker[] memory checkers = new IEntryPointLogic.Checker[](1);
        checkers[0] = IEntryPointLogic.Checker({
            data: abi.encode(deadline),
            viewData: "",
            storageRef: "",
            initData: ""
        });
        
        IEntryPointLogic.Action[] memory actions = new IEntryPointLogic.Action[](1);
        actions[0] = IEntryPointLogic.Action({
            data: swapData,
            storageRef: "",
            initData: ""
        });
        
        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflowAndGelatoTask,
                (checkers, actions, executor, 0)
            )
        );

        
        IExecutionLogic(vaultAddress).multicall(multicallData);

    }
}

// forge script script/CallAddWorkflow.s.sol:CallAddWorkflow --rpc-url $MUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $POL_API_KEY --verify -vv


