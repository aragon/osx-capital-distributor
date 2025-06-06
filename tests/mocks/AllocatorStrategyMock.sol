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
    /// @inheritdoc IAllocatorStrategy
    function setAllocationCampaign(uint256, bytes calldata) public pure override {
        return;
    }

    /// @inheritdoc IAllocatorStrategy
    function getClaimeableAmount(uint256, address, bytes calldata) public pure override returns (uint256 amount) {
        return 1 ether; // Mock logic: fixed payout of 1 ether
    }
}
