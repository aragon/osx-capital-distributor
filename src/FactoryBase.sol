// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";

/// @title FactoryBase
/// @author AragonX - 2025
/// @notice Abstract base contract for factory/registry hybrid contracts
/// @dev Provides common functionality for registering types and deploying instances
abstract contract FactoryBase {
    using Clones for address;

    /// @notice Struct containing implementation contract and metadata
    /// @param implementation The address of the implementation contract
    /// @param metadata Human-readable metadata describing the type
    struct RegisteredType {
        address implementation;
        string metadata;
    }

    /// @notice Emitted when a new type is registered
    /// @param typeId The unique identifier for the type
    /// @param implementation The address of the implementation contract
    /// @param metadata The metadata associated with the type
    /// @param registrar The address that registered the type
    event TypeRegistered(
        bytes32 indexed typeId,
        address indexed implementation,
        string metadata,
        address indexed registrar
    );

    /// @notice Emitted when an instance is deployed
    /// @param typeId The unique identifier for the type
    /// @param instance The address of the deployed instance
    /// @param deploymentId The unique deployment identifier
    /// @param deployer The address that deployed the instance
    event InstanceDeployed(
        bytes32 indexed typeId,
        address indexed instance,
        bytes32 indexed deploymentId,
        address deployer
    );

    /// @notice Thrown when attempting to register a type ID that already exists
    /// @param typeId The type ID that is already registered
    error AlreadyRegistered(bytes32 typeId);

    /// @notice Thrown when an invalid implementation address is provided
    /// @param implementation The invalid implementation address
    error InvalidImplementation(address implementation);

    /// @notice Thrown when an empty type ID is provided
    error EmptyTypeId();

    /// @notice Thrown when instance deployment fails
    /// @param typeId The type ID that failed to deploy
    error DeploymentFailed(bytes32 typeId);

    /// @notice Thrown when attempting to access a type that doesn't exist
    /// @param typeId The type ID that was not found
    error TypeNotFound(bytes32 typeId);

    /// @notice Validates that a type ID is not empty
    /// @param _typeId The type ID to validate
    modifier validTypeId(bytes32 _typeId) {
        if (_typeId == bytes32(0)) {
            revert EmptyTypeId();
        }
        _;
    }

    /// @notice Validates that an implementation address is not zero
    /// @param _implementation The implementation address to validate
    modifier validImplementation(address _implementation) {
        if (_implementation == address(0)) {
            revert InvalidImplementation(_implementation);
        }
        _;
    }

    /// @notice Internal function to validate registration parameters
    /// @param _typeId The type ID to register
    /// @param _implementation The implementation address
    /// @param _existingImplementation The existing implementation address (zero if not registered)
    function _validateRegistration(
        bytes32 _typeId,
        address _implementation,
        address _existingImplementation
    ) internal pure {
        if (_typeId == bytes32(0)) {
            revert EmptyTypeId();
        }
        if (_implementation == address(0)) {
            revert InvalidImplementation(_implementation);
        }
        if (_existingImplementation != address(0)) {
            revert AlreadyRegistered(_typeId);
        }
    }

    /// @notice Internal function to deploy a clone and initialize it
    /// @param _implementation The implementation address to clone
    /// @param _initCalldata The initialization calldata
    /// @return instance The address of the deployed instance
    function _deployAndInitialize(
        address _implementation,
        bytes memory _initCalldata
    ) internal returns (address instance) {
        instance = _implementation.clone();

        (bool success, ) = instance.call(_initCalldata);
        if (!success) {
            // Note: We can't determine the specific typeId here, so we use bytes32(0)
            // Inheriting contracts should override this behavior if they need specific error handling
            revert DeploymentFailed(bytes32(0));
        }
    }

    /// @notice Computes a basic hash for deployment parameters
    /// @param _typeId The type identifier
    /// @param _dao The DAO address
    /// @return paramsHash The computed hash
    function _computeBasicParamsHash(bytes32 _typeId, IDAO _dao) internal pure returns (bytes32 paramsHash) {
        return keccak256(abi.encodePacked(_typeId, address(_dao)));
    }

    /// @notice Computes a hash for deployment parameters with additional data
    /// @param _typeId The type identifier
    /// @param _dao The DAO address
    /// @param _auxData Additional data to include in the hash
    /// @return paramsHash The computed hash
    function _computeParamsHash(
        bytes32 _typeId,
        IDAO _dao,
        bytes memory _auxData
    ) internal pure returns (bytes32 paramsHash) {
        return keccak256(abi.encodePacked(_typeId, address(_dao), _auxData));
    }

    /// @notice Gets the registered type information
    /// @param _typeId The type identifier
    /// @return registeredType The registered type data
    /// @dev Must be implemented by inheriting contracts
    function getRegisteredType(bytes32 _typeId) external view virtual returns (RegisteredType memory registeredType);

    /// @notice Checks if a type is registered
    /// @param _typeId The type identifier to check
    /// @return isRegistered True if the type is registered, false otherwise
    /// @dev Must be implemented by inheriting contracts
    function isTypeRegistered(bytes32 _typeId) external view virtual returns (bool isRegistered);
}
