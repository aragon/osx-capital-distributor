// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.29;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IAllocatorStrategy } from "./IAllocatorStrategy.sol";
import { IPayoutActionEncoder } from "./IPayoutActionEncoder.sol";

/// @title ICapitalDistributorPlugin
/// @notice Interface for the CapitalDistributorPlugin contract
interface ICapitalDistributorPlugin is IERC165 {
    // ====================================
    // Configuration Structs
    // ====================================

    /// @notice Represents the different states a campaign can be in
    /// @dev ACTIVE: Normal operation, claims allowed
    /// @dev PAUSED: Temporarily paused (for updates), can be resumed
    /// @dev ENDED: Permanently ended, cannot be resumed
    enum CampaignState {
        ACTIVE,
        PAUSED,
        ENDED
    }

    /// @notice Represents a distribution campaign.
    /// @param metadataURI URI pointing to the campaign's metadata (e.g., IPFS hash).
    /// @param allocationStrategy The contract address responsible for determining allocation logic.
    /// @param token The address of the token that will be used for the payouts
    /// @param actionEncoder The logic to execute when claiming the payout
    /// @param state The current state of the campaign (ACTIVE, PAUSED, or ENDED)
    /// @param startTime The timestamp when the campaign becomes active (0 means no start time restriction)
    /// @param endTime The timestamp when the campaign ends (0 means no end time restriction)
    struct Campaign {
        bytes metadataUri;
        IAllocatorStrategy allocationStrategy;
        IERC20 token;
        IPayoutActionEncoder actionEncoder;
        CampaignState state;
        uint64 startTime;
        uint64 endTime;
    }

    /// @notice Strategy configuration for a campaign
    /// @param strategyId The strategy type ID to deploy or use
    /// @param strategyParams Deployment parameters for the strategy
    /// @param initData Additional data needed to initialize the allocation strategy
    struct StrategyConfig {
        bytes32 strategyId;
        bytes strategyParams;
        bytes initData;
    }

    /// @notice Payout configuration for a campaign
    /// @param token The token address that will be used for payouts
    /// @param actionEncoderId The action encoder type ID to deploy (use bytes32(0) for simple transfers)
    /// @param actionEncoderInitData Additional data needed to initialize the action encoder
    struct PayoutConfig {
        IERC20 token;
        bytes32 actionEncoderId;
        bytes actionEncoderInitData;
    }

    /// @notice Campaign settings for time bounds and claim behavior
    /// @param startTime The timestamp when the campaign becomes active (0 means no start time restriction)
    /// @param endTime The timestamp when the campaign ends (0 means no end time restriction)
    struct CampaignSettings {
        uint64 startTime;
        uint64 endTime;
    }

    // ====================================
    // Core Campaign Management Functions
    // ====================================

    /// @notice Creates a new distribution campaign with the specified configuration
    /// @param _metadataURI URI pointing to the campaign's metadata (e.g., IPFS hash)
    /// @param _strategy Strategy configuration including type, params, and init data
    /// @param _payout Payout configuration including token and action encoder settings
    /// @param _settings Campaign time bounds and behavior settings
    /// @return id The ID of the newly created campaign
    function createCampaign(
        bytes calldata _metadataURI,
        StrategyConfig calldata _strategy,
        PayoutConfig calldata _payout,
        CampaignSettings calldata _settings
    )
        external
        returns (uint256 id);

    /// @notice Claims payout from a campaign for the message sender
    /// @param _campaignId The ID of the campaign to claim from
    /// @param _recipient The address that will receive the payout
    /// @param _strategyAuxData Additional data required by the allocation strategy
    /// @param _encoderAuxData Additional data required by the action encoder
    /// @return amountToSend The amount of tokens that will be sent
    function claimCampaignPayout(
        uint256 _campaignId,
        address _recipient,
        bytes calldata _strategyAuxData,
        bytes calldata _encoderAuxData
    )
        external
        returns (uint256 amountToSend);

    /// @notice Claims payout from a campaign to a specific address
    /// @param _campaignId The ID of the campaign to claim from
    /// @param _payoutAddress The address that will receive the payout
    /// @param _strategyAuxData Additional data required by the allocation strategy
    /// @param _encoderAuxData Additional data required by the action encoder
    /// @return amountToSend The amount of tokens that will be sent
    function claimCampaignPayoutToAddress(
        uint256 _campaignId,
        address _payoutAddress,
        bytes calldata _strategyAuxData,
        bytes calldata _encoderAuxData
    )
        external
        returns (uint256 amountToSend);

    /// @notice Claims payouts from multiple campaigns in a single transaction
    /// @param _campaignIds Array of campaign IDs to claim from
    /// @param _recipients Array of recipient addresses for each claim
    /// @param _strategiesAuxData Array of strategy auxiliary data for each claim
    /// @param _encodersAuxData Array of encoder auxiliary data for each claim
    /// @return amounts Array of amounts that will be sent for each claim
    function batchClaimCampaignPayout(
        uint256[] calldata _campaignIds,
        address[] calldata _recipients,
        bytes[] calldata _strategiesAuxData,
        bytes[] calldata _encodersAuxData
    )
        external
        returns (uint256[] memory amounts);

