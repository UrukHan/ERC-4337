// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPartnerFee} from "./interfaces/IPartnerFee.sol";
import {Ownable} from "../../external/Ownable.sol";

/// @title PartnerFee
contract PartnerFee is IPartnerFee, Ownable {
    // =========================
    // Storage
    // =========================

    uint256 private constant E18 = 1e18;

    AgreementData private _currentAgreement;
    address private _dittoController;
    address private _partnerController;
    address private _dittoReceiver;
    address private _partnerReceiver;
    uint256 private _partnerPortionBPS;

    AgreementProposal private _agreementProposal;

    bool initialized;

    // =========================
    // Constructor
    // =========================

    constructor(address dittoController_) {
        _dittoController = dittoController_;
    }

    function initialize(
        address dittoController,
        address partnerController,
        address dittoReceiver,
        address partnerReceiver,
        uint256 partnerPortionBPS,
        address[] calldata tokens,
        uint256[] calldata fees
    ) external {
        _onlyController();

        if (initialized) {
            revert PartnerFee_AlreadyInitialized();
        }
        initialized = true;

        _parametersCheck(partnerPortionBPS, tokens.length, fees.length);

        _setAgreement(
            dittoController,
            partnerController,
            dittoReceiver,
            partnerReceiver,
            partnerPortionBPS,
            tokens,
            fees
        );
    }

    // =========================
    // Actions
    // =========================

    // Withdraw rewards function
    function withdrawReward(address _token) external {
        if (!initialized) {
            revert PartnerFee_NotInitialized();
        }

        uint256 balance = IERC20Metadata(_token).balanceOf(address(this));

        if (balance > 0) {
            uint256 rewardPartner;

            unchecked {
                rewardPartner = (balance * _partnerPortionBPS) / E18;
                balance -= rewardPartner;
            }

            if (rewardPartner > 0) {
                IERC20Metadata(_token).transfer(
                    _partnerReceiver,
                    rewardPartner
                );
            }
            IERC20Metadata(_token).transfer(_dittoReceiver, balance);

            emit RewardWithdrawn(_token, rewardPartner, balance);
        }
    }

    // =========================
    // Getters
    // =========================

    function getCurrentAgreement()
        external
        view
        returns (address[] memory tokens, uint256[] memory fees)
    {
        address[] storage currentTokenList = _currentAgreement.tokenList;
        mapping(address => uint256) storage feesByToken = _currentAgreement
            .feesByToken;

        uint256 tokenListLength = currentTokenList.length;

        tokens = new address[](tokenListLength);
        fees = new uint256[](tokenListLength);

        for (uint256 i; i < tokenListLength; ) {
            address token = currentTokenList[i];
            tokens[i] = token;
            fees[i] = feesByToken[token];

            unchecked {
                ++i;
            }
        }
    }

    function getState()
        external
        view
        returns (
            address dittoController,
            address partnerController,
            address dittoReceiver,
            address partnerReceiver,
            uint256 partnerPortionBPS
        )
    {
        dittoController = _dittoController;
        partnerController = _partnerController;
        dittoReceiver = _dittoReceiver;
        partnerReceiver = _partnerReceiver;
        partnerPortionBPS = _partnerPortionBPS;
    }

    function getFixFeesForPartnerByToken(
        address tokenAddress
    ) external view returns (uint256 fixFee) {
        if (!_currentAgreement.allowedTokens[tokenAddress]) {
            revert PartnerFee_TokenIsNotAllowed(tokenAddress);
        }

        fixFee = _currentAgreement.feesByToken[tokenAddress];
    }

    function getAgreementProposal()
        external
        view
        returns (AgreementProposal memory agreementProposal)
    {
        agreementProposal = _agreementProposal;
    }

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
    ) external {
        _onlyController();

        if (!initialized) {
            revert PartnerFee_NotInitialized();
        }

        _parametersCheck(newPartnerPortionBPS, tokens.length, fees.length);

        if (_dittoController == _partnerController) {
            _resetCurrentAgreementDataStorage();
            _setAgreement(
                newDittoController,
                newPartnerController,
                newDittoReceiver,
                newPartnerReceiver,
                newPartnerPortionBPS,
                tokens,
                fees
            );
        } else {
            AgreementProposal storage agreementProposal = _agreementProposal;

            if (agreementProposal.agreementProposalHash != bytes32(0)) {
                revert PartnerFee_ProposalAlreadyStarted();
            }

            uint256 tokensLength = tokens.length;

            agreementProposal.agreementProposalHash = _hashProposal(
                newDittoController,
                newPartnerController,
                newDittoReceiver,
                newPartnerReceiver,
                newPartnerPortionBPS,
                tokens,
                fees
            );

            agreementProposal.newDittoController = newDittoController;
            agreementProposal.newPartnerController = newPartnerController;
            agreementProposal.newDittoReceiver = newDittoReceiver;
            agreementProposal.newPartnerReceiver = newPartnerReceiver;
            agreementProposal.newPartnerPortionBPS = newPartnerPortionBPS;

            address[] storage _tokens = agreementProposal.tokens;
            uint256[] storage _fees = agreementProposal.fees;

            for (uint256 i; i < tokensLength; ) {
                _tokens.push(tokens[i]);
                _fees.push(fees[i]);

                unchecked {
                    ++i;
                }
            }

            agreementProposal.proposalProvider = msg.sender;
        }
    }

    function deleteProposal() external {
        _onlyController();

        if (_agreementProposal.agreementProposalHash == bytes32(0)) {
            revert PartnerFee_ProposalNotStarted();
        }

        // only proposalProvider can cancel proposal
        if (_agreementProposal.proposalProvider != msg.sender) {
            revert PartnerFee_WrongApproveSender();
        }

        // Clear the proposal to allow for future proposals
        delete _agreementProposal;
    }

    // Function for the second controller to approve the new agreement
    function approveAgreement(
        address newDittoController,
        address newPartnerController,
        address newDittoReceiver,
        address newPartnerReceiver,
        uint256 newPartnerPortionBPS,
        address[] calldata tokens,
        uint256[] calldata fees
    ) external {
        _onlyController();

        AgreementProposal memory agreementProposal = _agreementProposal;

        if (agreementProposal.agreementProposalHash == bytes32(0)) {
            revert PartnerFee_ProposalNotStarted();
        }

        if (agreementProposal.proposalProvider == msg.sender) {
            revert PartnerFee_WrongApproveSender();
        }

        if (
            _hashProposal(
                newDittoController,
                newPartnerController,
                newDittoReceiver,
                newPartnerReceiver,
                newPartnerPortionBPS,
                tokens,
                fees
            ) != agreementProposal.agreementProposalHash
        ) {
            revert PartnerFee_ProposalParamsMismatch();
        }

        _resetCurrentAgreementDataStorage();

        _setAgreement(
            newDittoController,
            newPartnerController,
            newDittoReceiver,
            newPartnerReceiver,
            newPartnerPortionBPS,
            tokens,
            fees
        );

        // Clear the proposal to allow for future proposals
        delete _agreementProposal;
    }

    // =========================
    // Private methods
    // =========================

    function _setAgreement(
        address dittoController,
        address partnerController,
        address dittoReceiver,
        address partnerReceiver,
        uint256 partnerPortionBPS,
        address[] calldata tokens,
        uint256[] calldata fees
    ) private {
        if (_dittoController != dittoController) {
            _dittoController = dittoController;
        }
        if (_partnerController != partnerController) {
            _partnerController = partnerController;
        }
        if (_dittoReceiver != dittoReceiver) {
            _dittoReceiver = dittoReceiver;
        }
        if (_partnerReceiver != partnerReceiver) {
            _partnerReceiver = partnerReceiver;
        }
        if (_partnerPortionBPS != partnerPortionBPS) {
            _partnerPortionBPS = partnerPortionBPS;
        }

        address[] storage _currentTokenList = _currentAgreement.tokenList;
        mapping(address => uint256) storage feesByToken = _currentAgreement
            .feesByToken;
        mapping(address => bool) storage allowedTokens = _currentAgreement
            .allowedTokens;

        uint256 _tokenLength = tokens.length;

        for (uint256 i; i < _tokenLength; ) {
            address token = tokens[i];
            uint256 fee = fees[i];

            feesByToken[token] = fee;
            emit NewFeeForToken(token, fee);

            allowedTokens[token] = true;
            _currentTokenList.push(token);

            unchecked {
                ++i;
            }
        }

        emit AgreementUpdated(
            dittoController,
            partnerController,
            dittoReceiver,
            partnerReceiver,
            partnerPortionBPS
        );
    }

    // Function to reset the agreement data to a new state
    function _resetCurrentAgreementDataStorage() private {
        address[] storage currentTokenList = _currentAgreement.tokenList;
        mapping(address => uint256) storage feesByToken = _currentAgreement
            .feesByToken;
        mapping(address => bool) storage allowedTokens = _currentAgreement
            .allowedTokens;

        uint256 _tokenListLength = currentTokenList.length;

        // Iterate over 'tokenList' and delete each entry from 'feesByToken' and 'whitelistedTokens'
        for (uint256 i; i < _tokenListLength; ) {
            address token = currentTokenList[i];
            feesByToken[token] = 0;
            allowedTokens[token] = false;

            unchecked {
                ++i;
            }
        }
        // Clear the 'tokenList' itself
        for (uint256 i; i < _tokenListLength; ) {
            currentTokenList.pop();

            unchecked {
                ++i;
            }
        }
    }

    function _onlyController() private view {
        if (msg.sender != _dittoController) {
            if (msg.sender != _partnerController) {
                revert PartnerFee_SenderMustBeOrDittoOwnerOrPartnerAddress();
            }
        }
    }

    function _parametersCheck(
        uint256 partnerPortionBPS,
        uint256 tokenLength,
        uint256 feesLength
    ) private pure {
        if (partnerPortionBPS > E18) {
            revert PartnerFee_PartnerPartOfFeesCannotBeGreaterThan100Percents();
        }

        if (tokenLength != feesLength) {
            revert PartnerFee_ArraysLengthNotMatch();
        }
    }

    function _hashProposal(
        address newDittoController,
        address newPartnerController,
        address newDittoReceiver,
        address newPartnerReceiver,
        uint256 newPartnerPortionBPS,
        address[] calldata tokens,
        uint256[] calldata fees
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
