// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { IDAO } from "@aragon/commons/dao/IDAO.sol";

/// @title IAllocatorStrategyFactory
/// @notice Interface for the AllocatorStrategyFactory contract.
interface IAllocatorStrategyFactory {
    /// @notice Emitted when a new strategy type is registered.
    event StrategyTypeRegistered(
        bytes32 indexed strategyId, address indexed implementation, string metadata, address indexed registrar
    );

    /// @notice Emitted when a strategy instance is deployed.
    event StrategyDeployed(
        bytes32 indexed strategyId, address indexed strategy, bytes32 indexed paramsHash, address deployer
    );

    /// @notice Thrown when trying to register a strategy type that already exists.
    error StrategyTypeAlreadyExists(bytes32 strategyId);

    /// @notice Thrown when trying to use a strategy type that doesn't exist.
    error StrategyTypeNotFound(bytes32 strategyId);

    /// @notice Thrown when trying to deploy a strategy that already exists.
    error StrategyAlreadyDeployed(bytes32 paramsHash, address existingStrategy);

    /// @notice Thrown when strategy deployment fails.
    error StrategyDeploymentFailed(bytes32 strategyId);

    /**
     * @notice Deploys a new instance of a registered strategy type.
     * @param _strategyId The strategy type to deploy.
     * @param _dao The DAO address.
     * @param _plugin The plugin address.
     * @param _params Deployment parameters for the strategy.
     * @return strategy The address of the deployed strategy.
     */
    function deployStrategy(
        bytes32 _strategyId,
        IDAO _dao,
        address _plugin,
        bytes calldata _params
    )
        external
        returns (address strategy);

    /**
     * @notice Gets an existing strategy instance or deploys a new one if it doesn't exist.
     * @param _strategyId The strategy type to get or deploy.
     * @param _dao The DAO address.
     * @param _plugin The plugin address.
     * @param _params Deployment parameters for the strategy.
     * @return strategy The address of the existing or newly deployed strategy.
     */
    function getOrDeployStrategy(
        bytes32 _strategyId,
        IDAO _dao,
        address _plugin,
        bytes calldata _params
    )
        external
        returns (address strategy);

    /**
     * @notice Gets the fee configuration for a deployed strategy instance.
     * @param _strategyInstance The address of the strategy instance.
     * @return recipient The address where fees are sent.
     * @return basisPoints The fee percentage in basis points.
     */
    function getStrategyFeeByInstance(address _strategyInstance)
        external
        view
        returns (address recipient, uint32 basisPoints);
}
