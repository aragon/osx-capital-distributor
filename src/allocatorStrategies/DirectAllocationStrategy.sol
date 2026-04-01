// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { AllocatorStrategyBase } from "./AllocatorStrategyBase.sol";

/// @title DirectAllocationStrategy
/// @notice Strategy that stores fixed per-address allocations configured by the owner or DAO.
/// @dev Allocations are immutable once written. Claim accounting is handled by CapitalDistributorPlugin.
contract DirectAllocationStrategy is AllocatorStrategyBase {
    /// @notice Campaign metadata for direct allocations.
    struct DirectCampaign {
        bool initialized;
    }

    /// @notice Maps campaign ID to campaign metadata.
    mapping(uint256 campaignId => DirectCampaign) public directCampaigns;

    /// @notice Maps campaign ID and recipient to its allocated amount.
    mapping(uint256 campaignId => mapping(address recipient => uint256 amount)) private allocations;

    /// @notice Emitted when a direct campaign is initialized.
    event DirectCampaignInitialized(uint256 indexed campaignId);

    /// @notice Emitted when allocations are set for a campaign.
    event AllocationsSet(uint256 indexed campaignId, address[] recipients, uint256[] amounts);

    /// @notice Thrown when attempting to initialize a campaign twice.
    error CampaignAlreadyInitialized(uint256 campaignId);

    /// @notice Thrown when attempting to configure allocations for a campaign that is not initialized.
    error CampaignNotInitialized(uint256 campaignId);

    /// @notice Thrown when trying to set an allocation that already exists.
    error AllocationAlreadySet(uint256 campaignId, address recipient);

    /// @notice Thrown when allocation inputs are invalid.
    error InvalidAllocationInput();

    /// @notice Encodes initialization parameters (none required for this strategy).
    function encodeInitializationParams() external pure returns (bytes memory) {
        return "";
    }

    /// @notice Encodes parameters for campaign creation (none required for this strategy).
    function encodeSetAllocationCampaignParams() external pure returns (bytes memory) {
        return "";
    }

    /// @notice Encodes parameters for setting allocations to help off-chain tooling.
    function encodeSetAllocationsParams(address[] memory _recipients, uint256[] memory _amounts)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(_recipients, _amounts);
    }

    /// @notice Decodes parameters for setting allocations.
    function decodeSetAllocationsParams(bytes memory _data)
        public
        pure
        returns (address[] memory recipients, uint256[] memory amounts)
    {
        return abi.decode(_data, (address[], uint256[]));
    }

    /// @return types Empty string as this strategy does not require aux data for initialization.
    function getInitializationEncodingTypes() external pure override returns (string memory types) {
        return "";
    }

    /// @return types Empty string as this strategy does not require aux data when creating campaigns.
    function getCreationEncodingTypes() external pure override returns (string memory types) {
        return "";
    }

    /// @return types Empty string as this strategy does not require aux data for claims.
    function getClaimEncodingTypes() external pure override returns (string memory types) {
        return "";
    }

    /// @inheritdoc AllocatorStrategyBase
    function setAllocationCampaign(uint256 _campaignId, bytes calldata _auxData) public override ownerOrDao {
        if (directCampaigns[_campaignId].initialized) {
            revert CampaignAlreadyInitialized(_campaignId);
        }

        if (_auxData.length != 0) {
            revert InvalidAllocationInput();
        }

        directCampaigns[_campaignId].initialized = true;

        emit AllocationCampaignCreated(plugin, _campaignId);
        emit DirectCampaignInitialized(_campaignId);
    }

    /// @notice Sets allocations in batch for a campaign.
    /// @param _campaignId The campaign identifier.
    /// @param _recipients Array of recipients to receive allocations.
    /// @param _amounts Array of amounts corresponding to each recipient.
    function setAllocations(uint256 _campaignId, address[] calldata _recipients, uint256[] calldata _amounts)
        external
        ownerOrDao
    {
        if (!directCampaigns[_campaignId].initialized) {
            revert CampaignNotInitialized(_campaignId);
        }

        if (_recipients.length == 0 || _recipients.length != _amounts.length) {
            revert InvalidAllocationInput();
        }

        for (uint256 i = 0; i < _recipients.length; ++i) {
            _setAllocation(_campaignId, _recipients[i], _amounts[i]);
        }

        emit AllocationsSet(_campaignId, _recipients, _amounts);
    }

    /// @notice Sets an allocation for a single recipient.
    /// @param _campaignId The campaign identifier.
    /// @param _recipient The recipient of the allocation.
    /// @param _amount The amount allocated to the recipient.
    function setAllocation(uint256 _campaignId, address _recipient, uint256 _amount) external ownerOrDao {
        if (!directCampaigns[_campaignId].initialized) {
            revert CampaignNotInitialized(_campaignId);
        }

        _setAllocation(_campaignId, _recipient, _amount);

        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = _recipient;
        amounts[0] = _amount;

        emit AllocationsSet(_campaignId, recipients, amounts);
    }

    /// @notice Internal helper that writes an allocation after input validation.
    function _setAllocation(uint256 _campaignId, address _recipient, uint256 _amount) internal {
        if (_recipient == address(0) || _amount == 0) {
            revert InvalidAllocationInput();
        }

        if (allocations[_campaignId][_recipient] != 0) {
            revert AllocationAlreadySet(_campaignId, _recipient);
        }

        allocations[_campaignId][_recipient] = _amount;
    }

    /// @inheritdoc AllocatorStrategyBase
    function getTotalClaimableAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    )
        public
        view
        override
        returns (uint256 amount)
    {
        if (_auxData.length != 0) {
            return 0;
        }
        return allocations[_campaignId][_account];
    }

    /// @notice Returns the allocation for a given campaign and recipient.
    function getAllocation(uint256 _campaignId, address _recipient) external view returns (uint256) {
        return allocations[_campaignId][_recipient];
    }
}
