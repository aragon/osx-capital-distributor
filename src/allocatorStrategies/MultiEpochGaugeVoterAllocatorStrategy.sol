// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { IAllocatorStrategy } from "../interfaces/IAllocatorStrategy.sol";
import { AllocatorStrategyBase } from "./AllocatorStrategyBase.sol";
import { IGaugeVoterSnapshotter } from "../interfaces/IGaugeVoterSnapshotter.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";

/// @title MultiEpochGaugeVoterAllocatorStrategy
/// @notice Allocator strategy that distributes tokens to gauges across multiple epochs based on historical vote data
/// @dev Supports campaigns that span multiple epochs with flexible distribution amounts per epoch
/// @dev The plugin tracks claims, this strategy only calculates accumulated unclaimed amounts
contract MultiEpochGaugeVoterAllocatorStrategy is AllocatorStrategyBase {
    // =========================================================================
    // Errors
    // =========================================================================

    error CampaignNotFound(uint256 campaignId);
    error InvalidSnapshotter();
    error InvalidEpochBounds(uint256 startEpoch, uint256 endEpoch);
    error EpochNotInCampaign(uint256 epoch, uint256 startEpoch, uint256 endEpoch);
    error EpochNotSnapshotted(uint256 epoch);
    error NoDistributionForEpoch(uint256 epoch);
    error InvalidDistributionAmount();
    error EpochInPast(uint256 epoch, uint256 currentEpoch);
    error CampaignAlreadyExists(uint256 campaignId);

    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice Reference to the gauge voter snapshotter
    IGaugeVoterSnapshotter public snapshotter;

    /// @notice Campaign-specific configuration
    mapping(uint256 campaignId => MultiEpochGaugeAllocationCampaign) public campaigns;

    /// @notice Campaign data structure
    struct MultiEpochGaugeAllocationCampaign {
        uint256 startEpoch; // First epoch of the campaign
        uint256 endEpoch; // Last epoch (0 = continuous)
        mapping(uint256 => uint256) epochDistributions; // epoch => amount to distribute
    }

    // =========================================================================
    // Initializer
    // =========================================================================

    /// @notice Initializes the strategy with snapshotter reference
    /// @param _strategyTypeId Strategy type identifier
    /// @param _dao DAO instance
    /// @param _plugin Capital distributor plugin address
    /// @param _auxData Encoded (IGaugeVoterSnapshotter snapshotter)
    function initialize(bytes32 _strategyTypeId, IDAO _dao, address _plugin, bytes calldata _auxData) public override {
        super.initialize(_strategyTypeId, _dao, _plugin, _auxData);

        IGaugeVoterSnapshotter _snapshotter = abi.decode(_auxData, (IGaugeVoterSnapshotter));
        if (address(_snapshotter) == address(0)) revert InvalidSnapshotter();

        snapshotter = _snapshotter;
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /// @notice Returns encoding types for strategy initialization
    /// @return types Comma-separated string of Solidity type strings for initialization auxData
    function getInitializationEncodingTypes() external pure override returns (string memory types) {
        return "address"; // IGaugeVoterSnapshotter
    }

    /// @inheritdoc IAllocatorStrategy
    function getCreationEncodingTypes() external pure override returns (string memory types) {
        return "uint256,uint256"; // startEpoch, endEpoch
    }

    /// @inheritdoc IAllocatorStrategy
    function getClaimEncodingTypes() external pure override returns (string memory types) {
        return ""; // No auxData needed for claims since we accumulate all epochs
    }

    /// @inheritdoc IAllocatorStrategy
    /// @dev For this strategy, _account represents the gauge address
    /// @dev _auxData is ignored as we accumulate all unclaimed epochs
    /// @dev The plugin tracks what has been claimed, so we return the total accumulated amount
    function getClaimeableAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    )
        public
        view
        override
        returns (uint256 amount)
    {
        MultiEpochGaugeAllocationCampaign storage campaign = campaigns[_campaignId];

        // Validate campaign exists
        if (campaign.startEpoch == 0) revert CampaignNotFound(_campaignId);

        // Accumulate claimable amounts across all eligible epochs
        uint256 totalClaimable = 0;

        // Determine the range of epochs to check
        uint256 currentEpoch = _getCurrentEpoch();
        uint256 endEpoch = campaign.endEpoch == 0 ? currentEpoch : campaign.endEpoch;
        if (endEpoch > currentEpoch) endEpoch = currentEpoch;

        // Accumulate rewards for all snapshotted epochs
        for (uint256 epoch = campaign.startEpoch; epoch <= endEpoch;) {
            // Only add if epoch is snapshotted and has distribution
            if (snapshotter.isEpochSnapshotted(epoch) && campaign.epochDistributions[epoch] > 0) {
                totalClaimable += _getEpochClaimableAmount(_campaignId, _account, epoch);
            }

            unchecked {
                ++epoch;
            }
        }

        return totalClaimable;
    }

    /// @notice Gets the current epoch from the snapshotter
    /// @dev The snapshotter forwards this call to the gauge voter's epochId()
    function _getCurrentEpoch() internal view returns (uint256) {
        return snapshotter.getCurrentEpoch();
    }

    /// @notice Internal function to calculate claimable amount for an epoch without checking claim status
    function _getEpochClaimableAmount(
        uint256 _campaignId,
        address _gauge,
        uint256 _epochId
    )
        internal
        view
        returns (uint256)
    {
        MultiEpochGaugeAllocationCampaign storage campaign = campaigns[_campaignId];

        // Validate epoch is within campaign bounds
        if (_epochId < campaign.startEpoch) {
            revert EpochNotInCampaign(_epochId, campaign.startEpoch, campaign.endEpoch);
        }
        if (campaign.endEpoch > 0 && _epochId > campaign.endEpoch) {
            revert EpochNotInCampaign(_epochId, campaign.startEpoch, campaign.endEpoch);
        }

        // Check if epoch has been snapshotted
        if (!snapshotter.isEpochSnapshotted(_epochId)) {
            revert EpochNotSnapshotted(_epochId);
        }

        // Check if distribution is set for this epoch
        uint256 epochDistribution = campaign.epochDistributions[_epochId];
        if (epochDistribution == 0) {
            revert NoDistributionForEpoch(_epochId);
        }

        // Get historical voting data
        uint256 gaugeVotes = snapshotter.getGaugeVotes(_epochId, _gauge);
        if (gaugeVotes == 0) return 0;

        uint256 totalVotingPowerCast = snapshotter.getTotalVotingPowerCast(_epochId);
        if (totalVotingPowerCast == 0) return 0;

        // Calculate proportional allocation
        return (gaugeVotes * epochDistribution) / totalVotingPowerCast;
    }

    /// @notice Gets the distribution amount for a specific epoch
    /// @param _campaignId Campaign identifier
    /// @param _epochId Epoch to query
    /// @return Distribution amount for the epoch
    function getEpochDistribution(uint256 _campaignId, uint256 _epochId) public view returns (uint256) {
        return campaigns[_campaignId].epochDistributions[_epochId];
    }

    /// @notice Checks if an epoch can be claimed (snapshotted and has distribution)
    /// @param _campaignId Campaign identifier
    /// @param _epochId Epoch to check
    /// @return True if epoch is claimable
    function isEpochClaimable(uint256 _campaignId, uint256 _epochId) public view returns (bool) {
        MultiEpochGaugeAllocationCampaign storage campaign = campaigns[_campaignId];

        // Check campaign exists
        if (campaign.startEpoch == 0) return false;

        // Check epoch bounds
        if (_epochId < campaign.startEpoch) return false;
        if (campaign.endEpoch > 0 && _epochId > campaign.endEpoch) return false;

        // Check if snapshotted and has distribution
        return snapshotter.isEpochSnapshotted(_epochId) && campaign.epochDistributions[_epochId] > 0;
    }

    /// @notice Gets the claimable amount for a specific epoch
    /// @dev This is a helper to check individual epoch amounts
    /// @param _campaignId Campaign identifier
    /// @param _gauge Gauge address
    /// @param _epochId Epoch to check
    /// @return Amount claimable for the specified epoch
    function getEpochClaimableAmount(
        uint256 _campaignId,
        address _gauge,
        uint256 _epochId
    )
        public
        view
        returns (uint256)
    {
        if (!isEpochClaimable(_campaignId, _epochId)) return 0;
        return _getEpochClaimableAmount(_campaignId, _gauge, _epochId);
    }

    // =========================================================================
    // External Functions
    // =========================================================================

    /// @inheritdoc IAllocatorStrategy
    /// @dev Creates a multi-epoch campaign with start and end epochs
    function setAllocationCampaign(uint256 _campaignId, bytes calldata _auxData) public override {
        if (msg.sender != owner() && msg.sender != address(dao())) {
            revert IAllocatorStrategy.OnlyDAOAllowed(msg.sender);
        }

        // Campaign shouldn't already exist
        if (campaigns[_campaignId].startEpoch != 0) {
            revert CampaignAlreadyExists(_campaignId);
        }

        // Decode epoch bounds
        (uint256 startEpoch, uint256 endEpoch) = abi.decode(_auxData, (uint256, uint256));

        // Validate epoch bounds
        if (startEpoch == 0) revert InvalidEpochBounds(startEpoch, endEpoch);
        if (endEpoch != 0 && startEpoch > endEpoch) revert InvalidEpochBounds(startEpoch, endEpoch);

        // Create new campaign
        MultiEpochGaugeAllocationCampaign storage campaign = campaigns[_campaignId];
        campaign.startEpoch = startEpoch;
        campaign.endEpoch = endEpoch;

        emit AllocationCampaignCreated(plugin, _campaignId);
    }

    /// @notice Sets the distribution amount for a specific epoch
    /// @param _campaignId Campaign identifier
    /// @param _epochId Epoch to set distribution for
    /// @param _amount Amount to distribute for this epoch
    function setEpochDistribution(uint256 _campaignId, uint256 _epochId, uint256 _amount) external {
        if (msg.sender != owner() && msg.sender != address(dao())) {
            revert IAllocatorStrategy.OnlyDAOAllowed(msg.sender);
        }

        if (_amount == 0) revert InvalidDistributionAmount();

        MultiEpochGaugeAllocationCampaign storage campaign = campaigns[_campaignId];

        // Validate campaign exists
        if (campaign.startEpoch == 0) revert CampaignNotFound(_campaignId);

        // Validate epoch is within campaign bounds
        if (_epochId < campaign.startEpoch) {
            revert EpochNotInCampaign(_epochId, campaign.startEpoch, campaign.endEpoch);
        }
        if (campaign.endEpoch > 0 && _epochId > campaign.endEpoch) {
            revert EpochNotInCampaign(_epochId, campaign.startEpoch, campaign.endEpoch);
        }

        // Can only set distribution for unsnapshotted epochs (future or current)
        if (snapshotter.isEpochSnapshotted(_epochId)) {
            revert EpochNotSnapshotted(_epochId);
        }

        campaign.epochDistributions[_epochId] = _amount;
    }

    /// @notice Sets distribution amounts for multiple epochs
    /// @param _campaignId Campaign identifier
    /// @param _epochIds Array of epoch IDs
    /// @param _amounts Array of distribution amounts
    function setMultipleEpochDistributions(
        uint256 _campaignId,
        uint256[] calldata _epochIds,
        uint256[] calldata _amounts
    )
        external
    {
        if (msg.sender != owner() && msg.sender != address(dao())) {
            revert IAllocatorStrategy.OnlyDAOAllowed(msg.sender);
        }

        if (_epochIds.length != _amounts.length) revert("Length mismatch");

        MultiEpochGaugeAllocationCampaign storage campaign = campaigns[_campaignId];

        // Validate campaign exists
        if (campaign.startEpoch == 0) revert CampaignNotFound(_campaignId);

        for (uint256 i = 0; i < _epochIds.length;) {
            uint256 epochId = _epochIds[i];
            uint256 amount = _amounts[i];

            if (amount == 0) revert InvalidDistributionAmount();

            // Validate epoch is within campaign bounds
            if (epochId < campaign.startEpoch) {
                revert EpochNotInCampaign(epochId, campaign.startEpoch, campaign.endEpoch);
            }
            if (campaign.endEpoch > 0 && epochId > campaign.endEpoch) {
                revert EpochNotInCampaign(epochId, campaign.startEpoch, campaign.endEpoch);
            }

            // Can only set distribution for unsnapshotted epochs
            if (snapshotter.isEpochSnapshotted(epochId)) {
                revert EpochNotSnapshotted(epochId);
            }

            campaign.epochDistributions[epochId] = amount;

            unchecked {
                ++i;
            }
        }
    }

    // =========================================================================
    // Storage Gap
    // =========================================================================

    /// @dev Storage gap to allow for future upgrades without storage collision.
    /// This contract adds 2 storage slots: snapshotter address and campaigns mapping.
    uint256[48] private __gap;
}
