// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Action } from "@aragon/commons/executors/IExecutor.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { PayoutActionEncoderBase } from "./PayoutActionEncoderBase.sol";

/// @title IVotingEscrow
/// @notice Interface for Voting Escrow contract that supports creating locks on behalf of users.
interface IVotingEscrow {
    /// @notice Creates a lock on behalf of someone else.
    /// @param _value Amount to deposit
    /// @param _to Address to receive the veNFT
    /// @return tokenId The ID of the created veNFT
    function createLockFor(uint256 _value, address _to) external returns (uint256);
}

/// @title VotingEscrowLockPayoutActionEncoder
/// @notice An IPayoutActionEncoder that approves tokens for a Voting Escrow contract and then calls createLockFor
///         to create ve-locked positions for users.
/// @dev This contract is DaoAuthorizable. The DAO controlling this encoder instance
///      must grant permission for `setVotingEscrow`.
contract VotingEscrowLockPayoutActionEncoder is PayoutActionEncoderBase {
    /// @notice Mapping from campaignId to the Voting Escrow contract address for that campaign.
    mapping(uint256 => address) public campaignVotingEscrow;

    /// @notice Emitted when a Voting Escrow address is set for a campaign.
    event CampaignVotingEscrowSet(
        uint256 indexed campaignId, address indexed votingEscrowAddress, address indexed setter
    );

    /// @notice Thrown if the amount to payout is zero.
    error AmountCannotBeZero();
    /// @notice Thrown if no Voting Escrow address is configured for the given campaignId.
    error VotingEscrowNotSetForCampaign(uint256 campaignId);
    /// @notice Thrown if the Voting Escrow address to be set is the zero address.
    error ZeroAddressNotAllowed();

    /// @inheritdoc PayoutActionEncoderBase
    function setupCampaign(uint256 _campaignId, bytes calldata _auxData) external override ownerOrDao {
        address votingEscrowAddress = decodeSetupCampaignParams(_auxData);
        if (votingEscrowAddress == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        campaignVotingEscrow[_campaignId] = votingEscrowAddress;
        emit CampaignVotingEscrowSet(_campaignId, votingEscrowAddress, msg.sender);
    }

    /**
     * @inheritdoc PayoutActionEncoderBase
     * @dev This implementation creates two actions:
     *      1. Approve the campaign-specific `votingEscrowAddress` to spend `_amount` of `_token`.
     *      2. Call `createLockFor(_amount, _recipient)` on that `votingEscrowAddress`.
     *      The `_campaignId` is used to look up the correct Voting Escrow address.
     *      The `_recipient` receives the veNFT representing the locked position.
     */
    function buildActions(
        IERC20 _token,
        address _recipient,
        uint256 _amount,
        address,
        uint256 _campaignId,
        bytes memory
    )
        external
        view
        override
        returns (Action[] memory actions)
    {
        if (_amount == 0) {
            revert AmountCannotBeZero();
        }

        address votingEscrowAddress = campaignVotingEscrow[_campaignId];
        if (votingEscrowAddress == address(0)) {
            revert VotingEscrowNotSetForCampaign(_campaignId);
        }

        actions = new Action[](2);

        // Action 1: Approve the Voting Escrow contract to spend the token
        actions[0] = Action({
            to: address(_token), value: 0, data: abi.encodeCall(IERC20.approve, (votingEscrowAddress, _amount))
        });

        // Action 2: Call createLockFor on the Voting Escrow contract
        // This creates a ve-locked position for the recipient
        actions[1] = Action({
            to: votingEscrowAddress, value: 0, data: abi.encodeCall(IVotingEscrow.createLockFor, (_amount, _recipient))
        });

        return actions;
    }

    /// @notice Encodes the Voting Escrow address parameter for setupCampaign
    /// @param _votingEscrowAddress The Voting Escrow address to encode
    /// @return The encoded parameters
    function encodeSetupCampaignParams(address _votingEscrowAddress) external pure returns (bytes memory) {
        return abi.encode(_votingEscrowAddress);
    }

    /// @notice Decodes the Voting Escrow address parameter from setupCampaign
    /// @param _data The encoded parameters
    /// @return votingEscrowAddress The decoded Voting Escrow address
    function decodeSetupCampaignParams(bytes memory _data) public pure returns (address votingEscrowAddress) {
        return abi.decode(_data, (address));
    }

    /// @inheritdoc PayoutActionEncoderBase
    /// @return types The encoding type for votingEscrowAddress parameter
    function getCreationEncodingTypes() external pure override returns (string memory types) {
        return "address";
    }

    /// @inheritdoc PayoutActionEncoderBase
    /// @return types Empty string as this encoder doesn't use encoderAuxData in buildActions
    function getClaimEncodingTypes() external pure override returns (string memory types) {
        return "";
    }
}
