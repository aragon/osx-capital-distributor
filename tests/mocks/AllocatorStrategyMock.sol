// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {IAllocatorStrategy} from "../../src/interfaces/IAllocatorStrategy.sol";
import {AllocatorStrategyBase} from "../../src/allocatorStrategies/AllocatorStrategyBase.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";

/// @title AllocatorStrategyMock
/// @notice A mock implementation of AllocatorStrategyBase for testing purposes.
/// @dev This mock provides basic implementations for abstract functions:
///      - `isEligible` always returns `true`.
///      - `getPayoutAmount` always returns `1 ether`.
///      It also ensures that internal functions are protected by Aragon OSx's DaoAuthorizable.
contract AllocatorStrategyMock is AllocatorStrategyBase {
    constructor(
        IDAO _dao,
        uint256 _epochDuration,
        bool _claimOpen
    ) AllocatorStrategyBase(_dao, _epochDuration, _claimOpen) {}

    /// @inheritdoc IAllocatorStrategy
    function isEligible(address _account) public view override returns (bool eligible) {
        return true; // Mock logic: always eligible
    }

    /// @inheritdoc IAllocatorStrategy
    function getPayoutAmount(address _account, bytes calldata _auxData) public view override returns (uint256 amount) {
        return 1 ether; // Mock logic: fixed payout of 1 ether
    }

    /// @notice Exposes the internal `_updateEpochDuration` function for testing.
    /// @dev This function is protected by DaoAuthorizable.
    function updateEpochDuration(uint256 _newEpochDuration) public {
        if (msg.sender != address(dao())) revert OnlyDAOAllowed(msg.sender);
        _updateEpochDuration(_newEpochDuration);
    }

    /// @notice Exposes the internal `_updateClaimPeriodStatus` function for testing.
    /// @dev This function is protected by DaoAuthorizable.
    function updateClaimPeriodStatus(bool _isOpen) public {
        if (msg.sender != address(dao())) revert OnlyDAOAllowed(msg.sender);
        _updateClaimPeriodStatus(_isOpen);
    }
}