    // ====================================
    // Campaign State Management Functions
    // ====================================

    /// @notice Pauses an active campaign, temporarily disabling claims
    /// @param _campaignId The ID of the campaign to pause
    function pauseCampaign(uint256 _campaignId) external;

    /// @notice Resumes a paused campaign, re-enabling claims
    /// @param _campaignId The ID of the campaign to resume
    function resumeCampaign(uint256 _campaignId) external;

    /// @notice Permanently ends a campaign, disabling all future claims
    /// @param _campaignId The ID of the campaign to end
    function endCampaign(uint256 _campaignId) external;

    // ====================================
    // Factory Integration Functions
    // ====================================

    /// @notice Deploys a new allocation strategy using the strategy factory
    /// @param _strategyId The ID of the strategy to deploy
    /// @param _deploymentParams The parameters for the strategy deployment
    /// @return strategyAddress The address of the deployed strategy
    function deployStrategy(
        bytes32 _strategyId,
        bytes calldata _deploymentParams
    )
        external
        returns (address strategyAddress);

    /// @notice Deploys a new action encoder using the action encoder factory
    /// @param _actionEncoderId The ID of the action encoder to deploy
    /// @param _deploymentParams The parameters for the action encoder deployment
    /// @return actionEncoderAddress The address of the deployed action encoder
    function deployActionEncoder(
        bytes32 _actionEncoderId,
        bytes calldata _deploymentParams
    )
        external
        returns (address actionEncoderAddress);

    // ====================================
    // View functions
    // ====================================

    /// @notice Returns the total number of campaigns created
    /// @return The current campaign count
    function numCampaigns() external view returns (uint256);

    /// @notice Checks if a campaign is currently active
    /// @param _campaignId The ID of the campaign to check
    /// @return active True if the campaign is active and within time bounds
    function isCampaignActive(uint256 _campaignId) external view returns (bool active);

    /// @notice Checks if a campaign is currently paused
    /// @param _campaignId The ID of the campaign to check
    /// @return paused True if the campaign is paused
    function isCampaignPaused(uint256 _campaignId) external view returns (bool paused);

    /// @notice Returns the complete campaign configuration
    /// @param _campaignId The ID of the campaign to retrieve
    /// @return campaign The campaign struct containing all configuration data
    function getCampaign(uint256 _campaignId) external view returns (Campaign memory campaign);

    /// @notice Returns the strategy ID for a given campaign
    /// @param _campaignId The campaign ID to query
    /// @return strategyId The bytes32 strategy identifier used by the campaign
    function getCampaignStrategyId(uint256 _campaignId) external view returns (bytes32 strategyId);

    /// @notice Returns the encoder ID for a given campaign
    /// @param _campaignId The campaign ID to query
    /// @return encoderId The bytes32 encoder identifier used by the campaign
    function getCampaignEncoderId(uint256 _campaignId) external view returns (bytes32 encoderId);

    /// @notice Returns the amount already claimed by an account for a specific campaign
    /// @param _campaignId The campaign ID to check
    /// @param _account The account address to check
    /// @return amount The amount already claimed by the account
    function getClaimedAmount(uint256 _campaignId, address _account) external view returns (uint256 amount);

    /// @notice Returns the encoding types expected for strategy initialization
    /// @param _strategyId The strategy ID to query
    /// @return types Comma-separated string of Solidity type strings
    function getStrategyInitializationEncodingTypes(bytes32 _strategyId) external view returns (string memory types);

    /// @notice Returns the encoding types expected for strategy creation auxiliary data
    /// @param _campaignId The campaign ID to query
    /// @return types Comma-separated string of Solidity type strings
    function getStrategyCreationEncodingTypes(uint256 _campaignId) external view returns (string memory types);

    /// @notice Returns the encoding types expected for strategy claim auxiliary data
    /// @param _campaignId The campaign ID to query
    /// @return types Comma-separated string of Solidity type strings
    function getStrategyClaimEncodingTypes(uint256 _campaignId) external view returns (string memory types);

    /// @notice Returns the encoding types expected for encoder creation auxiliary data
    /// @param _campaignId The campaign ID to query
    /// @return types Comma-separated string of Solidity type strings
    function getEncoderCreationEncodingTypes(uint256 _campaignId) external view returns (string memory types);

    /// @notice Returns the encoding types expected for encoder claim auxiliary data
    /// @param _campaignId The campaign ID to query
    /// @return types Comma-separated string of Solidity type strings
    function getEncoderClaimEncodingTypes(uint256 _campaignId) external view returns (string memory types);
}
