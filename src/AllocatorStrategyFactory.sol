// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {DaoAuthorizable} from "@aragon/commons/permission/auth/DaoAuthorizable.sol";
import {IAllocatorStrategy} from "./interfaces/IAllocatorStrategy.sol";
import {IAllocatorStrategyFactory} from "./interfaces/IAllocatorStrategyFactory.sol";

/// @title AllocatorStrategyFactory
/// @author AragonX - 2025
/// @notice A factory/registry hybrid for managing and deploying allocator strategies.
/// @dev This contract allows registering strategy types and deploying instances on demand.
contract AllocatorStrategyFactory is IAllocatorStrategyFactory {
    using Clones for address;

    /// @notice Maps strategy type IDs to their configuration.
    mapping(bytes32 strategyTypeId => StrategyType) public strategyTypes;

    /// @notice Maps deployment parameters hash to deployed strategy addresses.
    mapping(bytes32 paramsHash => address strategy) public deployedStrategies;

    /// @notice Maps strategy addresses to their type IDs.
    mapping(address strategy => bytes32 strategyTypeId) public strategyToType;

    constructor() {}

    /**
     * @notice Registers a new strategy type in the factory.
     * @param _strategyId Unique identifier for the strategy type.
     * @param _implementation Address of the strategy implementation contract.
     * @param _metadata Human-readable name for the strategy type.
     */
    function registerStrategyType(bytes32 _strategyId, address _implementation, string calldata _metadata) external {
        if (strategyTypes[_strategyId].implementation != address(0)) {
            revert StrategyTypeAlreadyExists(_strategyId);
        }
        if (_implementation == address(0)) {
            revert InvalidImplementation(_implementation);
        }
        if (_strategyId.length == 0) {
            revert EmptyStrategyName();
        }

        strategyTypes[_strategyId] = StrategyType({implementation: _implementation, metadata: _metadata});

        emit StrategyTypeRegistered(_strategyId, _implementation, _metadata, msg.sender);
    }

    /**
     * @notice Deploys a new instance of a registered strategy type.
     * @param _strategyTypeId The strategy type to deploy.
     * @param _params Deployment parameters for the strategy.
     * @return strategy The address of the deployed strategy.
     */
    function deployStrategy(
        bytes32 _strategyTypeId,
        IDAO _dao,
        DeploymentParams calldata _params
    ) public returns (address strategy) {
        StrategyType storage strategyType = strategyTypes[_strategyTypeId];

        if (strategyType.implementation == address(0)) {
            revert StrategyTypeNotFound(_strategyTypeId);
        }

        bytes32 paramsHash = _computeParamsHash(_strategyTypeId, _dao, _params);

        // Check if strategy with these parameters already exists
        if (deployedStrategies[paramsHash] != address(0)) {
            revert StrategyAlreadyDeployed(paramsHash, deployedStrategies[paramsHash]);
        }

        // Deploy strategy using Clones
        strategy = strategyType.implementation.clone();

        // Initialize the strategy
        bytes memory initCalldata = abi.encodeWithSignature(
            "initialize(address,uint256,bool)",
            _dao,
            _params.epochDuration,
            _params.claimOpen
        );

        (bool success, ) = strategy.call(initCalldata);
        if (!success) {
            revert StrategyDeploymentFailed(_strategyTypeId);
        }

        // Register the deployed strategy
        deployedStrategies[paramsHash] = strategy;
        strategyToType[strategy] = _strategyTypeId;

        emit StrategyDeployed(_strategyTypeId, strategy, paramsHash, msg.sender);

        return strategy;
    }

    /**
     * @notice Gets an existing strategy instance or deploys a new one if it doesn't exist.
     * @param _strategyTypeId The strategy type to get or deploy.
     * @param _params Deployment parameters for the strategy.
     * @return strategy The address of the existing or newly deployed strategy.
     */
    function getOrDeployStrategy(
        bytes32 _strategyTypeId,
        IDAO _dao,
        DeploymentParams calldata _params
    ) external returns (address strategy) {
        bytes32 paramsHash = _computeParamsHash(_strategyTypeId, _dao, _params);

        strategy = deployedStrategies[paramsHash];
        if (strategy != address(0)) {
            return strategy;
        }

        return deployStrategy(_strategyTypeId, _dao, _params);
    }

    /**
     * @notice Checks if a strategy with given parameters already exists.
     * @param _strategyTypeId The strategy type ID.
     * @param _params Deployment parameters.
     * @return exists True if the strategy exists, false otherwise.
     * @return strategy The address of the existing strategy (zero if doesn't exist).
     */
    function strategyExists(
        bytes32 _strategyTypeId,
        IDAO _dao,
        DeploymentParams calldata _params
    ) external view returns (bool exists, address strategy) {
        bytes32 paramsHash = _computeParamsHash(_strategyTypeId, _dao, _params);
        strategy = deployedStrategies[paramsHash];
        exists = strategy != address(0);
    }

    /**
     * @notice Gets the strategy type information.
     * @param _strategyTypeId The strategy type ID.
     * @return strategyType The strategy type configuration.
     */
    function getStrategyType(bytes32 _strategyTypeId) external view returns (StrategyType memory strategyType) {
        return strategyTypes[_strategyTypeId];
    }

    /**
     * @notice Computes a unique hash for deployment parameters.
     * @param _strategyTypeId The strategy type ID.
     * @param _params Deployment parameters.
     * @return paramsHash The computed hash.
     */
    function _computeParamsHash(
        bytes32 _strategyTypeId,
        IDAO _dao,
        DeploymentParams calldata _params
    ) internal pure returns (bytes32 paramsHash) {
        return
            keccak256(
                abi.encodePacked(_strategyTypeId, _dao, _params.epochDuration, _params.claimOpen, _params.auxData)
            );
    }
}
