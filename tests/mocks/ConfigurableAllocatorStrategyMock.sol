// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {IAllocatorStrategy} from "../../src/interfaces/IAllocatorStrategy.sol";
import {AllocatorStrategyBase} from "../../src/allocatorStrategies/AllocatorStrategyBase.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";

/// @title ConfigurableAllocatorStrategyMock
/// @notice A configurable mock implementation of AllocatorStrategyBase for testing.
/// @dev Allows setting custom claimable amounts per campaign and recipient.
contract ConfigurableAllocatorStrategyMock is AllocatorStrategyBase {
    mapping(uint256 campaignId => mapping(address recipient => uint256 amount)) public claimableAmounts;
    mapping(uint256 campaignId => uint256 defaultAmount) public defaultClaimableAmounts;

    /// @notice Sets the claimable amount for a specific recipient in a campaign
    function setClaimableAmount(uint256 _campaignId, address _recipient, uint256 _amount) external {
        claimableAmounts[_campaignId][_recipient] = _amount;
    }

    /// @notice Sets the default claimable amount for a campaign
    function setDefaultClaimableAmount(uint256 _campaignId, uint256 _amount) external {
        defaultClaimableAmounts[_campaignId] = _amount;
    }

    /// @inheritdoc IAllocatorStrategy
    function setAllocationCampaign(uint256 /* _campaignId */, bytes calldata) public pure override {
        // Mock implementation - do nothing
        return;
    }

    /// @inheritdoc IAllocatorStrategy
    function getClaimeableAmount(
        uint256 _campaignId,
        address _recipient,
        bytes calldata
    ) public view override returns (uint256 amount) {
        // First check if there's a specific amount set for this recipient
        amount = claimableAmounts[_campaignId][_recipient];
        
        // If no specific amount, use the default for the campaign
        if (amount == 0) {
            amount = defaultClaimableAmounts[_campaignId];
        }
        
        return amount;
    }

    /// @inheritdoc IAllocatorStrategy
    function getInitializationEncodingTypes() external pure override returns (string memory types) {
        return ""; // This strategy doesn't use auxData for initialization
    }

    /// @inheritdoc IAllocatorStrategy
    function getCreationEncodingTypes() external pure override returns (string memory types) {
        return "";
    }

    /// @inheritdoc IAllocatorStrategy
    function getClaimEncodingTypes() external pure override returns (string memory types) {
        return "";
    }
}