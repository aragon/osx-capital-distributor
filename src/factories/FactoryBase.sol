// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title FactoryBase
/// @author AragonX - 2025
/// @notice Abstract base contract for factory/registry hybrid contracts
/// @dev Provides common functionality for registering types and deploying instances
abstract contract FactoryBase is ReentrancyGuard {
    using Clones for address;

    /// @notice Struct containing implementation contract and metadata
    /// @param implementation The address of the implementation contract
    /// @param metadata Human-readable metadata describing the type
    struct RegisteredType {
        address implementation;
        string metadata;
    }

    /// @notice Maps type IDs to their registered type data
    mapping(bytes32 typeId => RegisteredType) public registeredTypes;

    /// @notice Emitted when a new type is registered
    /// @param typeId The unique identifier for the type
    /// @param implementation The address of the implementation contract
    /// @param metadata The metadata associated with the type
    /// @param registrar The address that registered the type
    event TypeRegistered(
        bytes32 indexed typeId, address indexed implementation, string metadata, address indexed registrar
    );

    /// @notice Emitted when an instance is deployed
    /// @param typeId The unique identifier for the type
    /// @param instance The address of the deployed instance
    /// @param deploymentId The unique deployment identifier
    /// @param deployer The address that deployed the instance
    event InstanceDeployed(
        bytes32 indexed typeId, address indexed instance, bytes32 indexed deploymentId, address deployer
    );

    /// @notice Thrown when attempting to register a type ID that already exists
    /// @param typeId The type ID that is already registered
    error AlreadyRegistered(bytes32 typeId);

    /// @notice Thrown when an invalid implementation address is provided
    /// @param implementation The invalid implementation address
    /// @param reason The reason why the implementation is invalid
    error InvalidImplementation(address implementation, string reason);

    /// @notice Thrown when an empty type ID is provided
    error EmptyTypeId();

    /// @notice Thrown when instance deployment fails
    /// @param typeId The type ID that failed to deploy
    /// @param implementation The implementation address that failed
    /// @param reason Additional context about the failure
    error DeploymentFailed(bytes32 typeId, address implementation, string reason);

    /// @notice Thrown when attempting to access a type that doesn't exist
    /// @param typeId The type ID that was not found
    error TypeNotFound(bytes32 typeId);

    /// @notice Thrown when an instance with the same parameters already exists
    /// @param deploymentId The deployment ID that already exists
    /// @param existingInstance The address of the existing instance
    error InstanceAlreadyDeployed(bytes32 deploymentId, address existingInstance);

    /// @notice Internal function to register a type
    /// @param _typeId The type ID to register
    /// @param _implementation The implementation address
    /// @param _metadata The metadata for the type
    /// @dev This function handles the common registration logic
    function _registerType(bytes32 _typeId, address _implementation, string calldata _metadata) internal {
        _validateRegistration(_typeId, _implementation, registeredTypes[_typeId].implementation);

        // Validate that the implementation is a contract
        if (_implementation.code.length == 0) {
            revert InvalidImplementation(_implementation, "Implementation must be a deployed contract");
        }

        registeredTypes[_typeId] = RegisteredType({ implementation: _implementation, metadata: _metadata });

        emit TypeRegistered(_typeId, _implementation, _metadata, msg.sender);
    }

    /// @notice Internal function to validate registration parameters
    /// @param _typeId The type ID to register
    /// @param _implementation The implementation address
    /// @param _existingImplementation The existing implementation address (zero if not registered)
    function _validateRegistration(
        bytes32 _typeId,
        address _implementation,
        address _existingImplementation
    )
        internal
        pure
    {
        if (_typeId == bytes32(0)) {
            revert EmptyTypeId();
        }
        if (_implementation == address(0)) {
            revert InvalidImplementation(_implementation, "Implementation address cannot be zero");
        }
        if (_existingImplementation != address(0)) {
            revert AlreadyRegistered(_typeId);
        }
    }

    /// @notice Internal function to deploy a clone and initialize it
    /// @param _typeId The type ID being deployed
    /// @param _implementation The implementation address to clone
    /// @param _initCalldata The initialization calldata
    /// @return instance The address of the deployed instance
    function _deployAndInitialize(
        bytes32 _typeId,
        address _implementation,
        bytes memory _initCalldata
    )
        internal
        nonReentrant
        returns (address instance)
    {
        instance = _implementation.clone();

        (bool success, bytes memory returnData) = instance.call(_initCalldata);
        if (!success) {
            string memory reason = returnData.length > 0 ? string(returnData) : "Initialization failed";
            revert DeploymentFailed(_typeId, _implementation, reason);
        }
    }

    /// @notice Computes a hash for deployment parameters with additional data
    /// @param _typeId The type identifier
    /// @param _dao The DAO address
    /// @param _deploymentParams Additional data to include in the hash
    /// @return deploymentId The computed hash
    function _computeDeploymentId(
        bytes32 _typeId,
        IDAO _dao,
        bytes memory _deploymentParams
    )
        internal
        pure
        returns (bytes32 deploymentId)
    {
        return keccak256(abi.encode(_typeId, address(_dao), _deploymentParams));
    }

    /// @notice Checks if a type is registered
    /// @param _typeId The type identifier to check
    /// @return isRegistered True if the type is registered, false otherwise
    function isTypeRegistered(bytes32 _typeId) external view returns (bool isRegistered) {
        return registeredTypes[_typeId].implementation != address(0);
    }
}
