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
    function initialize(IDAO _dao) public virtual initializer {
        __DaoAuthorizableUpgradeable_init(_dao);
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
