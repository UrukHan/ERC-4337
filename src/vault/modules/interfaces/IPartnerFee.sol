// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPartnerFee {
    // =========================
    // Storage
    // =========================

    struct AgreementData {
        mapping(address => uint256) feesByToken;
        mapping(address => bool) allowedTokens;
        address[] tokenList; // Array to keep track of all keys used in 'feesByToken'
    }

    // Struct to store agreement proposals
    struct AgreementProposal {
        address newDittoController;
        address newPartnerController;
        address newDittoReceiver;
        address newPartnerReceiver;
        uint256 newPartnerPortionBPS;
        address[] tokens;
        uint256[] fees;
        address proposalProvider;
        bytes32 agreementProposalHash;
    }

    function initialize(
        address dittoController,
        address partnerController,
        address dittoReceiver,
        address partnerReceiver,
        uint256 partnerPortionBPS,
        address[] calldata tokens,
        uint256[] calldata fees
    ) external;

    // =========================
    // Events
    // =========================

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
    // Errors
    // =========================

    error PartnerFee_AlreadyInitialized();
    error PartnerFee_NotInitialized();
    error PartnerFee_AddressZero();
    error PartnerFee_ArraysLengthNotMatch();
    error PartnerFee_PartnerPartOfFeesCannotBeGreaterThan100Percents();
    error PartnerFee_SenderMustBeOrDittoOwnerOrPartnerAddress();
    error PartnerFee_TokenIsNotAllowed(address tokenAddress);
    error PartnerFee_ProposalAlreadyStarted();
    error PartnerFee_ProposalNotStarted();
    error PartnerFee_ProposalParamsMismatch();
    error PartnerFee_WrongApproveSender();

    // =========================
    // Actions
    // =========================

    // Withdraw rewards function
    function withdrawReward(address _token) external;

    // =========================
    // Getters
    // =========================

    function getCurrentAgreement()
        external
        view
        returns (address[] memory tokens, uint256[] memory fees);

    function getState()
        external
        view
        returns (
            address dittoController,
            address partnerController,
            address dittoReceiver,
            address partnerReceiver,
            uint256 partnerPortionBPS
        );

    function getFixFeesForPartnerByToken(
        address tokenAddress
    ) external view returns (uint256 fixFee);

    function getAgreementProposal()
        external
        view
        returns (AgreementProposal memory agreementProposal);

    // =========================
    // Setters
    // =========================

    // Function to propose a new agreement
    function proposeAgreement(
        address newDittoController,
        address newPartnerController,
        address newDittoReceiver,
        address newPartnerReceiver,
        uint256 newPartnerPortionBPS,
        address[] calldata tokens,
        uint256[] calldata fees
    ) external;

    function deleteProposal() external;

    // Function for the second controller to approve the new agreement
    function approveAgreement(
        address newDittoController,
        address newPartnerController,
        address newDittoReceiver,
        address newPartnerReceiver,
        uint256 newPartnerPortionBPS,
        address[] calldata tokens,
        uint256[] calldata fees
    ) external;
}
