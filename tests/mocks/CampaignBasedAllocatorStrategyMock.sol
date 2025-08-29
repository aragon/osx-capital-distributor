// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { IAllocatorStrategy } from "../../src/interfaces/IAllocatorStrategy.sol";
import { AllocatorStrategyBase } from "../../src/allocatorStrategies/AllocatorStrategyBase.sol";

/// @title CampaignBasedAllocatorStrategyMock
/// @notice A mock implementation that returns different amounts based on campaign ID
/// @dev Returns campaignId + 1 ether as the claimable amount
contract CampaignBasedAllocatorStrategyMock is AllocatorStrategyBase {
    /// @inheritdoc IAllocatorStrategy
    function setAllocationCampaign(uint256, bytes calldata) public pure override {
        return;
    }

    /// @inheritdoc IAllocatorStrategy
    function getClaimeableAmount(
        uint256 _campaignId,
        address,
        bytes calldata
    )
        public
        pure
        override
        returns (uint256 amount)
    {
        // Return campaignId + 1 ether
        // So campaign 0 returns 1 ether, campaign 1 returns 2 ether, etc.
        return (_campaignId + 1) * 1 ether;
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
