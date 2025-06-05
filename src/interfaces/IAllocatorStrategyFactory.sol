// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {IDAO} from "@aragon/commons/dao/IDAO.sol";

/// @title IAllocatorStrategyFactory
/// @notice Interface for the AllocatorStrategyFactory contract.
interface IAllocatorStrategyFactory {
    /// @notice Represents a registered strategy type.
    struct StrategyType {
        address implementation;
        string metadata;
    }

    /// @notice Represents deployment parameters for a strategy instance.
    struct DeploymentParams {
        uint256 epochDuration;
        bool claimOpen;
        bytes auxData;
    }

    /// @notice Emitted when a new strategy type is registered.
    event StrategyTypeRegistered(
        bytes32 indexed strategyId,
        address indexed implementation,
        string metadata,
        address indexed registrar
    );

    /// @notice Emitted when a strategy instance is deployed.
    event StrategyDeployed(
        bytes32 indexed strategyTypeId,
        address indexed strategy,
        bytes32 indexed paramsHash,
        address deployer
    );

    /// @notice Thrown when trying to register a strategy type that already exists.
    error StrategyTypeAlreadyExists(bytes32 strategyTypeId);

    /// @notice Thrown when trying to use a strategy type that doesn't exist.
    error StrategyTypeNotFound(bytes32 strategyTypeId);

    /// @notice Thrown when trying to deploy a strategy that already exists.
    error StrategyAlreadyDeployed(bytes32 paramsHash, address existingStrategy);

    /// @notice Thrown when strategy deployment fails.
    error StrategyDeploymentFailed(bytes32 strategyTypeId);

    /// @notice Thrown when provided implementation address is invalid.
    error InvalidImplementation(address implementation);

    /// @notice Thrown when provided strategy name is empty.
    error EmptyStrategyName();

    /**
     * @notice Registers a new strategy type in the factory.
     * @param _strategyId Unique identifier for the strategy type.
     * @param _implementation Address of the strategy implementation contract.
     * @param _metadata The hash of the metadata for the strategy type.
     */
    function registerStrategyType(bytes32 _strategyId, address _implementation, string calldata _metadata) external;

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
    ) external returns (address strategy);

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
    ) external returns (address strategy);

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
    ) external view returns (bool exists, address strategy);

    /**
     * @notice Gets the strategy type information.
     * @param _strategyTypeId The strategy type ID.
     * @return strategyType The strategy type configuration.
     */
    function getStrategyType(bytes32 _strategyTypeId) external view returns (StrategyType memory strategyType);

    /**
     * @notice Maps deployment parameters hash to deployed strategy addresses.
     * @param paramsHash The parameters hash.
     * @return strategy The deployed strategy address.
     */
    function deployedStrategies(bytes32 paramsHash) external view returns (address strategy);

    /**
     * @notice Maps strategy addresses to their type IDs.
     * @param strategy The strategy address.
     * @return strategyTypeId The strategy type ID.
     */
    function strategyToType(address strategy) external view returns (bytes32 strategyTypeId);
}
