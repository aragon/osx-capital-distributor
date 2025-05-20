// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {IAllocatorStrategy} from "../interfaces/IAllocatorStrategy.sol";
import {DaoAuthorizable} from "@aragon/commons/permission/auth/DaoAuthorizable.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";

/// @title AllocatorStrategyBase
/// @notice Base contract implementing the IAllocatorStrategy interface. All natspec is inherited.
abstract contract AllocatorStrategyBase is IAllocatorStrategy, DaoAuthorizable {
    // =========================================================================
    // State Variables
    // =========================================================================

    uint256 private epochDuration;
    bool private claimOpen;
    mapping(uint256 campaignId => mapping(address receiver => uint256 amount)) private payouts;

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor(IDAO _dao, uint256 _epochDuration, bool _claimOpen) DaoAuthorizable(_dao) {
        epochDuration = _epochDuration;
        claimOpen = _claimOpen;
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /// @inheritdoc IAllocatorStrategy
    function getEpochDuration() public view virtual override returns (uint256 duration) {
        return epochDuration;
    }

    /// @inheritdoc IAllocatorStrategy
    function getEpochTimeLeft() public view virtual override returns (uint256 timeLeft) {
        return getEpochDuration();
    }

    /// @inheritdoc IAllocatorStrategy
    function isClaimOpen() public view virtual override returns (bool isOpen) {
        return claimOpen;
    }

    /// @inheritdoc IAllocatorStrategy
    function isEligible(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    ) public view virtual override returns (bool eligible) {
        // Placeholder logic; should be implemented by derived contracts
        return false;
    }

    /// @inheritdoc IAllocatorStrategy
    function getPayoutAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    ) public view virtual override returns (uint256 amount) {
        // Placeholder logic; should be implemented by derived contracts
        return 0;
    }

    /// @inheritdoc IAllocatorStrategy
    function setPayoutAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    ) public virtual override returns (uint256 amount) {
        // Placeholder logic; should be implemented by derived contracts
        amount = getPayoutAmount(_campaignId, _account, _auxData);
        payouts[_campaignId][_account] = amount;
        return amount;
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    /// @notice Internal function to update the epoch duration.
    /// @param _newEpochDuration The new duration for epochs, in seconds.
    function _updateEpochDuration(uint256 _newEpochDuration) internal {
        epochDuration = _newEpochDuration;
        emit EpochDurationUpdated(_newEpochDuration);
    }

    /// @notice Internal function to update the claim period status.
    /// @param _isOpen True if the claim period is now open, false otherwise.
    function _updateClaimPeriodStatus(bool _isOpen) internal {
        claimOpen = _isOpen;
        emit ClaimPeriodStatusChanged(_isOpen);
    }
}
