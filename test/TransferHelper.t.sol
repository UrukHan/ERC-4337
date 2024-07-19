// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {TransferHelper} from "../src/vault/libraries/utils/TransferHelper.sol";

contract MockTranferHelper {
    using TransferHelper for address;

    constructor() payable {}

    function transferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) external {
        TransferHelper.safeTransferFrom(token, from, to, value);
    }

    function transfer(address token, address to, uint256 value) external {
        TransferHelper.safeTransfer(token, to, value);
    }

    function approve(address token, address to, uint256 value) external {
        TransferHelper.safeApprove(token, to, value);
    }

    function getBalance(
        address token,
        address account
    ) external view returns (uint256) {
        return TransferHelper.safeGetBalance(token, account);
    }

    function transferNative(address to, uint256 value) external {
        TransferHelper.safeTransferNative(to, value);
    }
}

contract FakeERC20 {
    bool flagReturnZero;
    bool flagRevert;

    function setFlagReturnZero(bool value) external {
        flagReturnZero = value;
    }

    function setFlagRevert(bool value) external {
        flagRevert = value;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        from;
        to;
        value;

        flagReturnZero = flagReturnZero;
        flagRevert = flagRevert;

        if (flagReturnZero) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }

        if (flagRevert) {
            revert();
        }

        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        to;
        value;

        flagReturnZero = flagReturnZero;
        flagRevert = flagRevert;

        if (flagReturnZero) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }

        if (flagRevert) {
            revert();
        }

        return true;
    }

    mapping(address => mapping(address => uint256)) public allowance;

    function approve(address to, uint256 value) external returns (bool) {
        to;
        value;

        flagReturnZero = flagReturnZero;
        flagRevert = flagRevert;

        if (flagReturnZero) {
            allowance[msg.sender][to] = value;

            assembly ("memory-safe") {
                return(0, 0)
            }
        }

        if (flagRevert) {
            if (value == 0) {
                allowance[msg.sender][to] = value;
                flagRevert = false;
            } else {
                revert();
            }
        }

        allowance[msg.sender][to] = value;
        return true;
    }

    function balanceOf(address to) external view returns (uint256) {
        to;

        if (flagReturnZero) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }

        if (flagRevert) {
            revert();
        }

        return 1000;
    }
}

contract TransferHelperTest is Test {
    event TransferHelperTransfer(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 value
    );

    MockTranferHelper mock;
    FakeERC20 fakeToken;

    function setUp() external {
        mock = new MockTranferHelper{value: 1 ether}();
        fakeToken = new FakeERC20();
    }

    function test_transferHelper_safeTransferFrom_shouldEmitEvent() external {
        vm.expectEmit();

        emit TransferHelperTransfer(
            address(fakeToken),
            address(this),
            address(1),
            1 ether
        );

        mock.transferFrom(
            address(fakeToken),
            address(this),
            address(1),
            1 ether
        );

        // function return nothing (like USDT on eth mainnet)
        fakeToken.setFlagReturnZero(true);
        vm.expectEmit();

        emit TransferHelperTransfer(
            address(fakeToken),
            address(this),
            address(1),
            1 ether
        );

        mock.transferFrom(
            address(fakeToken),
            address(this),
            address(1),
            1 ether
        );
    }

    function test_transferHelper_safeTransferFrom_shouldRevert() external {
        fakeToken.setFlagRevert(true);
        vm.expectRevert(
            TransferHelper.TransferHelper_SafeTransferFromError.selector
        );
        mock.transferFrom(
            address(fakeToken),
            address(this),
            address(1),
            1 ether
        );
    }

    function test_transferHelper_safeTransfer_shouldEmitEvent() external {
        vm.expectEmit();

        emit TransferHelperTransfer(
            address(fakeToken),
            address(mock),
            address(1),
            1 ether
        );

        mock.transfer(address(fakeToken), address(1), 1 ether);

        // function return nothing (like USDT on eth mainnet)
        fakeToken.setFlagReturnZero(true);
        vm.expectEmit();

        emit TransferHelperTransfer(
            address(fakeToken),
            address(mock),
            address(1),
            1 ether
        );

        mock.transfer(address(fakeToken), address(1), 1 ether);
    }

    function test_transferHelper_safeTransfer_shouldRevert() external {
        fakeToken.setFlagRevert(true);
        vm.expectRevert(
            TransferHelper.TransferHelper_SafeTransferError.selector
        );
        mock.transfer(address(fakeToken), address(1), 1 ether);
    }

    function test_transferHelper_approve() external {
        assertEq(fakeToken.allowance(address(mock), address(1)), 0);

        mock.approve(address(fakeToken), address(1), 1 ether);
        assertEq(fakeToken.allowance(address(mock), address(1)), 1 ether);

        // function return nothing (like USDT on eth mainnet)
        fakeToken.setFlagReturnZero(true);

        mock.approve(address(fakeToken), address(1), 10 ether);

        assertEq(fakeToken.allowance(address(mock), address(1)), 10 ether);
    }

    function test_transferHelper_approve_USDTLikeApprove() external {
        // Should lower the allowance to 0 before raising it (like USDT on eth mainnet)
        assertEq(fakeToken.allowance(address(mock), address(1)), 0);
        mock.approve(address(fakeToken), address(1), 1 ether);
        assertEq(fakeToken.allowance(address(mock), address(1)), 1 ether);

        fakeToken.setFlagRevert(true);
        mock.approve(address(fakeToken), address(1), 10 ether);
        assertEq(fakeToken.allowance(address(mock), address(1)), 10 ether);
    }

    function test_transferHelper_safeTransferNative_shouldEmitEvent() external {
        vm.expectEmit();

        emit TransferHelperTransfer(
            address(0),
            address(mock),
            address(1),
            1 ether
        );

        mock.transferNative(address(1), 1 ether);
    }

    function test_transferHelper_safeTransferNative_shouldRevert() external {
        vm.expectRevert(
            TransferHelper.TransferHelper_SafeTransferNativeError.selector
        );
        mock.transferNative(address(this), 1 ether);
    }

    function test_transferHelper_safeGetBalance_shouldReturnValue() external {
        assertEq(mock.getBalance(address(fakeToken), address(1)), 1000);
    }

    function test_transferHelper_safeGetBalance_shouldRevert() external {
        fakeToken.setFlagReturnZero(true);
        vm.expectRevert(
            TransferHelper.TransferHelper_SafeGetBalanceError.selector
        );
        mock.getBalance(address(fakeToken), address(1));

        fakeToken.setFlagReturnZero(false);
        fakeToken.setFlagRevert(true);
        vm.expectRevert(
            TransferHelper.TransferHelper_SafeGetBalanceError.selector
        );
        mock.getBalance(address(fakeToken), address(1));
    }
}
