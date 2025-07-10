// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {IAllocatorStrategy} from "../interfaces/IAllocatorStrategy.sol";
import {DaoAuthorizableUpgradeable} from "@aragon/commons/permission/auth/DaoAuthorizableUpgradeable.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";

/// @title AllocatorStrategyBase
/// @notice Base contract implementing the IAllocatorStrategy interface.
/// @dev Provides common functionality for allocation strategies. Implementing contracts should override
/// abstract functions to define specific allocation logic.
abstract contract AllocatorStrategyBase is IAllocatorStrategy, DaoAuthorizableUpgradeable {
    bytes32 public strategyTypeId;

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
    /// @param _strategyTypeId The type ID of the strategy
    /// @param _dao The DAO that will control this strategy
    function initialize(bytes32 _strategyTypeId, IDAO _dao, bytes calldata) public virtual initializer {
        __DaoAuthorizableUpgradeable_init(_dao);

        strategyTypeId = _strategyTypeId;
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /// @inheritdoc IAllocatorStrategy
    function setAllocationCampaign(uint256 _campaignId, bytes calldata _auxData) public virtual override;

    /// @inheritdoc IAllocatorStrategy
    function getClaimeableAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    ) public view virtual override returns (uint256 amount);
}
