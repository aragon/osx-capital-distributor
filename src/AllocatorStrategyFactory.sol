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

    /// @notice Maps strategy type IDs to their configuration.
    mapping(bytes32 strategyTypeId => RegisteredType) public strategyTypes;

    /// @notice Maps deployment parameters hash to deployed strategy addresses.
    mapping(bytes32 paramsHash => address strategy) public deployedStrategies;

    /// @notice Maps strategy addresses to their type IDs.
    mapping(address strategy => bytes32 strategyTypeId) public strategyToType;

    /**
     * @notice Registers a new strategy type in the factory.
     * @param _strategyId Unique identifier for the strategy type.
     * @param _implementation Address of the strategy implementation contract.
     * @param _metadata Human-readable name for the strategy type.
     */
    function registerStrategyType(bytes32 _strategyId, address _implementation, string calldata _metadata) external {
        _validateRegistration(_strategyId, _implementation, strategyTypes[_strategyId].implementation);

        strategyTypes[_strategyId] = RegisteredType({implementation: _implementation, metadata: _metadata});

        emit TypeRegistered(_strategyId, _implementation, _metadata, msg.sender);
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
        bytes32 paramsHash = _computeParamsHash(_strategyTypeId, _dao, _params);
        return _deployStrategy(_strategyTypeId, _dao, paramsHash);
    }

    /**
     * @notice Internal function to deploy a strategy with pre-computed hash for gas optimization.
     * @param _strategyTypeId The strategy type to deploy.
     * @param _dao The DAO address for initialization.
     * @param _paramsHash Pre-computed hash of deployment parameters.
     * @return strategy The address of the deployed strategy.
     */
    function _deployStrategy(
        bytes32 _strategyTypeId,
        IDAO _dao,
        bytes32 _paramsHash
    ) internal returns (address strategy) {
        RegisteredType storage strategyType = strategyTypes[_strategyTypeId];

        if (strategyType.implementation == address(0)) {
            revert TypeNotFound(_strategyTypeId);
        }

        // Check if strategy with these parameters already exists
        address existingStrategy = deployedStrategies[_paramsHash];
        if (existingStrategy != address(0)) {
            revert StrategyAlreadyDeployed(_paramsHash, existingStrategy);
        }

        // Initialize the strategy
        bytes memory initCalldata = abi.encodeWithSignature("initialize(address)", _dao);

        // Deploy and initialize using base class utility
        strategy = _deployAndInitialize(strategyType.implementation, initCalldata);

        // Register the deployed strategy
        deployedStrategies[_paramsHash] = strategy;
        strategyToType[strategy] = _strategyTypeId;

        emit InstanceDeployed(_strategyTypeId, strategy, _paramsHash, msg.sender);

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

        return _deployStrategy(_strategyTypeId, _dao, paramsHash);
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
    function getStrategyType(
        bytes32 _strategyTypeId
    ) external view returns (FactoryBase.RegisteredType memory strategyType) {
        return strategyTypes[_strategyTypeId];
    }

    /**
     * @notice Gets the registered type information (required by FactoryBase).
     * @param _typeId The type identifier.
     * @return registeredType The registered type data.
     */
    function getRegisteredType(bytes32 _typeId) external view override returns (RegisteredType memory registeredType) {
        return strategyTypes[_typeId];
    }

    /**
     * @notice Checks if a type is registered (required by FactoryBase).
     * @param _typeId The type identifier to check.
     * @return isRegistered True if the type is registered, false otherwise.
     */
    function isTypeRegistered(bytes32 _typeId) external view override returns (bool isRegistered) {
        return strategyTypes[_typeId].implementation != address(0);
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
        return _computeParamsHash(_strategyTypeId, _dao, _params.auxData);
    }
}
