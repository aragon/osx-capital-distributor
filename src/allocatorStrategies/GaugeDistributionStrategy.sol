// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { IAllocatorStrategy } from "../interfaces/IAllocatorStrategy.sol";
import { AllocatorStrategyBase } from "./AllocatorStrategyBase.sol";
import { IAddressGaugeVoter } from "../interfaces/helpers/IAddressGaugeVoter.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";

/// @title GaugeDistributionStrategy
/// @notice Allocator strategy that distributes tokens proportionally to gauges based on the votes they received
/// in Aragon OSx Gauge voting plugin
/// @dev Gauges receive allocations based on how many votes they received relative to the total votes cast
contract GaugeDistributionStrategy is AllocatorStrategyBase {
    // =========================================================================
    // Errors
    // =========================================================================

    error CampaignNotFound(uint256 campaignId);
    error CampaignAlreadyExists();
    error EpochMismatch(uint256 campaignEpoch, uint256 currentEpoch);
    error VotingCurrentlyActive();
    error InvalidGaugeVoter();
    error InvalidDistributionAmount();

    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice Reference to the Aragon OSx Gauge voting plugin
    IAddressGaugeVoter public gaugeVoter;

    /// @notice Campaign-specific configuration
    mapping(uint256 campaignId => GaugeAllocationCampaign) public campaigns;

    /// @notice Campaign data structure
    struct GaugeAllocationCampaign {
        uint256 epochId; // Epoch ID when campaign was created
        uint256 totalDistributionAmount; // Total amount available for this campaign
    }

    // =========================================================================
    // Initializer
    // =========================================================================

    /// @notice Initializes the strategy with gauge voting plugin reference
    /// @param _strategyId Strategy type identifier
    /// @param _dao DAO instance
    /// @param _plugin Capital distributor plugin address
    /// @param _auxData Encoded (IAddressGaugeVoter gaugeVoter)
    function initialize(bytes32 _strategyId, IDAO _dao, address _plugin, bytes calldata _auxData) public override {
        super.initialize(_strategyId, _dao, _plugin, _auxData);

        IAddressGaugeVoter _gaugeVoter = abi.decode(_auxData, (IAddressGaugeVoter));
        if (address(_gaugeVoter) == address(0)) revert InvalidGaugeVoter();

        gaugeVoter = _gaugeVoter;
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /// @notice Returns encoding types for strategy initialization
    /// @return types Comma-separated string of Solidity type strings for initialization auxData
    function getInitializationEncodingTypes() external pure override returns (string memory types) {
        return "address"; // IAddressGaugeVoter
    }

    /// @inheritdoc IAllocatorStrategy
    function getCreationEncodingTypes() external pure override returns (string memory types) {
        return "uint256"; // totalDistributionAmount
    }

    /// @inheritdoc IAllocatorStrategy
    function getClaimEncodingTypes() external pure override returns (string memory types) {
        return ""; // No auxiliary data needed for claiming
    }

    /// @inheritdoc IAllocatorStrategy
    function getTotalClaimableAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata
    )
        public
        view
        override
        returns (uint256 amount)
    {
        GaugeAllocationCampaign storage campaign = campaigns[_campaignId];

        // Validate campaign exists
        if (campaign.epochId == 0) revert CampaignAlreadyExists();

        // Validate campaign epoch matches current epoch
        uint256 currentEpoch = gaugeVoter.epochId();
        if (campaign.epochId != currentEpoch) {
            revert EpochMismatch(campaign.epochId, currentEpoch);
        }

        // Validate voting is not currently active (distribution period)
        if (gaugeVoter.votingActive()) revert VotingCurrentlyActive();

        // Get votes received by this gauge
        uint256 gaugeVotes = gaugeVoter.gaugeVotes(_account);
        if (gaugeVotes == 0) return 0;

        // Get total voting power cast
        uint256 totalVotingPowerCast = gaugeVoter.totalVotingPowerCast();
        if (totalVotingPowerCast == 0) return 0;

        // Calculate proportional allocation based on gauge votes
        return (gaugeVotes * campaign.totalDistributionAmount) / totalVotingPowerCast;
    }

    /// @notice Checks if gauge is eligible for allocation in the campaign
    /// @param _campaignId Campaign identifier
    /// @param _account Gauge address
    /// @return True if gauge is eligible
    function isGaugeEligible(uint256 _campaignId, address _account) public view returns (bool) {
        GaugeAllocationCampaign storage campaign = campaigns[_campaignId];

        // Check campaign exists
        if (campaign.epochId == 0) return false;

        // Check campaign epoch matches current epoch
        if (campaign.epochId != gaugeVoter.epochId()) return false;

        // Check voting is not currently active
        if (gaugeVoter.votingActive()) return false;

        // Check gauge has received votes > 0
        return gaugeVoter.gaugeVotes(_account) > 0;
    }

    // =========================================================================
    // External Functions
    // =========================================================================

    /// @inheritdoc IAllocatorStrategy
    /// @dev Campaigns can be created anytime, but gauge claims only work when:
    /// 1. Campaign has started (managed by CapitalDistributorPlugin)
    /// 2. Voting is not currently active (distribution period)
    /// 3. Current epoch matches campaign epoch
    function setAllocationCampaign(uint256 _campaignId, bytes calldata _auxData) public override {
        if (msg.sender != owner()) {
            revert IAllocatorStrategy.OnlyDAOAllowed(msg.sender);
        }

        // Campaign shouldn't already exist
        if (campaigns[_campaignId].epochId != 0) {
            revert CampaignAlreadyExists();
        }

        // Decode distribution amount
        uint256 totalDistributionAmount = abi.decode(_auxData, (uint256));
        if (totalDistributionAmount == 0) revert InvalidDistributionAmount();

        // Create new campaign
        campaigns[_campaignId] =
            GaugeAllocationCampaign({ epochId: gaugeVoter.epochId(), totalDistributionAmount: totalDistributionAmount });

        emit AllocationCampaignCreated(plugin, _campaignId);
    }
}
