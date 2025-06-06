// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

/// @title IAllocatorStrategy
/// @author Your Name/Project
/// @notice Interface for all allocator strategies, defining a common set of functions
/// for interacting with different allocation and distribution mechanisms.
/// Implementing contracts will define the specific logic for allocation and eligibility.
interface IAllocatorStrategy {
    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when a new allocation campaign is created.
    /// @param _dao The address of the DAO creating the campaign.
    /// @param _campaignId The unique identifier for the newly created campaign.
    event AllocationCampaignCreated(address indexed _dao, uint256 indexed _campaignId);

    // =========================================================================
    // Errors
    // =========================================================================
    error OnlyDAOAllowed(address account);

    // =========================================================================
    // View Functions
    // =========================================================================

    /// @notice Called by the plugin only when creating a new campaign
    /// @param _campaignId The id of the campaign getting the payout from
    /// @param _auxData Strategy-specific auxiliary data. Pass `bytes("")` if not required by the strategy.
    function setAllocationCampaign(uint256 _campaignId, bytes calldata _auxData) external;

    /// @notice Retrieves the payout amount an account is entitled to based on the strategy.
    /// @dev This function calculates the potential payout. The actual claiming mechanism might be separate.
    /// The `_auxData` parameter allows for passing strategy-specific information required for the calculation,
    /// such as a Merkle proof, a signed message, or other contextual data.
    /// @param _campaignId The id of the campaign getting the payout from
    /// @param _account The address of the account for which to calculate the payout.
    /// @param _auxData Strategy-specific auxiliary data. Pass `bytes("")` if not required by the strategy.
    /// @return amount The amount of tokens/value the account is eligible to receive.
    function getClaimeableAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    ) external view returns (uint256 amount);
}
