// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { IAllocatorStrategy } from "../interfaces/IAllocatorStrategy.sol";
import { IAllocatorStrategyFactory } from "../interfaces/IAllocatorStrategyFactory.sol";
import { FactoryBase } from "./FactoryBase.sol";

/// @title AllocatorStrategyFactory
/// @author AragonX - 2025
/// @notice A factory/registry hybrid for managing and deploying allocator strategies.
/// @dev This contract allows registering strategy types and deploying instances on demand.
contract AllocatorStrategyFactory is FactoryBase, IAllocatorStrategyFactory {
    using Clones for address;

    /// @notice Maximum fee in basis points (10% = 1000 basis points).
    uint256 public constant MAX_FEE_BASIS_POINTS = 1000;

    /// @notice Fee configuration for a strategy type
    /// @param recipient Where fees are sent
    /// @param basisPoints Fee percentage in basis points (e.g., 250 = 2.5%, max 1000 = 10%)
    struct FeeConfig {
        address recipient;
        uint256 basisPoints;
    }

    /// @notice Maps deployment parameters hash to deployed strategy addresses.
    mapping(bytes32 deploymentId => address strategy) public deployedInstances;

    /// @notice Maps strategy addresses to their type IDs.
    mapping(address instance => bytes32 typeId) public instanceToType;

    /// @notice Maps strategy type IDs to their fee configurations.
    mapping(bytes32 strategyId => FeeConfig) public strategyFees;

    /// @notice Emitted when a new strategy type is registered
    /// @param strategyId The unique identifier for the strategy type
    /// @param implementation The address of the implementation contract
    /// @param metadata The metadata associated with the strategy type
    event StrategyTypeRegistered(bytes32 indexed strategyId, address indexed implementation, string metadata);

    /// @notice Emitted when a strategy instance is deployed
    /// @param strategyId The unique identifier for the strategy type
    /// @param strategy The address of the deployed strategy
    event StrategyDeployed(bytes32 indexed strategyId, address indexed strategy);

    /// @notice Emitted when a strategy type is registered with fee configuration
    /// @param strategyId The unique identifier for the strategy type
    /// @param feeRecipient The address where fees will be sent
    /// @param feeBasisPoints The fee percentage in basis points
    event StrategyFeeConfigured(bytes32 indexed strategyId, address indexed feeRecipient, uint256 feeBasisPoints);

    /// @notice Error thrown when fee recipient is zero address
    error InvalidFeeRecipient();

    /// @notice Error thrown when fee basis points exceed maximum allowed
    /// @param provided The provided fee basis points
    /// @param maximum The maximum allowed fee basis points
    error ExcessiveFee(uint256 provided, uint256 maximum);

    /// @notice Error thrown when querying fee for a strategy not deployed by this factory
    /// @param strategyInstance The strategy instance address that was not found
    error StrategyNotFound(address strategyInstance);

    /**
     * @notice Registers a new strategy type in the factory.
     * @param _strategyId Unique identifier for the strategy type.
     * @param _strategyImplementation Address of the strategy implementation contract.
     * @param _metadata Human-readable name for the strategy type.
     * @param _feeRecipient Address where fees for this strategy type will be sent.
     * @param _feeBasisPoints Fee percentage in basis points (max 1000 = 10%).
     * @dev Validates that the implementation supports the IAllocatorStrategy interface.
     */
    function registerStrategyType(
        bytes32 _strategyId,
        address _strategyImplementation,
        string calldata _metadata,
        address _feeRecipient,
        uint256 _feeBasisPoints
    )
        external
    {
        // Validate basic requirements first
        if (_strategyId == bytes32(0)) {
            revert EmptyTypeId();
        }
        if (_strategyImplementation == address(0)) {
            revert InvalidImplementation(_strategyImplementation, "Implementation address cannot be zero");
        }
        if (registeredTypes[_strategyId].implementation != address(0)) {
            revert AlreadyRegistered(_strategyId);
        }
        if (_strategyImplementation.code.length == 0) {
            revert InvalidImplementation(_strategyImplementation, "Implementation must be a deployed contract");
        }

        // Validate fee configuration
        if (_feeBasisPoints > 0 && _feeRecipient == address(0)) {
            revert InvalidFeeRecipient();
        }
        if (_feeBasisPoints > MAX_FEE_BASIS_POINTS) {
            // Max 10%
            revert ExcessiveFee(_feeBasisPoints, MAX_FEE_BASIS_POINTS);
        }

        // Validate that the implementation supports the IAllocatorStrategy interface
        try IERC165(_strategyImplementation).supportsInterface(type(IAllocatorStrategy).interfaceId) returns (
            bool supported
        ) {
            if (!supported) {
                revert InvalidImplementation(
                    _strategyImplementation, "Implementation must support IAllocatorStrategy interface"
                );
            }
        } catch {
            revert InvalidImplementation(
                _strategyImplementation, "Implementation must support IAllocatorStrategy interface"
            );
        }

        // Register the type
        registeredTypes[_strategyId] = RegisteredType({ implementation: _strategyImplementation, metadata: _metadata });

        // Store fee configuration
        strategyFees[_strategyId] = FeeConfig({ recipient: _feeRecipient, basisPoints: _feeBasisPoints });

        emit TypeRegistered(_strategyId, _strategyImplementation, _metadata, msg.sender);
        emit StrategyTypeRegistered(_strategyId, _strategyImplementation, _metadata);
        emit StrategyFeeConfigured(_strategyId, _feeRecipient, _feeBasisPoints);
    }

    /**
     * @notice Deploys a new instance of a registered strategy type.
     * @param _strategyId The strategy type to deploy.
     * @param _dao The DAO address for initialization.
     * @param _deploymentParams Additional deployment parameters.
     * @return strategy The address of the deployed strategy.
     */
    function deployStrategy(
        bytes32 _strategyId,
        IDAO _dao,
        bytes calldata _deploymentParams
    )
        public
        returns (address strategy)
    {
        bytes32 deploymentId = _computeDeploymentId(_strategyId, _dao, _deploymentParams);

        // Check if strategy with these parameters already exists
        address existingStrategy = deployedInstances[deploymentId];
        if (existingStrategy != address(0)) {
            revert InstanceAlreadyDeployed(deploymentId, existingStrategy);
        }

        return _deployStrategy(_strategyId, _dao, _deploymentParams, deploymentId);
    }

    /**
     * @notice Gets an existing strategy instance or deploys a new one if it doesn't exist.
     * @param _strategyId The strategy type to get or deploy.
     * @param _dao The DAO address for initialization.
     * @param _deploymentParams Additional deployment parameters.
     * @return strategy The address of the existing or newly deployed strategy.
     */
    function getOrDeployStrategy(
        bytes32 _strategyId,
        IDAO _dao,
        bytes calldata _deploymentParams
    )
        external
        returns (address strategy)
    {
        bytes32 deploymentId = _computeDeploymentId(_strategyId, _dao, _deploymentParams);

        strategy = deployedInstances[deploymentId];
        if (strategy != address(0)) {
            return strategy;
        }

        return _deployStrategy(_strategyId, _dao, _deploymentParams, deploymentId);
    }

    /**
     * @notice Checks if a strategy with given parameters already exists.
     * @param _strategyId The strategy type ID.
     * @param _dao The DAO address.
     * @param _deploymentParams Additional deployment parameters.
     * @return exists True if the strategy exists, false otherwise.
     * @return strategy The address of the existing strategy (zero if doesn't exist).
     */
    function hasDeployment(
        bytes32 _strategyId,
        IDAO _dao,
        bytes calldata _deploymentParams
    )
        external
        view
        returns (bool exists, address strategy)
    {
        bytes32 deploymentId = _computeDeploymentId(_strategyId, _dao, _deploymentParams);
        strategy = deployedInstances[deploymentId];
        // Avoid redundant comparison by using inline assembly for gas optimization
        assembly {
            exists := gt(strategy, 0)
        }
    }

    /**
     * @notice Gets the fee configuration for a deployed strategy instance.
     * @param _strategyInstance The address of the strategy instance.
     * @return recipient The address where fees are sent.
     * @return basisPoints The fee percentage in basis points.
     */
    function getStrategyFeeByInstance(address _strategyInstance)
        external
        view
        returns (address recipient, uint256 basisPoints)
    {
        bytes32 typeId = instanceToType[_strategyInstance];
        if (typeId == bytes32(0)) {
            revert StrategyNotFound(_strategyInstance);
        }
        FeeConfig memory feeConfig = strategyFees[typeId];
        return (feeConfig.recipient, feeConfig.basisPoints);
    }

    /**
     * @notice Internal function to deploy a strategy with pre-computed hash.
     * @param _strategyId The strategy type to deploy.
     * @param _dao The DAO address for initialization.
     * @param _deploymentParams Additional deployment parameters.
     * @param _deploymentId Pre-computed deployment identifier.
     * @return strategy The address of the deployed strategy.
     */
    function _deployStrategy(
        bytes32 _strategyId,
        IDAO _dao,
        bytes calldata _deploymentParams,
        bytes32 _deploymentId
    )
        internal
        returns (address strategy)
    {
        RegisteredType storage strategyType = registeredTypes[_strategyId];
        address implementation = strategyType.implementation; // Cache storage read

        if (implementation == address(0)) {
            revert TypeNotFound(_strategyId);
        }

        // Initialize the strategy
        bytes memory initCalldata = abi.encodeWithSignature(
            "initialize(bytes32,address,address,bytes)", _strategyId, address(_dao), msg.sender, _deploymentParams
        );

        // Deploy and initialize using base class utility
        strategy = _deployAndInitialize(_strategyId, implementation, initCalldata);

        // Register the deployed strategy
        deployedInstances[_deploymentId] = strategy;
        instanceToType[strategy] = _strategyId;

        emit InstanceDeployed(_strategyId, strategy, _deploymentId, msg.sender);
        emit StrategyDeployed(_strategyId, strategy);

        return strategy;
    }
}
