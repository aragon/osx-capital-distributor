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

    /// @notice Emitted when the duration of an epoch is updated by the strategy.
    /// @param newEpochDuration The new duration for epochs, in seconds.
    event EpochDurationUpdated(uint256 newEpochDuration);

    /// @notice Emitted when the claim period status changes (e.g., opened or closed).
    /// @param isOpen True if the claim period is now open, false otherwise.
    event ClaimPeriodStatusChanged(bool isOpen);

    /// @notice Emitted when a payout is successfully claimed or processed for a recipient.
    /// @param recipient The address of the account that received the payout.
    /// @param amount The amount of tokens/value paid out.
    /// @param auxData Additional data associated with the claim, specific to the strategy (e.g., proof data).
    event PayoutClaimed(address indexed recipient, uint256 amount, bytes auxData);

    /// @notice Emitted when an account's eligibility status is confirmed or changes.
    /// @dev This event can be used by strategies to signal changes or confirmations of eligibility,
    /// potentially triggered by checks or updates to the underlying eligibility criteria.
    /// @param account The address of the account whose eligibility was assessed.
    /// @param isEligible True if the account is eligible, false otherwise.
    event EligibilityStatus(address indexed account, bool isEligible);

    // =========================================================================
    // Errors
    // =========================================================================
    error OnlyDAOAllowed(address account);

    // =========================================================================
    // View Functions
    // =========================================================================

    /// @notice Gets the configured duration of a single epoch for this strategy.
    /// @return duration The epoch duration in seconds. Returns 0 if not applicable.
    function getEpochDuration() external view returns (uint256 duration);

    /// @notice Gets the time remaining in the current epoch, if applicable.
    /// @return timeLeft The time left in seconds for the current epoch to conclude.
    /// Returns 0 if not in an active epoch or if epochs are not applicable.
    function getEpochTimeLeft() external view returns (uint256 timeLeft);

    /// @notice Checks if the claim window is currently open according to the strategy's rules.
    /// @return isOpen True if claims can be made at the time of calling, false otherwise.
    function isClaimOpen() external view returns (bool isOpen);

    /// @notice Checks if a specific account is eligible for a payout according to the strategy's rules
    /// and current state.
    /// @param _campaignId The id of the campaign getting the payout from
    /// @param _account The address of the account to check for eligibility.
    /// @param _auxData Strategy-specific auxiliary data. Pass `bytes("")` if not required by the strategy.
    /// @return eligible True if the account is eligible for a payout, false otherwise.
    function isEligible(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    ) external view returns (bool eligible);

    /// @notice Retrieves the payout amount an account is entitled to based on the strategy.
    /// @dev This function calculates the potential payout. The actual claiming mechanism might be separate.
    /// The `_auxData` parameter allows for passing strategy-specific information required for the calculation,
    /// such as a Merkle proof, a signed message, or other contextual data.
    /// @param _campaignId The id of the campaign getting the payout from
    /// @param _account The address of the account for which to calculate the payout.
    /// @param _auxData Strategy-specific auxiliary data. Pass `bytes("")` if not required by the strategy.
    /// @return amount The amount of tokens/value the account is eligible to receive.
    function getPayoutAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    ) external view returns (uint256 amount);

    /// @notice Sets the payout amount an account is entitled to based on the strategy.
    /// @dev This function calculates the potential payout. The actual claiming mechanism might be separate.
    /// The `_auxData` parameter allows for passing strategy-specific information required for the calculation,
    /// such as a Merkle proof, a signed message, or other contextual data.
    /// @param _campaignId The id of the campaign getting the payout from
    /// @param _account The address of the account for which to calculate the payout.
    /// @param _auxData Strategy-specific auxiliary data. Pass `bytes("")` if not required by the strategy.
    /// @return amount The amount of tokens/value the account is eligible to receive.
    function setPayoutAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    ) external returns (uint256 amount);
}
