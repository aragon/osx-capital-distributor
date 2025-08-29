// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { IAllocatorStrategy } from "../interfaces/IAllocatorStrategy.sol";
import { AllocatorStrategyBase } from "./AllocatorStrategyBase.sol";
import { IAddressGaugeVoter } from "../interfaces/helpers/IAddressGaugeVoter.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";

/// @title GaugeVoterAllocatorStrategy
/// @notice Allocator strategy that distributes tokens proportionally to users based on their voting participation and
/// power in Aragon OSx Gauge voting plugin
/// @dev Users receive allocations based on how much voting power they contributed to the gauge relative to the total
/// voting power cast
contract GaugeVoterAllocatorStrategy is AllocatorStrategyBase {
    // =========================================================================
    // Errors
    // =========================================================================

    error CampaignNotFound(uint256 campaignId);
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
    /// @param _strategyTypeId Strategy type identifier
    /// @param _dao DAO instance
    /// @param _plugin Capital distributor plugin address
    /// @param _auxData Encoded (IAddressGaugeVoter gaugeVoter)
    function initialize(bytes32 _strategyTypeId, IDAO _dao, address _plugin, bytes calldata _auxData) public override {
        super.initialize(_strategyTypeId, _dao, _plugin, _auxData);

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
    function getClaimeableAmount(
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
        if (campaign.epochId == 0) revert CampaignNotFound(_campaignId);

        // Validate campaign epoch matches current epoch
        uint256 currentEpoch = gaugeVoter.epochId();
        if (campaign.epochId != currentEpoch) {
            revert EpochMismatch(campaign.epochId, currentEpoch);
        }

        // Validate voting is not currently active (distribution period)
        if (gaugeVoter.votingActive()) revert VotingCurrentlyActive();

        // Get user's current voting power
        uint256 userVotingPower = gaugeVoter.usedVotingPower(_account);
        if (userVotingPower == 0) return 0;

        // Get total voting power cast
        uint256 totalVotingPowerCast = gaugeVoter.totalVotingPowerCast();
        if (totalVotingPowerCast == 0) return 0;

        // Calculate proportional allocation
        return (userVotingPower * campaign.totalDistributionAmount) / totalVotingPowerCast;
    }

    /// @notice Checks if user is eligible for allocation in the campaign
    /// @param _campaignId Campaign identifier
    /// @param _account User address
    /// @return True if user is eligible
    function isUserEligible(uint256 _campaignId, address _account) public view returns (bool) {
        GaugeAllocationCampaign storage campaign = campaigns[_campaignId];

        // Check campaign exists
        if (campaign.epochId == 0) return false;

        // Check campaign epoch matches current epoch
        if (campaign.epochId != gaugeVoter.epochId()) return false;

        // Check voting is not currently active
        if (gaugeVoter.votingActive()) return false;

        // Check user has voting power > 0
        return gaugeVoter.usedVotingPower(_account) > 0;
    }

    // =========================================================================
    // External Functions
    // =========================================================================

    /// @inheritdoc IAllocatorStrategy
    /// @dev Campaigns can be created anytime, but claims only work when:
    /// 1. Campaign has started (managed by CapitalDistributorPlugin)
    /// 2. Voting is not currently active (distribution period)
    /// 3. Current epoch matches campaign epoch
    function setAllocationCampaign(uint256 _campaignId, bytes calldata _auxData) public override {
        if (msg.sender != owner() && msg.sender != address(dao())) {
            revert IAllocatorStrategy.OnlyDAOAllowed(msg.sender);
        }

        // Campaign shouldn't already exist
        if (campaigns[_campaignId].epochId != 0) {
            revert CampaignNotFound(_campaignId);
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
