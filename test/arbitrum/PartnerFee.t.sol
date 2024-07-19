// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPartnerFee} from "../../src/vault/modules/interfaces/IPartnerFee.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract TestPartnerFee is Test, FullDeploy {
    bool isTest = true;

    Registry.Contracts reg;

    IPartnerFee partnerFee;

    address dittoController = makeAddr("ditto Controller");
    address partnerController = makeAddr("partner Controller");
    address user = makeAddr("user");

    function setUp() external {
        vm.createSelectFork(vm.envString("ARB_RPC_URL"));

        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );
        reg = deployAndAddModules(isTest, reg, dittoController);

        partnerFee = IPartnerFee(reg.partnerFeesContracts.partnerFees);
    }

    event AgreementUpdated(
        address newDittoController,
        address newPartnerController,
        address indexed newDittoReceiver,
        address indexed newPartnerReceiver,
        uint256 newPartnerPortionBPS
    );
    event NewFeeForToken(address indexed token, uint256 fee);
    event RewardWithdrawn(
        address indexed token,
        uint256 rewardPartner,
        uint256 rewardDitto
    );

    // =========================
    // Initialize
    // =========================

    function test_arb_partnerFee_initialize_accessControl() external {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(user);
        vm.expectRevert(
            IPartnerFee
                .PartnerFee_SenderMustBeOrDittoOwnerOrPartnerAddress
                .selector
        );
        partnerFee.initialize(user, user, user, user, 1e18, tokens, fees);
    }

    function test_arb_partnerFee_initialize_shouldRevertIfContractAlreadyInitialized()
        external
    {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(dittoController);
        partnerFee.initialize(
            dittoController,
            dittoController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        vm.prank(dittoController);
        vm.expectRevert(IPartnerFee.PartnerFee_AlreadyInitialized.selector);
        partnerFee.initialize(
            dittoController,
            dittoController,
            dittoController,
            dittoController,
            1e18,
            tokens,
            fees
        );
    }

    function test_arb_partnerFee_initialize_shouldRevertDuringParametersCheck()
        external
    {
        address[] memory tokens = new address[](1);
        uint256[] memory fees;

        vm.prank(dittoController);
        vm.expectRevert(
            IPartnerFee
                .PartnerFee_PartnerPartOfFeesCannotBeGreaterThan100Percents
                .selector
        );
        partnerFee.initialize(
            dittoController,
            dittoController,
            dittoController,
            dittoController,
            1.1e18,
            tokens,
            fees
        );

        vm.prank(dittoController);
        vm.expectRevert(IPartnerFee.PartnerFee_ArraysLengthNotMatch.selector);
        partnerFee.initialize(
            dittoController,
            dittoController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );
    }

    function test_arb_partnerFee_initialize_shouldCorrectlySetAgreement()
        external
    {
        address[] memory tokens = new address[](2);
        uint256[] memory fees = new uint256[](2);

        tokens[0] = address(1);
        tokens[1] = address(2);
        fees[0] = 123456;
        fees[1] = 789101;

        vm.prank(dittoController);
        vm.expectEmit();
        emit NewFeeForToken(address(1), 123456);
        vm.expectEmit();
        emit NewFeeForToken(address(2), 789101);
        vm.expectEmit();
        emit AgreementUpdated(
            dittoController,
            dittoController,
            dittoController,
            dittoController,
            0.5e18
        );
        partnerFee.initialize(
            dittoController,
            dittoController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        (address[] memory _tokens, uint256[] memory _fees) = partnerFee
            .getCurrentAgreement();

        for (uint256 i; i < 2; ++i) {
            assertEq(_tokens[i], tokens[i]);
            assertEq(_fees[i], _fees[i]);
        }

        (
            address _dittoController,
            address _partnerController,
            address _dittoReceiver,
            address _partnerReceiver,
            uint256 _partnerPortionBPS
        ) = partnerFee.getState();

        assertEq(_dittoController, dittoController);
        assertEq(_partnerController, dittoController);
        assertEq(_dittoReceiver, dittoController);
        assertEq(_partnerReceiver, dittoController);
        assertEq(_partnerPortionBPS, 0.5e18);

        assertEq(partnerFee.getFixFeesForPartnerByToken(address(1)), 123456);

        assertEq(partnerFee.getFixFeesForPartnerByToken(address(2)), 789101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPartnerFee.PartnerFee_TokenIsNotAllowed.selector,
                address(3)
            )
        );
        partnerFee.getFixFeesForPartnerByToken(address(3));
    }

    // =========================
    // proposeAgreement
    // =========================

    function test_arb_partnerFee_proposeAgreement_accessControl() external {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(user);
        vm.expectRevert(
            IPartnerFee
                .PartnerFee_SenderMustBeOrDittoOwnerOrPartnerAddress
                .selector
        );
        partnerFee.proposeAgreement(user, user, user, user, 1e18, tokens, fees);
    }

    function test_arb_partnerFee_proposeAgreement_shouldRevertIfContractIsNotInitialized()
        external
    {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(dittoController);
        vm.expectRevert(IPartnerFee.PartnerFee_NotInitialized.selector);
        partnerFee.proposeAgreement(user, user, user, user, 1e18, tokens, fees);
    }

    function test_arb_partnerFee_proposeAgreement_shouldRevertIfProposalAlreadyStarted()
        external
    {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(dittoController);
        partnerFee.initialize(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        vm.prank(dittoController);
        partnerFee.proposeAgreement(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        IPartnerFee.AgreementProposal memory agreementProposal = partnerFee
            .getAgreementProposal();

        assertEq(agreementProposal.newDittoController, dittoController);
        assertEq(agreementProposal.newPartnerController, partnerController);
        assertEq(agreementProposal.newDittoReceiver, dittoController);
        assertEq(agreementProposal.newPartnerReceiver, dittoController);
        assertEq(agreementProposal.newPartnerPortionBPS, 0.5e18);
        assertEq(agreementProposal.tokens.length, 0);
        assertEq(agreementProposal.fees.length, 0);
        assertEq(agreementProposal.proposalProvider, dittoController);
        assertEq(
            agreementProposal.agreementProposalHash,
            _hashProposal(
                dittoController,
                partnerController,
                dittoController,
                dittoController,
                0.5e18,
                tokens,
                fees
            )
        );

        vm.prank(dittoController);
        vm.expectRevert(IPartnerFee.PartnerFee_ProposalAlreadyStarted.selector);
        partnerFee.proposeAgreement(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.4e18,
            tokens,
            fees
        );
    }

    function test_arb_partnerFee_proposeAgreement_shouldSetAgreementIfControllersAreSame()
        external
    {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(dittoController);
        partnerFee.initialize(
            dittoController,
            dittoController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        tokens = new address[](2);
        fees = new uint256[](2);

        tokens[0] = address(1);
        tokens[1] = address(2);
        fees[0] = 123456;
        fees[1] = 789101;

        vm.prank(dittoController);
        vm.expectEmit();
        emit NewFeeForToken(address(1), 123456);
        vm.expectEmit();
        emit NewFeeForToken(address(2), 789101);
        vm.expectEmit();
        emit AgreementUpdated(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.4e18
        );
        partnerFee.proposeAgreement(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.4e18,
            tokens,
            fees
        );
    }

    function test_arb_partnerFee_proposeAgreement_shouldCreateNewProposal()
        external
    {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(dittoController);
        partnerFee.initialize(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        tokens = new address[](2);
        fees = new uint256[](2);

        tokens[0] = address(1);
        tokens[1] = address(2);
        fees[0] = 123456;
        fees[1] = 789101;

        vm.prank(dittoController);
        partnerFee.proposeAgreement(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.4e18,
            tokens,
            fees
        );

        IPartnerFee.AgreementProposal memory agreementProposal = partnerFee
            .getAgreementProposal();

        assertEq(agreementProposal.newDittoController, dittoController);
        assertEq(agreementProposal.newPartnerController, partnerController);
        assertEq(agreementProposal.newDittoReceiver, dittoController);
        assertEq(agreementProposal.newPartnerReceiver, dittoController);
        assertEq(agreementProposal.newPartnerPortionBPS, 0.4e18);
        assertEq(agreementProposal.tokens.length, 2);
        assertEq(agreementProposal.fees.length, 2);
        assertEq(agreementProposal.proposalProvider, dittoController);
        assertEq(
            agreementProposal.agreementProposalHash,
            _hashProposal(
                dittoController,
                partnerController,
                dittoController,
                dittoController,
                0.4e18,
                tokens,
                fees
            )
        );
    }

    // =========================
    // deleteProposal
    // =========================

    function test_arb_partnerFee_deleteProposal_accessControl() external {
        vm.prank(user);
        vm.expectRevert(
            IPartnerFee
                .PartnerFee_SenderMustBeOrDittoOwnerOrPartnerAddress
                .selector
        );
        partnerFee.deleteProposal();
    }

    function test_arb_partnerFee_deleteProposal_shouldRevertIfProposalNotStarted()
        external
    {
        vm.prank(dittoController);
        vm.expectRevert(IPartnerFee.PartnerFee_ProposalNotStarted.selector);
        partnerFee.deleteProposal();
    }

    function test_arb_partnerFee_deleteProposal_shouldRevertIfSenderForDeleteIsNotProposeProvider()
        external
    {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(dittoController);
        partnerFee.initialize(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        vm.prank(dittoController);
        partnerFee.proposeAgreement(
            dittoController,
            dittoController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        vm.prank(partnerController);
        vm.expectRevert(IPartnerFee.PartnerFee_WrongApproveSender.selector);
        partnerFee.deleteProposal();
    }

    function test_arb_partnerFee_deleteProposal_shouldSuccessfullyDeleteProposal()
        external
    {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(dittoController);
        partnerFee.initialize(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        tokens = new address[](2);
        fees = new uint256[](2);

        tokens[0] = address(1);
        tokens[1] = address(2);
        fees[0] = 123456;
        fees[1] = 789101;

        vm.prank(dittoController);
        partnerFee.proposeAgreement(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.4e18,
            tokens,
            fees
        );

        IPartnerFee.AgreementProposal memory agreementProposal = partnerFee
            .getAgreementProposal();

        assertEq(agreementProposal.newDittoController, dittoController);
        assertEq(agreementProposal.newPartnerController, partnerController);
        assertEq(agreementProposal.newDittoReceiver, dittoController);
        assertEq(agreementProposal.newPartnerReceiver, dittoController);
        assertEq(agreementProposal.newPartnerPortionBPS, 0.4e18);
        assertEq(agreementProposal.tokens.length, 2);
        assertEq(agreementProposal.fees.length, 2);
        assertEq(agreementProposal.proposalProvider, dittoController);
        assertEq(
            agreementProposal.agreementProposalHash,
            _hashProposal(
                dittoController,
                partnerController,
                dittoController,
                dittoController,
                0.4e18,
                tokens,
                fees
            )
        );

        vm.prank(dittoController);
        partnerFee.deleteProposal();

        agreementProposal = partnerFee.getAgreementProposal();

        assertEq(agreementProposal.newDittoController, address(0));
        assertEq(agreementProposal.newPartnerController, address(0));
        assertEq(agreementProposal.newDittoReceiver, address(0));
        assertEq(agreementProposal.newPartnerReceiver, address(0));
        assertEq(agreementProposal.newPartnerPortionBPS, 0);
        assertEq(agreementProposal.tokens.length, 0);
        assertEq(agreementProposal.fees.length, 0);
        assertEq(agreementProposal.proposalProvider, address(0));
        assertEq(agreementProposal.agreementProposalHash, bytes32(0));
    }

    // =========================
    // approveAgreement
    // =========================

    function test_arb_partnerFee_approveAgreement_accessControl() external {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(user);
        vm.expectRevert(
            IPartnerFee
                .PartnerFee_SenderMustBeOrDittoOwnerOrPartnerAddress
                .selector
        );
        partnerFee.approveAgreement(
            dittoController,
            dittoController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );
    }

    function test_arb_partnerFee_approveAgreement_shouldRevertIfProposalNotStarted()
        external
    {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(dittoController);
        vm.expectRevert(IPartnerFee.PartnerFee_ProposalNotStarted.selector);
        partnerFee.approveAgreement(
            dittoController,
            dittoController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );
    }

    function test_arb_partnerFee_approveAgreement_shouldRevertIfSenderIsProposalProvider()
        external
    {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(dittoController);
        partnerFee.initialize(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        vm.prank(dittoController);
        partnerFee.proposeAgreement(
            dittoController,
            dittoController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        vm.prank(dittoController);
        vm.expectRevert(IPartnerFee.PartnerFee_WrongApproveSender.selector);
        partnerFee.approveAgreement(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );
    }

    function test_arb_partnerFee_approveAgreement_shouldRevertIfProposalHashesAreNotSame()
        external
    {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(dittoController);
        partnerFee.initialize(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        vm.prank(dittoController);
        partnerFee.proposeAgreement(
            dittoController,
            dittoController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        tokens = new address[](1);
        fees = new uint256[](1);

        vm.prank(partnerController);
        vm.expectRevert(IPartnerFee.PartnerFee_ProposalParamsMismatch.selector);
        partnerFee.approveAgreement(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );
    }

    function test_arb_partnerFee_approveAgreement_shouldSuccessfullySetAgreement()
        external
    {
        address[] memory tokens;
        uint256[] memory fees;

        vm.prank(dittoController);
        partnerFee.initialize(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.5e18,
            tokens,
            fees
        );

        tokens = new address[](2);
        fees = new uint256[](2);

        tokens[0] = address(1);
        tokens[1] = address(2);
        fees[0] = 123456;
        fees[1] = 789101;

        vm.prank(dittoController);
        partnerFee.proposeAgreement(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.4e18,
            tokens,
            fees
        );
        {
            IPartnerFee.AgreementProposal memory agreementProposal = partnerFee
                .getAgreementProposal();

            assertEq(agreementProposal.newDittoController, dittoController);
            assertEq(agreementProposal.newPartnerController, partnerController);
            assertEq(agreementProposal.newDittoReceiver, dittoController);
            assertEq(agreementProposal.newPartnerReceiver, dittoController);
            assertEq(agreementProposal.newPartnerPortionBPS, 0.4e18);
            assertEq(agreementProposal.tokens.length, 2);
            assertEq(agreementProposal.fees.length, 2);
            assertEq(agreementProposal.proposalProvider, dittoController);
            assertEq(
                agreementProposal.agreementProposalHash,
                _hashProposal(
                    dittoController,
                    partnerController,
                    dittoController,
                    dittoController,
                    0.4e18,
                    tokens,
                    fees
                )
            );

            (address[] memory _tokens, uint256[] memory _fees) = partnerFee
                .getCurrentAgreement();

            assertEq(_tokens.length, 0);
            assertEq(_fees.length, 0);

            (
                address _dittoController,
                address _partnerController,
                address _dittoReceiver,
                address _partnerReceiver,
                uint256 _partnerPortionBPS
            ) = partnerFee.getState();

            assertEq(_dittoController, dittoController);
            assertEq(_partnerController, partnerController);
            assertEq(_dittoReceiver, dittoController);
            assertEq(_partnerReceiver, dittoController);
            assertEq(_partnerPortionBPS, 0.5e18);
        }

        vm.prank(partnerController);
        vm.expectEmit();
        emit NewFeeForToken(address(1), 123456);
        vm.expectEmit();
        emit NewFeeForToken(address(2), 789101);
        vm.expectEmit();
        emit AgreementUpdated(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.4e18
        );
        partnerFee.approveAgreement(
            dittoController,
            partnerController,
            dittoController,
            dittoController,
            0.4e18,
            tokens,
            fees
        );

        {
            IPartnerFee.AgreementProposal memory agreementProposal = partnerFee
                .getAgreementProposal();

            assertEq(agreementProposal.newDittoController, address(0));
            assertEq(agreementProposal.newPartnerController, address(0));
            assertEq(agreementProposal.newDittoReceiver, address(0));
            assertEq(agreementProposal.newPartnerReceiver, address(0));
            assertEq(agreementProposal.newPartnerPortionBPS, 0);
            assertEq(agreementProposal.tokens.length, 0);
            assertEq(agreementProposal.fees.length, 0);
            assertEq(agreementProposal.proposalProvider, address(0));
            assertEq(agreementProposal.agreementProposalHash, bytes32(0));

            (address[] memory _tokens, uint256[] memory _fees) = partnerFee
                .getCurrentAgreement();

            for (uint256 i; i < 2; ++i) {
                assertEq(_tokens[i], tokens[i]);
                assertEq(_fees[i], _fees[i]);
            }

            (
                address _dittoController,
                address _partnerController,
                address _dittoReceiver,
                address _partnerReceiver,
                uint256 _partnerPortionBPS
            ) = partnerFee.getState();

            assertEq(_dittoController, dittoController);
            assertEq(_partnerController, partnerController);
            assertEq(_dittoReceiver, dittoController);
            assertEq(_partnerReceiver, dittoController);
            assertEq(_partnerPortionBPS, 0.4e18);

            assertEq(
                partnerFee.getFixFeesForPartnerByToken(address(1)),
                123456
            );

            assertEq(
                partnerFee.getFixFeesForPartnerByToken(address(2)),
                789101
            );
        }
    }

    // =========================
    // helper
    // =========================

    function _hashProposal(
        address newDittoController,
        address newPartnerController,
        address newDittoReceiver,
        address newPartnerReceiver,
        uint256 newPartnerPortionBPS,
        address[] memory tokens,
        uint256[] memory fees
    ) private pure returns (bytes32 result) {
        bytes32 ptr;

        assembly ("memory-safe") {
            // store ptr for future trim
            ptr := mload(64)
        }

        bytes memory data = abi.encode(
            newDittoController,
            newPartnerController,
            newDittoReceiver,
            newPartnerReceiver,
            newPartnerPortionBPS,
            abi.encodePacked(tokens),
            abi.encodePacked(fees)
        );

        assembly ("memory-safe") {
            result := keccak256(add(data, 32), mload(data))
            mstore(64, ptr)
        }
    }
}
