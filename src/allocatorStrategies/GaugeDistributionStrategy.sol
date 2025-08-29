// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { IAllocatorStrategy } from "../interfaces/IAllocatorStrategy.sol";
import { AllocatorStrategyBase } from "./AllocatorStrategyBase.sol";
import { IGaugeVoterSnapshotter } from "../interfaces/helpers/IGaugeVoterSnapshotter.sol";
import { IAddressGaugeVoter } from "../interfaces/helpers/IAddressGaugeVoter.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";

/// @title GaugeDistributionStrategy
/// @notice Allocator strategy that distributes tokens to gauges across multiple epochs based on historical vote data
/// @dev Supports campaigns that span multiple epochs with flexible distribution amounts per epoch
/// @dev The plugin tracks claims, this strategy only calculates accumulated unclaimed amounts
contract GaugeDistributionStrategy is AllocatorStrategyBase {
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
    error CannotLowerDistribution(uint256 epochId, uint256 currentAmount, uint256 newAmount);

    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice Reference to the gauge voter snapshotter
    IGaugeVoterSnapshotter public snapshotter;

    /// @notice Reference to the gauge voter contract
    IAddressGaugeVoter public gaugeVoter;

    /// @notice Campaign-specific configuration
    mapping(uint256 campaignId => GaugeDistributionCampaign) public campaigns;

    /// @notice Campaign data structure
    struct GaugeDistributionCampaign {
        uint256 startEpoch; // First epoch of the campaign
        uint256 endEpoch; // Last epoch (0 = continuous)
        uint256 lastProcessedEpoch; // Last epoch processed into claimableSum (common to all gauges)
        mapping(uint256 => uint256) epochDistributions; // epoch => amount to distribute
        mapping(address => uint256) claimableSum; // gauge => accumulated amount up to lastProcessedEpoch
    }

    // =========================================================================
    // Modifiers
    // =========================================================================

    /// @notice Ensures the caller is authorized (owner or DAO)
    modifier onlyAuthorized() {
        if (msg.sender != owner() && msg.sender != address(dao())) {
            revert IAllocatorStrategy.OnlyDAOAllowed(msg.sender);
        }
        _;
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
        gaugeVoter = IAddressGaugeVoter(_snapshotter.gaugeVoter());
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
    /// @dev Uses accumulated claimableSum for past epochs and calculates only unprocessed epochs
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
        GaugeDistributionCampaign storage campaign = campaigns[_campaignId];

        // Validate campaign exists
        _validateCampaignExists(_campaignId);

        // Get accumulated amount for this gauge
        uint256 totalClaimable = campaign.claimableSum[_account];

        // Determine the range of epochs to check
        uint256 currentEpoch = _getCurrentEpoch();
        uint256 endEpoch = _getEffectiveEndEpoch(campaign, currentEpoch);

        // Start from where we left off processing
        uint256 startFrom = _getNextUnprocessedEpoch(campaign);

        // Only calculate epochs not yet processed
        for (uint256 epoch = startFrom; epoch <= endEpoch;) {
            // For current epoch, we don't need snapshot; for past epochs we do
            bool isEligible = (epoch == currentEpoch) || snapshotter.isEpochSnapshotted(epoch);

            // Only add if eligible and has distribution
            if (isEligible && campaign.epochDistributions[epoch] > 0) {
                totalClaimable += _getEpochClaimableAmount(campaign, _account, epoch);
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
        GaugeDistributionCampaign storage campaign,
        address _gauge,
        uint256 _epochId
    )
        internal
        view
        returns (uint256)
    {
        // Validate epoch is within campaign bounds
        if (!_isEpochInCampaign(campaign, _epochId)) {
            return 0;
        }

        // Check if distribution is set for this epoch
        uint256 epochDistribution = campaign.epochDistributions[_epochId];
        if (epochDistribution == 0) {
            return 0;
        }

        uint256 currentEpoch = _getCurrentEpoch();
        uint256 gaugeVotes;
        uint256 totalVotingPowerCast;

        if (_epochId == currentEpoch) {
            // For current epoch, always use live data from gauge voter
            gaugeVotes = gaugeVoter.gaugeVotes(_gauge);
            totalVotingPowerCast = gaugeVoter.totalVotingPowerCast();
        } else {
            // For past epochs, require snapshot
            if (!snapshotter.isEpochSnapshotted(_epochId)) {
                return 0;
            }

            gaugeVotes = snapshotter.getGaugeVotes(_epochId, _gauge);
            totalVotingPowerCast = snapshotter.getTotalVotingPowerCast(_epochId);
        }

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

    /// @notice Checks if an epoch can be claimed
    /// @param _campaignId Campaign identifier
    /// @param _epochId Epoch to check
    /// @return True if epoch is claimable
    function isEpochClaimable(uint256 _campaignId, uint256 _epochId) public view returns (bool) {
        GaugeDistributionCampaign storage campaign = campaigns[_campaignId];

        // Check campaign exists
        if (campaign.startEpoch == 0) return false;

        // Check epoch bounds
        if (!_isEpochInCampaign(campaign, _epochId)) return false;

        // Check if has distribution
        if (campaign.epochDistributions[_epochId] == 0) return false;

        uint256 currentEpoch = _getCurrentEpoch();

        // Current epoch is always claimable if it has distribution
        if (_epochId == currentEpoch) return true;

        // Past epochs require snapshot
        return snapshotter.isEpochSnapshotted(_epochId);
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
        return _getEpochClaimableAmount(campaigns[_campaignId], _gauge, _epochId);
    }

    // =========================================================================
    // Internal ClaimableSum Functions
    // =========================================================================

    /// @notice Calculate a gauge's share for a specific epoch
    /// @param _campaign Campaign storage reference
    /// @param _gauge Gauge address
    /// @param _epochId Epoch to calculate for
    /// @return The gauge's share of the distribution for this epoch
    function _calculateGaugeShare(
        GaugeDistributionCampaign storage _campaign,
        address _gauge,
        uint256 _epochId
    )
        internal
        view
        returns (uint256)
    {
        uint256 distribution = _campaign.epochDistributions[_epochId];
        uint256 gaugeVotes = snapshotter.getGaugeVotes(_epochId, _gauge);
        uint256 totalVotes = snapshotter.getTotalVotingPowerCast(_epochId);

        if (totalVotes == 0) return 0;
        return (gaugeVotes * distribution) / totalVotes;
    }

    /// @notice Sum epochs distributions per gauge up to a specific epoch
    /// @param _campaign Campaign object
    function _processEpochs(GaugeDistributionCampaign storage _campaign) internal {
        address[] memory gauges = gaugeVoter.getAllGauges();

        uint256 startFrom = _getNextUnprocessedEpoch(_campaign);
        uint256 endAt = _getEffectiveEndEpoch(_campaign, _getCurrentEpoch());

        // Only process up to current epoch - 1 (completed epochs only)
        uint256 currentEpoch = _getCurrentEpoch();
        if (endAt >= currentEpoch) {
            endAt = currentEpoch - 1;
        }

        uint256 lastProcessed = _campaign.lastProcessedEpoch;

        // Process all epochs from last processed to current epoch (or endAt)
        for (uint256 epoch = startFrom; epoch <= endAt;) {
            if (_campaign.epochDistributions[epoch] > 0 && snapshotter.isEpochSnapshotted(epoch)) {
                // Process this epoch for all gauges
                for (uint256 i = 0; i < gauges.length;) {
                    address gauge = gauges[i];
                    _campaign.claimableSum[gauge] += _calculateGaugeShare(_campaign, gauge, epoch);

                    unchecked {
                        ++i;
                    }
                }
                // Update lastProcessed only if we actually processed this epoch
                lastProcessed = epoch;
            }

            unchecked {
                ++epoch;
            }
        }

        // Only update if we processed any epochs
        if (lastProcessed > _campaign.lastProcessedEpoch) {
            _campaign.lastProcessedEpoch = lastProcessed;
        }
    }

    /// @notice Recalculate claimableSum for an epoch when distribution changes
    /// @param _campaign Campaign storage reference
    /// @param _epochId The epoch being updated
    /// @param _oldDistribution The previous distribution amount
    /// @param _newDistribution The new distribution amount
    function _recalculateSum(
        GaugeDistributionCampaign storage _campaign,
        uint256 _epochId,
        uint256 _oldDistribution,
        uint256 _newDistribution
    )
        internal
    {
        // Only update if this epoch is within the processed range
        address[] memory gauges = gaugeVoter.getAllGauges();

        for (uint256 i = 0; i < gauges.length;) {
            address gauge = gauges[i];
            uint256 gaugeVotes = snapshotter.getGaugeVotes(_epochId, gauge);
            uint256 totalVotes = snapshotter.getTotalVotingPowerCast(_epochId);

            if (totalVotes > 0) {
                uint256 oldAmount = (gaugeVotes * _oldDistribution) / totalVotes;
                uint256 newAmount = (gaugeVotes * _newDistribution) / totalVotes;

                // Update claimableSum with the difference
                _campaign.claimableSum[gauge] = _campaign.claimableSum[gauge] - oldAmount + newAmount;
            }

            unchecked {
                ++i;
            }
        }
    }

    // =========================================================================
    // Validation Helper Functions
    // =========================================================================

    /// @notice Validates that a campaign exists
    /// @param _campaignId Campaign identifier
    function _validateCampaignExists(uint256 _campaignId) internal view {
        if (campaigns[_campaignId].startEpoch == 0) {
            revert CampaignNotFound(_campaignId);
        }
    }

    /// @notice Checks if an epoch is within campaign bounds
    /// @param _campaign Campaign storage reference
    /// @param _epochId Epoch to check
    /// @return True if epoch is within campaign bounds
    function _isEpochInCampaign(
        GaugeDistributionCampaign storage _campaign,
        uint256 _epochId
    )
        internal
        view
        returns (bool)
    {
        if (_epochId < _campaign.startEpoch) {
            return false;
        }
        if (_campaign.endEpoch > 0 && _epochId > _campaign.endEpoch) {
            return false;
        }
        return true;
    }

    /// @notice Validates epoch is within campaign bounds, reverts if not
    /// @param _campaign Campaign storage reference
    /// @param _epochId Epoch to validate
    function _validateEpochInCampaign(GaugeDistributionCampaign storage _campaign, uint256 _epochId) internal view {
        if (_epochId < _campaign.startEpoch) {
            revert EpochNotInCampaign(_epochId, _campaign.startEpoch, _campaign.endEpoch);
        }
        if (_campaign.endEpoch > 0 && _epochId > _campaign.endEpoch) {
            revert EpochNotInCampaign(_epochId, _campaign.startEpoch, _campaign.endEpoch);
        }
    }

    /// @notice Validates that a past epoch has a snapshot
    /// @param _epochId Epoch to validate
    /// @param _currentEpoch Current epoch
    function _validatePastEpochHasSnapshot(uint256 _epochId, uint256 _currentEpoch) internal view {
        if (_epochId < _currentEpoch && !snapshotter.isEpochSnapshotted(_epochId)) {
            revert EpochNotSnapshotted(_epochId);
        }
    }

    // =========================================================================
    // Utility Functions
    // =========================================================================

    /// @notice Gets the next unprocessed epoch for accumulation
    /// @param _campaign Campaign storage reference
    /// @return The epoch to start processing from
    function _getNextUnprocessedEpoch(GaugeDistributionCampaign storage _campaign) internal view returns (uint256) {
        return _campaign.lastProcessedEpoch > 0 ? _campaign.lastProcessedEpoch + 1 : _campaign.startEpoch;
    }

    /// @notice Gets the effective end epoch for a campaign
    /// @param _campaign Campaign storage reference
    /// @param _currentEpoch Current epoch
    /// @return The effective end epoch (considering continuous campaigns)
    function _getEffectiveEndEpoch(
        GaugeDistributionCampaign storage _campaign,
        uint256 _currentEpoch
    )
        internal
        view
        returns (uint256)
    {
        uint256 endEpoch = _campaign.endEpoch == 0 ? _currentEpoch : _campaign.endEpoch;
        return endEpoch > _currentEpoch ? _currentEpoch : endEpoch;
    }

    // =========================================================================
    // External Functions
    // =========================================================================

    /// @inheritdoc IAllocatorStrategy
    /// @dev Creates a multi-epoch campaign with start and end epochs
    function setAllocationCampaign(uint256 _campaignId, bytes calldata _auxData) public override onlyAuthorized {
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
        GaugeDistributionCampaign storage campaign = campaigns[_campaignId];
        campaign.startEpoch = startEpoch;
        campaign.endEpoch = endEpoch;

        emit AllocationCampaignCreated(plugin, _campaignId);
    }

    /// @notice Sets the distribution amount for a specific epoch
    /// @param _campaignId Campaign identifier
    /// @param _epochId Epoch to set distribution for
    /// @param _amount Amount to distribute for this epoch
    function setEpochDistribution(uint256 _campaignId, uint256 _epochId, uint256 _amount) external onlyAuthorized {
        GaugeDistributionCampaign storage campaign = campaigns[_campaignId];
        uint256 currentEpoch = _getCurrentEpoch();

        // Validate params
        {
            if (_amount == 0) revert InvalidDistributionAmount();

            // Validate campaign exists
            _validateCampaignExists(_campaignId);

            // Validate epoch is within campaign bounds
            _validateEpochInCampaign(campaign, _epochId);

            // Validate that if epoch is in the past, it has a snapshot
            _validatePastEpochHasSnapshot(_epochId, currentEpoch);
        }

        _setEpochDistribution(campaign, _epochId, _amount, currentEpoch);
    }

    function _setEpochDistribution(
        GaugeDistributionCampaign storage _campaign,
        uint256 _epochId,
        uint256 _amount,
        uint256 currentEpoch
    )
        internal
    {
        uint256 epochDistribution = _campaign.epochDistributions[_epochId];

        // Prevent lowering distribution amount
        if (_amount < epochDistribution) {
            revert CannotLowerDistribution(_epochId, epochDistribution, _amount);
        }

        // Check if we need to recalculate existing sum up values
        if (epochDistribution > 0 && _epochId <= _campaign.lastProcessedEpoch) {
            _recalculateSum(_campaign, _epochId, epochDistribution, _amount);
        }

        // Update the distribution
        _campaign.epochDistributions[_epochId] = _amount;

        // Only process if this is a new high water mark
        if (_epochId < currentEpoch) {
            // Process sum for last epochs
            _processEpochs(_campaign);
        }
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
        onlyAuthorized
    {
        if (_epochIds.length != _amounts.length) revert("Length mismatch");

        GaugeDistributionCampaign storage campaign = campaigns[_campaignId];
        uint256 currentEpoch = _getCurrentEpoch();

        // Validate campaign exists once
        _validateCampaignExists(_campaignId);

        for (uint256 i = 0; i < _epochIds.length; i++) {
            uint256 epochId = _epochIds[i];
            uint256 amount = _amounts[i];

            if (amount == 0) revert InvalidDistributionAmount();

            // Validate epoch is within campaign bounds
            _validateEpochInCampaign(campaign, epochId);

            // Validate that if epoch is in the past, it has a snapshot
            _validatePastEpochHasSnapshot(epochId, currentEpoch);

            // Set the distribution
            _setEpochDistribution(campaign, epochId, amount, currentEpoch);
        }
    }

    // =========================================================================
    // Storage Gap
    // =========================================================================

    /// @dev Storage gap to allow for future upgrades without storage collision.
    /// This contract adds 3 storage slots: snapshotter, gaugeVoter, and campaigns mapping.
    uint256[47] private __gap;
}
