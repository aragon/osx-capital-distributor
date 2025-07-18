// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {Action, IExecutor} from "@aragon/commons/executors/IExecutor.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title IPayoutActionEncoder
/// @notice Interface for contracts that construct the DAO actions required to execute a payout.
interface IPayoutActionEncoder {
    error OnlyDAOAllowed(address account);

    /// @notice Retrieves the encoder ID associated with a campaign.
    /// @return The encoder ID.
    function encoderId() external view returns (bytes32);

    /// @notice Returns the Solidity types expected for campaign setup auxiliary data.
    /// @return types Comma-separated string of Solidity type strings expected for setupCampaign _auxData parameter.
    function getCreationEncodingTypes() external view returns (string memory types);

    /// @notice Returns the Solidity types expected for buildActions auxiliary data.
    /// @return types Comma-separated string of Solidity type strings expected for buildActions _encoderAuxData parameter.
    function getClaimEncodingTypes() external view returns (string memory types);

    /**
     * @notice Call to setup the ActionEncoder for the campaign
     * @param _campaignId The ID of the campaign for which this payout is being made.
     * @param _auxData The data require to initialize the encoder
     */
    function setupCampaign(uint256 _campaignId, bytes calldata _auxData) external;

    /**
     * @notice Constructs the sequence of actions required to execute a payout.
     * @param _token The token being distributed.
     * @param _recipient The ultimate beneficiary of the payout.
     * @param _amount The amount of tokens to be paid out.
     * @param _caller The address of the CapitalDistributorPlugin calling this builder.
     * @param _campaignId The ID of the campaign for which this payout is being made.
     * @param _encoderAuxData The data needed by the encoder to send the payout
     * @return actions An array of `Action` structs to be executed by the DAO.
     */
    function buildActions(
        IERC20 _token,
        address _recipient,
        uint256 _amount,
        address _caller, // Added for context, might be useful for builders
        uint256 _campaignId, // Added for context
        bytes calldata _encoderAuxData
    ) external view returns (Action[] memory actions);
}
