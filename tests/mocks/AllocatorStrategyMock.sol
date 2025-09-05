// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { IAllocatorStrategy } from "../../src/interfaces/IAllocatorStrategy.sol";
import { AllocatorStrategyBase } from "../../src/allocatorStrategies/AllocatorStrategyBase.sol";

/// @title AllocatorStrategyMock
/// @notice A mock implementation of AllocatorStrategyBase for testing purposes.
/// @dev This mock provides basic implementations for abstract functions:
///      - `isEligible` always returns `true`.
///      - `getPayoutAmount` always returns `1 ether`.
///      It also ensures that internal functions are protected by Aragon OSx's DaoAuthorizable.
contract AllocatorStrategyMock is AllocatorStrategyBase {
    /// @inheritdoc IAllocatorStrategy
    function setAllocationCampaign(uint256, bytes calldata) public pure override {
        return;
    }

    /// @inheritdoc IAllocatorStrategy
    function getTotalClaimableAmount(
        uint256 _campaignId,
        address,
        bytes calldata
    )
        public
        pure
        override
        returns (uint256 amount)
    {
        // Return different amounts based on campaign ID for testing
        if (_campaignId == 999) {
            return 0; // Special campaign ID for zero amount tests
        }
        return 1 ether; // Default: fixed payout of 1 ether
    }
}
