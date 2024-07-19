// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IOwnable} from "../src/external/IOwnable.sol";

import {DittoBridgeReceiver} from "../src/DittoBridgeReceiver.sol";
import {IVaultFactory} from "../src/IVaultFactory.sol";
import {LayerZeroLogic, ILayerZeroLogic} from "../src/vault/logics/OurLogic/bridges/LayerZeroLogic.sol";
import {IAccessControlLogic} from "../src/vault/logics/AccessControlLogic.sol";
import {StargateLogic, IStargateLogic} from "../src/vault/logics/OurLogic/bridges/StargateLogic.sol";
import {VaultProxyAdmin} from "../src/VaultProxyAdmin.sol";
import {TransferHelper} from "../src/vault/libraries/utils/TransferHelper.sol";
import {VersionUpgradeLogic, IVersionUpgradeLogic} from "../src/vault/logics/VersionUpgradeLogic.sol";

import {FullDeploy, Registry} from "../script/FullDeploy.s.sol";

contract DittoBridgeReceiverTest is Test, FullDeploy {
    bool isTest = true;

    DittoBridgeReceiver dittoBridgeReceiver;
    Registry.Contracts reg;

    address vaultOwner = makeAddr("VAULT_OWNER");
    address arbitraryUser = makeAddr("ARBITRARY_USER");

    IVaultFactory vaultFactory;

    address vaultAddress;

    // mainnet USDT
    address usdtAddress = 0x55d398326f99059fF775485246999027B3197955;
    address donor = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    function setUp() external {
        vm.createSelectFork(vm.envString("BNB_RPC_URL"));

        vm.startPrank(vaultOwner);
        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );

        uint256 nonce = vm.getNonce(vaultOwner);

        address _vFactory = vm.computeCreateAddress(vaultOwner, nonce + 6);

        reg.logics.versionUpgradeLogic = address(
            new VersionUpgradeLogic(IVaultFactory(_vFactory))
        );

        reg.vaultProxyAdmin = new VaultProxyAdmin(_vFactory);

        address bReciever = vm.computeCreateAddress(vaultOwner, nonce + 8);

        reg.logics.stargateLogic = address(
            new StargateLogic(reg.stargateRouter, bReciever)
        );

        reg.logics.layerZeroLogic = address(
            new LayerZeroLogic(reg.layerZeroEndpoint, bReciever)
        );

        (vaultFactory, ) = addImplementation(reg, isTest, vaultOwner);

        dittoBridgeReceiver = new DittoBridgeReceiver(
            address(vaultFactory),
            vaultOwner
        );

        dittoBridgeReceiver.setBridgeContracts(
            reg.stargateRouter,
            reg.layerZeroEndpoint
        );

        vaultFactory.setBridgeReceiverContract(address(dittoBridgeReceiver));

        vaultAddress = vaultFactory.predictDeterministicVaultAddress(
            vaultOwner,
            1
        );

        vm.stopPrank();

        deal(address(dittoBridgeReceiver), 1e18);
        deal(address(vaultAddress), 1e18);
        vm.prank(donor);
        (bool success, ) = usdtAddress.call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                address(dittoBridgeReceiver),
                1e18
            )
        );

        require(success);

        vm.prank(donor);
        (success, ) = usdtAddress.call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                vaultAddress,
                1e18
            )
        );

        require(success);
    }

    function test_dittoLayerZeroReceiver_shouldCorrectlySetVariables()
        external
    {
        assertEq(dittoBridgeReceiver.owner(), vaultOwner);
        assertEq(
            address(dittoBridgeReceiver.vaultFactory()),
            address(vaultFactory)
        );
        assertEq(dittoBridgeReceiver.stargateComposer(), reg.stargateRouter);
        assertEq(
            dittoBridgeReceiver.layerZeroEndpoint(),
            reg.layerZeroEndpoint
        );
    }

    function test_dittoLayerZeroReceiver_withdrawToken_accessControl()
        external
    {
        vm.prank(arbitraryUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOwnable.Ownable_SenderIsNotOwner.selector,
                arbitraryUser
            )
        );
        dittoBridgeReceiver.withdrawToken(address(0));

        vm.prank(arbitraryUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOwnable.Ownable_SenderIsNotOwner.selector,
                arbitraryUser
            )
        );
        dittoBridgeReceiver.withdrawToken(usdtAddress);
    }

    event TransferHelperTransfer(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 value
    );

    function test_dittoLayerZeroReceiver_withdrawToken_shouldWithdrawTokens()
        external
    {
        assertEq(address(dittoBridgeReceiver).balance, 1e18);

        vm.startPrank(vaultOwner);
        vm.expectEmit();
        emit TransferHelperTransfer(
            address(0),
            address(dittoBridgeReceiver),
            vaultOwner,
            1e18
        );
        dittoBridgeReceiver.withdrawToken(address(0));

        assertEq(address(dittoBridgeReceiver).balance, 0);

        (, bytes memory data) = usdtAddress.staticcall(
            abi.encodeWithSignature(
                "balanceOf(address)",
                address(dittoBridgeReceiver)
            )
        );

        assertEq(abi.decode(data, (uint256)), 1e18);

        vm.expectEmit();
        emit TransferHelperTransfer(
            usdtAddress,
            address(dittoBridgeReceiver),
            vaultOwner,
            1e18
        );
        dittoBridgeReceiver.withdrawToken(usdtAddress);

        vm.stopPrank();

        (, data) = usdtAddress.staticcall(
            abi.encodeWithSignature(
                "balanceOf(address)",
                address(dittoBridgeReceiver)
            )
        );

        assertEq(abi.decode(data, (uint256)), 0);
    }

    function test_dittoStargateReceiver_sgReceive_shouldRevertIfSenderIsNotStargateRouter()
        external
    {
        vm.prank(arbitraryUser);
        vm.expectRevert(
            DittoBridgeReceiver
                .DittoBridgeReciever_OnlyStargateComposerCanCallThisMethod
                .selector
        );
        dittoBridgeReceiver.sgReceive(
            0,
            bytes(""),
            0,
            address(0),
            0,
            bytes("")
        );
    }

    function test_dittoLayerZeroReceiver_lzReceive_shouldRevertIfSenderIsNotLayerZeroEndpoint()
        external
    {
        vm.prank(arbitraryUser);
        vm.expectRevert(
            DittoBridgeReceiver
                .DittoBridgeReciever_OnlyLayerZeroEndpointCanCallThisMethod
                .selector
        );
        dittoBridgeReceiver.lzReceive(0, bytes(""), 0, bytes(""));
    }

    event VaultCreated(
        address indexed creator,
        address indexed vault,
        uint16 vaultId
    );

    function test_dittoStargateReceiver_sgReceive_shouldDeployNewVaultIfNeccessary()
        external
    {
        bytes[] memory mData = new bytes[](0);

        vm.prank(reg.stargateRouter);
        vm.expectEmit();
        emit VaultCreated(vaultOwner, vaultAddress, 1);
        dittoBridgeReceiver.sgReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress),
            0, // nonce
            usdtAddress, // token
            0, // amount
            abi.encode(
                vaultOwner,
                1,
                1,
                abi.encodeCall(IStargateLogic.stargateMulticall, (0, mData))
            ) // payload
        );
    }

    function test_dittoStargateReceiver_sgReceive_shouldRevertIfDeployIsReverted()
        external
    {
        bytes[] memory mData = new bytes[](0);

        vm.prank(reg.stargateRouter);
        vm.expectRevert(
            IVaultFactory.VaultFactory_VersionDoesNotExist.selector
        );
        dittoBridgeReceiver.sgReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress),
            0, // nonce
            usdtAddress, // token
            0, // amount
            abi.encode(
                vaultOwner,
                2,
                1,
                abi.encodeCall(IStargateLogic.stargateMulticall, (0, mData))
            ) // payload
        );
    }

    function test_dittoLayerZeroReceiver_lzReceive_shouldDeployNewVaultIfNeccessary()
        external
    {
        bytes[] memory mData = new bytes[](0);

        vm.prank(reg.layerZeroEndpoint);
        vm.expectEmit();
        emit VaultCreated(vaultOwner, vaultAddress, 1);
        dittoBridgeReceiver.lzReceive(
            109,
            abi.encodePacked(vaultAddress, dittoBridgeReceiver),
            1212,
            abi.encode(
                vaultOwner,
                1,
                1,
                abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (mData))
            )
        );
    }

    function test_dittoLayerZeroReceiver_lzReceive_shouldRevertIfDeployIsReverted()
        external
    {
        bytes[] memory mData = new bytes[](0);

        vm.prank(reg.layerZeroEndpoint);
        vm.expectRevert(
            IVaultFactory.VaultFactory_VersionDoesNotExist.selector
        );
        dittoBridgeReceiver.lzReceive(
            109,
            abi.encodePacked(vaultAddress, dittoBridgeReceiver),
            1212,
            abi.encode(
                vaultOwner,
                2,
                1,
                abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (mData))
            )
        );
    }

    function test_dittoStargateReceiver_sgReceive_shouldSendMultisenderIfConditionsTrue()
        external
    {
        bytes[] memory mData = new bytes[](1);

        address[] memory recipients = new address[](1);
        uint256[] memory shares = new uint256[](1);

        recipients[0] = vaultOwner;
        shares[0] = 1e18; // 100%

        IStargateLogic.MultisenderParams memory mParams;
        mParams.dstChainId = 109; // polygon
        mParams.srcPoolId = 2; // usdt
        mParams.dstPoolId = 2; // usdt
        mParams.slippageE18 = 0.995e18; // 0.5%
        mParams.recipients = recipients;
        mParams.tokenShares = shares;

        mData[0] = abi.encodeCall(
            IStargateLogic.stargateMultisender,
            (0, mParams)
        );

        vm.prank(reg.stargateRouter);
        vm.expectEmit();
        emit VaultCreated(vaultOwner, vaultAddress, 1);
        dittoBridgeReceiver.sgReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress),
            12121, // nonce
            usdtAddress, // token
            1e18, // amount
            abi.encode(
                vaultOwner,
                1,
                1,
                abi.encodeCall(IStargateLogic.stargateMulticall, (0, mData))
            ) // payload
        );
    }

    function test_dittoLayerZeroReceiver_lzReceive_shouldSendMessageIfConditionsTrue()
        external
    {
        (, bytes memory data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", vaultAddress)
        );

        assertEq(abi.decode(data, (uint256)), 1e18);

        vm.prank(vaultOwner);
        vaultFactory.deploy(1, 1);

        bytes[] memory mData = new bytes[](1);

        mData[0] = abi.encodeWithSignature(
            "withdrawERC20(address,address,uint256)",
            usdtAddress,
            vaultOwner,
            1e18
        );

        vm.prank(reg.layerZeroEndpoint);
        dittoBridgeReceiver.lzReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress, dittoBridgeReceiver),
            12121, // nonce
            abi.encode(
                vaultOwner,
                1,
                1,
                abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (mData))
            ) // payload
        );

        (, data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", vaultAddress)
        );

        assertEq(abi.decode(data, (uint256)), 0);
    }

    event DittoBridgeReceiverRevertData(
        address indexed vaultAddress,
        bytes payload,
        bytes reason
    );

    function test_dittoStargateReceiver_sgReceive_shouldEmitEventIfCallReverted()
        external
    {
        bytes[] memory mData = new bytes[](1);

        address[] memory recipients = new address[](1);
        uint256[] memory shares = new uint256[](1);

        recipients[0] = vaultOwner;
        shares[0] = 1.1e18; // 110%

        IStargateLogic.MultisenderParams memory mParams;
        mParams.dstChainId = 109; // polygon
        mParams.srcPoolId = 2; // usdt
        mParams.dstPoolId = 2; // usdt
        mParams.slippageE18 = 0.995e18; // 0.5%
        mParams.recipients = recipients;
        mParams.tokenShares = shares;

        mData[0] = abi.encodeCall(
            IStargateLogic.stargateMultisender,
            (0, mParams)
        );

        vm.prank(reg.stargateRouter);
        vm.expectEmit();
        emit DittoBridgeReceiverRevertData(
            vaultAddress,
            abi.encodeCall(IStargateLogic.stargateMulticall, (0, mData)),
            abi.encodeWithSignature(
                "Error(string)",
                "BEP20: transfer amount exceeds allowance"
            )
        );
        dittoBridgeReceiver.sgReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress),
            12121, // nonce
            usdtAddress, // token
            1e18, // amount
            abi.encode(
                vaultOwner,
                1,
                1,
                abi.encodeCall(IStargateLogic.stargateMulticall, (0, mData))
            ) // payload
        );
    }

    function test_dittoLayerZeroReceiver_lzReceive_shouldEmitEventIfCallReverted()
        external
    {
        vm.prank(vaultOwner);
        vaultFactory.deploy(1, 1);

        bytes[] memory mData = new bytes[](1);

        mData[0] = abi.encodeWithSignature(
            "withdrawERC20(address,address,uint256)",
            usdtAddress,
            10e18,
            vaultOwner
        );

        vm.prank(reg.layerZeroEndpoint);
        vm.expectEmit();
        emit DittoBridgeReceiverRevertData(
            vaultAddress,
            abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (mData)),
            abi.encodeWithSelector(
                TransferHelper.TransferHelper_SafeTransferError.selector
            )
        );
        dittoBridgeReceiver.lzReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress),
            12121, // nonce
            abi.encode(
                vaultOwner,
                1,
                1,
                abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (mData))
            ) // payload
        );
    }

    function test_dittoStargateReceiver_sgReceive_shouldJustTransferTokensToSrcChainOwnerIfDstVaultAndSrcVaultAreNotTheSame()
        external
    {
        bytes[] memory mData = new bytes[](1);

        address[] memory recipients = new address[](1);
        uint256[] memory shares = new uint256[](1);

        (, bytes memory data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", arbitraryUser)
        );

        assertEq(abi.decode(data, (uint256)), 0);

        recipients[0] = arbitraryUser;
        shares[0] = 1e18; // 100%

        IStargateLogic.MultisenderParams memory mParams;
        mParams.dstChainId = 109; // polygon
        mParams.srcPoolId = 2; // usdt
        mParams.dstPoolId = 2; // usdt
        mParams.slippageE18 = 0.995e18; // 0.5%
        mParams.recipients = recipients;
        mParams.tokenShares = shares;

        mData[0] = abi.encodeCall(
            IStargateLogic.stargateMultisender,
            (0, mParams)
        );

        vm.prank(reg.stargateRouter);
        dittoBridgeReceiver.sgReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress),
            12121, // nonce
            usdtAddress, // token
            1e18, // amount
            abi.encode(
                arbitraryUser,
                1,
                1,
                abi.encodeCall(IStargateLogic.stargateMulticall, (0, mData))
            ) // payload
        );

        (, data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", arbitraryUser)
        );

        assertEq(abi.decode(data, (uint256)), 1e18);
    }

    event LayerZeroWrongRecipient(
        address srcVaultAddress,
        address dstVaultAddress
    );

    function test_dittoLayerZeroReceiver_lzReceive_shouldEmitEventIfDstVaultAndSrcVaultAreNotTheSame()
        external
    {
        bytes[] memory mData = new bytes[](1);

        mData[0] = abi.encodeWithSignature(
            "withdrawERC20(address,address,uint256)",
            usdtAddress,
            10e18,
            vaultOwner
        );

        address wrongVault = vaultFactory.predictDeterministicVaultAddress(
            arbitraryUser,
            1
        );

        vm.prank(reg.layerZeroEndpoint);
        vm.expectEmit();
        emit LayerZeroWrongRecipient(vaultAddress, wrongVault);
        dittoBridgeReceiver.lzReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress),
            12121, // nonce
            abi.encode(
                arbitraryUser,
                1,
                1,
                abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (mData))
            ) // payload
        );
    }

    function test_dittoStargateReceiver_sgReceive_shouldJustTransferTokensToDstVaultIfDstOwnerIsNotEqualSrcOwner()
        external
    {
        vm.prank(vaultOwner);
        vaultFactory.deploy(0, 1);

        vm.prank(vaultOwner);
        (bool success, ) = vaultAddress.call(
            abi.encodeWithSignature("transferOwnership(address)", arbitraryUser)
        );
        require(success);

        address[] memory recipients = new address[](1);
        uint256[] memory shares = new uint256[](1);

        (, bytes memory data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", vaultAddress)
        );

        assertEq(abi.decode(data, (uint256)), 1e18);

        bytes[] memory mData = new bytes[](1);

        {
            recipients[0] = arbitraryUser;
            shares[0] = 1e18; // 100%

            IStargateLogic.MultisenderParams memory mParams;
            mParams.dstChainId = 109; // polygon
            mParams.srcPoolId = 2; // usdt
            mParams.dstPoolId = 2; // usdt
            mParams.slippageE18 = 0.995e18; // 0.5%
            mParams.recipients = recipients;
            mParams.tokenShares = shares;

            mData[0] = abi.encodeCall(
                IStargateLogic.stargateMultisender,
                (0, mParams)
            );
        }

        vm.prank(reg.stargateRouter);
        vm.expectEmit();
        emit DittoBridgeReceiverRevertData(
            vaultAddress,
            abi.encodeCall(IStargateLogic.stargateMulticall, (0, mData)),
            abi.encodePacked(
                IStargateLogic
                    .StargateLogic_VaultCannotUseCrossChainLogic
                    .selector
            )
        );
        dittoBridgeReceiver.sgReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress),
            12121, // nonce
            usdtAddress, // token
            1e18, // amount
            abi.encode(
                vaultOwner,
                1,
                1,
                abi.encodeCall(IStargateLogic.stargateMulticall, (0, mData))
            ) // payload
        );

        (, data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", vaultAddress)
        );

        assertEq(abi.decode(data, (uint256)), 2e18);
    }

    event BridgeReceiverDstVaultIsUnaccessibleForCrossChainCall(
        address dstVaultAddress
    );

    function test_dittoLayerZeroReceiver_lzReceive_shouldEmitEventIfDstOwnerIsNotEqualSrcOwner()
        external
    {
        vm.prank(vaultOwner);
        vaultFactory.deploy(1, 1);

        bytes[] memory mData = new bytes[](1);

        vm.prank(vaultOwner);
        (bool success, ) = vaultAddress.call(
            abi.encodeWithSignature("transferOwnership(address)", arbitraryUser)
        );
        require(success);

        mData[0] = abi.encodeWithSignature(
            "withdrawERC20(address,address,uint256)",
            usdtAddress,
            10e18,
            vaultOwner
        );
        vm.prank(reg.layerZeroEndpoint);
        vm.expectEmit();
        emit DittoBridgeReceiverRevertData(
            vaultAddress,
            abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (mData)),
            abi.encodePacked(
                ILayerZeroLogic
                    .LayerZeroLogic_VaultCannotUseCrossChainLogic
                    .selector
            )
        );
        dittoBridgeReceiver.lzReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress),
            12121, // nonce
            abi.encode(
                vaultOwner,
                1,
                1,
                abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (mData))
            ) // payload
        );
    }

    event ImplementationChanged(address newImplementation);

    function test_dittoStargateReceiver_sgReceive_crossChainUpgrade() external {
        vm.prank(vaultOwner);
        vaultFactory.addNewImplementation(address(1));

        vm.prank(vaultOwner);
        vaultFactory.deploy(1, 1);

        bytes[] memory mData = new bytes[](1);

        mData[0] = abi.encodeCall(IVersionUpgradeLogic.upgradeVersion, (2));

        vm.prank(reg.stargateRouter);
        vm.expectEmit();
        emit ImplementationChanged(address(1));
        dittoBridgeReceiver.sgReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress),
            12121, // nonce
            usdtAddress, // token
            1e18, // amount
            abi.encode(
                vaultOwner,
                1,
                1,
                abi.encodeCall(IStargateLogic.stargateMulticall, (0, mData))
            ) // payload
        );
    }

    function test_dittoLayerZeroReceiver_lzReceive_crossChainUpgrade()
        external
    {
        vm.prank(vaultOwner);
        vaultFactory.addNewImplementation(address(1));

        vm.prank(vaultOwner);
        vaultFactory.deploy(1, 1);

        bytes[] memory mData = new bytes[](1);

        mData[0] = abi.encodeCall(IVersionUpgradeLogic.upgradeVersion, (2));

        vm.prank(reg.layerZeroEndpoint);
        vm.expectEmit();
        emit ImplementationChanged(address(1));
        dittoBridgeReceiver.lzReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress),
            12121, // nonce
            abi.encode(
                vaultOwner,
                1,
                1,
                abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (mData))
            ) // payload
        );
    }

    function test_dittoStargateReceiver_sgReceive_crossChainFlagFalse()
        external
    {
        vm.prank(vaultOwner);
        vaultFactory.deploy(0, 1);

        vm.prank(vaultAddress);
        IAccessControlLogic(vaultAddress).setCrossChainLogicInactiveStatus(
            true
        );

        address[] memory recipients = new address[](1);
        uint256[] memory shares = new uint256[](1);

        (, bytes memory data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", vaultAddress)
        );

        assertEq(abi.decode(data, (uint256)), 1e18);

        bytes[] memory mData = new bytes[](1);

        {
            recipients[0] = arbitraryUser;
            shares[0] = 1e18; // 100%

            IStargateLogic.MultisenderParams memory mParams;
            mParams.dstChainId = 109; // polygon
            mParams.srcPoolId = 2; // usdt
            mParams.dstPoolId = 2; // usdt
            mParams.slippageE18 = 0.995e18; // 0.5%
            mParams.recipients = recipients;
            mParams.tokenShares = shares;

            mData[0] = abi.encodeCall(
                IStargateLogic.stargateMultisender,
                (0, mParams)
            );
        }

        vm.prank(reg.stargateRouter);
        vm.expectEmit();
        emit DittoBridgeReceiverRevertData(
            vaultAddress,
            abi.encodeCall(IStargateLogic.stargateMulticall, (0, mData)),
            abi.encodePacked(
                IStargateLogic
                    .StargateLogic_VaultCannotUseCrossChainLogic
                    .selector
            )
        );
        dittoBridgeReceiver.sgReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress),
            12121, // nonce
            usdtAddress, // token
            1e18, // amount
            abi.encode(
                vaultOwner,
                1,
                1,
                abi.encodeCall(IStargateLogic.stargateMulticall, (0, mData))
            ) // payload
        );

        (, data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", vaultAddress)
        );

        assertEq(abi.decode(data, (uint256)), 2e18);
    }

    function test_dittoLayerZeroReceiver_lzReceive_crossChainFlagFalse()
        external
    {
        vm.prank(vaultOwner);
        vaultFactory.deploy(1, 1);

        bytes[] memory mData = new bytes[](1);

        vm.prank(vaultAddress);
        IAccessControlLogic(vaultAddress).setCrossChainLogicInactiveStatus(
            true
        );

        mData[0] = abi.encodeWithSignature(
            "withdrawERC20(address,address,uint256)",
            usdtAddress,
            10e18,
            vaultOwner
        );
        vm.prank(reg.layerZeroEndpoint);
        vm.expectEmit();
        emit DittoBridgeReceiverRevertData(
            vaultAddress,
            abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (mData)),
            abi.encodePacked(
                ILayerZeroLogic
                    .LayerZeroLogic_VaultCannotUseCrossChainLogic
                    .selector
            )
        );
        dittoBridgeReceiver.lzReceive(
            109, // src chainId
            abi.encodePacked(vaultAddress),
            12121, // nonce
            abi.encode(
                vaultOwner,
                1,
                1,
                abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (mData))
            ) // payload
        );
    }
}
