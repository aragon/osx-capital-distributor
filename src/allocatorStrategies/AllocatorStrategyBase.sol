// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {IAllocatorStrategy} from "../interfaces/IAllocatorStrategy.sol";
import {DaoAuthorizableUpgradeable} from "@aragon/commons/permission/auth/DaoAuthorizableUpgradeable.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";

/// @title AllocatorStrategyBase
/// @notice Base contract implementing the IAllocatorStrategy interface. All natspec is inherited.
abstract contract AllocatorStrategyBase is IAllocatorStrategy, DaoAuthorizableUpgradeable {
    // =========================================================================
    // State Variables
    // =========================================================================

    uint256 private epochDuration;
    bool private claimOpen;
    mapping(uint256 campaignId => mapping(address receiver => uint256 amount)) private payouts;

    // =========================================================================
    // Constructor
    // =========================================================================
    constructor() {
        // Disable initializers to prevent implementation contract from being initialized
        _disableInitializers();
    }

    // =========================================================================
    // Initializer
    // =========================================================================

    /// @notice Initializes the strategy with the given parameters
    /// @param _dao The DAO that will control this strategy
    /// @param _epochDuration The duration of each epoch in seconds
    /// @param _claimOpen Whether claims are initially open
    function initialize(IDAO _dao, uint256 _epochDuration, bool _claimOpen) public virtual initializer {
        __DaoAuthorizableUpgradeable_init(_dao);
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
    function setAllocationCampaign(uint256 _campaignId, bytes calldata _auxData) public virtual override;

    /// @inheritdoc IAllocatorStrategy
    function getClaimeableAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    ) public view virtual override returns (uint256 amount);

    /// @inheritdoc IAllocatorStrategy
    function setClaimeableAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    ) public virtual override returns (uint256 amount) {
        // Placeholder logic; should be implemented by derived contracts
        amount = getClaimeableAmount(_campaignId, _account, _auxData);
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
