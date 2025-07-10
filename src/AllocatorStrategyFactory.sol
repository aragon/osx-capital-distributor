// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {IAllocatorStrategy} from "./interfaces/IAllocatorStrategy.sol";
import {IAllocatorStrategyFactory} from "./interfaces/IAllocatorStrategyFactory.sol";
import {FactoryBase} from "./FactoryBase.sol";

/// @title AllocatorStrategyFactory
/// @author AragonX - 2025
/// @notice A factory/registry hybrid for managing and deploying allocator strategies.
/// @dev This contract allows registering strategy types and deploying instances on demand.
contract AllocatorStrategyFactory is FactoryBase, IAllocatorStrategyFactory {
    using Clones for address;

    /// @notice Maps deployment parameters hash to deployed strategy addresses.
    mapping(bytes32 deploymentId => address strategy) public deployedInstances;

    /// @notice Maps strategy addresses to their type IDs.
    mapping(address instance => bytes32 typeId) public instanceToType;

    /// @notice Emitted when a new strategy type is registered
    /// @param strategyId The unique identifier for the strategy type
    /// @param implementation The address of the implementation contract
    /// @param metadata The metadata associated with the strategy type
    event StrategyTypeRegistered(bytes32 indexed strategyId, address indexed implementation, string metadata);

    /// @notice Emitted when a strategy instance is deployed
    /// @param strategyId The unique identifier for the strategy type
    /// @param strategy The address of the deployed strategy
    event StrategyDeployed(bytes32 indexed strategyId, address indexed strategy);

    /**
     * @notice Registers a new strategy type in the factory.
     * @param _strategyId Unique identifier for the strategy type.
     * @param _implementation Address of the strategy implementation contract.
     * @param _metadata Human-readable name for the strategy type.
     */
    function registerStrategyType(bytes32 _strategyId, address _implementation, string calldata _metadata) external {
        _registerType(_strategyId, _implementation, _metadata);
        emit StrategyTypeRegistered(_strategyId, _implementation, _metadata);
    }

    /**
     * @notice Deploys a new instance of a registered strategy type.
     * @param _strategyTypeId The strategy type to deploy.
     * @param _dao The DAO address for initialization.
     * @param _auxData Additional deployment parameters.
     * @return strategy The address of the deployed strategy.
     */
    function deployStrategy(
        bytes32 _strategyTypeId,
        IDAO _dao,
        bytes calldata _auxData
    ) public returns (address strategy) {
        bytes32 deploymentId = _computeParamsHash(_strategyTypeId, _dao, _auxData);

        // Check if strategy with these parameters already exists
        address existingStrategy = deployedInstances[deploymentId];
        if (existingStrategy != address(0)) {
            revert InstanceAlreadyDeployed(deploymentId, existingStrategy);
        }

        return _deployStrategy(_strategyTypeId, _dao, _auxData, deploymentId);
    }

    /**
     * @notice Gets an existing strategy instance or deploys a new one if it doesn't exist.
     * @param _strategyTypeId The strategy type to get or deploy.
     * @param _dao The DAO address for initialization.
     * @param _auxData Additional deployment parameters.
     * @return strategy The address of the existing or newly deployed strategy.
     */
    function getOrDeployStrategy(
        bytes32 _strategyTypeId,
        IDAO _dao,
        bytes calldata _auxData
    ) external returns (address strategy) {
        bytes32 deploymentId = _computeParamsHash(_strategyTypeId, _dao, _auxData);

        strategy = deployedInstances[deploymentId];
        if (strategy != address(0)) {
            return strategy;
        }

        return _deployStrategy(_strategyTypeId, _dao, _auxData, deploymentId);
    }

    /**
     * @notice Checks if a strategy with given parameters already exists.
     * @param _strategyTypeId The strategy type ID.
     * @param _dao The DAO address.
     * @param _auxData Additional deployment parameters.
     * @return exists True if the strategy exists, false otherwise.
     * @return strategy The address of the existing strategy (zero if doesn't exist).
     */
    function instanceExists(
        bytes32 _strategyTypeId,
        IDAO _dao,
        bytes calldata _auxData
    ) external view returns (bool exists, address strategy) {
        bytes32 deploymentId = _computeParamsHash(_strategyTypeId, _dao, _auxData);
        strategy = deployedInstances[deploymentId];
        exists = strategy != address(0);
    }

    /**
     * @notice Internal function to deploy a strategy with pre-computed hash.
     * @param _strategyTypeId The strategy type to deploy.
     * @param _dao The DAO address for initialization.
     * @param _auxData Additional deployment parameters.
     * @param _deploymentId Pre-computed deployment identifier.
     * @return strategy The address of the deployed strategy.
     */
    function _deployStrategy(
        bytes32 _strategyTypeId,
        IDAO _dao,
        bytes calldata _auxData,
        bytes32 _deploymentId
    ) internal returns (address strategy) {
        RegisteredType storage strategyType = registeredTypes[_strategyTypeId];

        if (strategyType.implementation == address(0)) {
            revert TypeNotFound(_strategyTypeId);
        }

        // Initialize the strategy
        bytes memory initCalldata = abi.encodeWithSignature(
            "initialize(bytes32,address,bytes)",
            _strategyTypeId,
            address(_dao),
            _auxData
        );

        // Deploy and initialize using base class utility
        strategy = _deployAndInitialize(strategyType.implementation, initCalldata);

        // Register the deployed strategy
        deployedInstances[_deploymentId] = strategy;
        instanceToType[strategy] = _strategyTypeId;

        emit InstanceDeployed(_strategyTypeId, strategy, _deploymentId, msg.sender);
        emit StrategyDeployed(_strategyTypeId, strategy);

        return strategy;
    }
}
