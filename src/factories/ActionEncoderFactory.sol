// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { IPayoutActionEncoder } from "../interfaces/IPayoutActionEncoder.sol";
import { IActionEncoderFactory } from "../interfaces/IActionEncoderFactory.sol";
import { FactoryBase } from "./FactoryBase.sol";

/// @title ActionEncoderFactory
/// @author AragonX - 2025
/// @notice A factory/registry hybrid for managing and deploying action encoders.
/// @dev This contract allows registering and deploying action encoders instances on demand.
contract ActionEncoderFactory is FactoryBase, IActionEncoderFactory {
    using Clones for address;

    /// @notice Maps deployment IDs to deployed encoder addresses
    mapping(bytes32 deploymentId => IPayoutActionEncoder encoder) public deployedInstances;

    /// @notice Maps encoder addresses to their type IDs
    mapping(address instance => bytes32 typeId) public instanceToType;

    /// @notice Emitted when a new action encoder type is registered
    /// @param encoderId The unique identifier for the action encoder type
    /// @param implementation The address of the implementation contract
    /// @param metadata The metadata associated with the action encoder type
    event ActionEncoderTypeRegistered(bytes32 indexed encoderId, address indexed implementation, string metadata);

    /// @param _encoderId The unique identifier for the action encoder
    /// @param _encoderImplementation The address of the implementation contract
    /// @param _metadata Human-readable metadata describing the action encoder
    function registerActionEncoder(
        bytes32 _encoderId,
        address _encoderImplementation,
        string calldata _metadata
    )
        external
    {
        // Validate basic requirements first
        if (_encoderId == bytes32(0)) {
            revert EmptyTypeId();
        }
        if (_encoderImplementation == address(0)) {
            revert InvalidImplementation(_encoderImplementation, "Implementation address cannot be zero");
        }
        if (registeredTypes[_encoderId].implementation != address(0)) {
            revert AlreadyRegistered(_encoderId);
        }
        if (_encoderImplementation.code.length == 0) {
            revert InvalidImplementation(_encoderImplementation, "Implementation must be a deployed contract");
        }

        // Validate that the implementation supports the IPayoutActionEncoder interface
        try IERC165(_encoderImplementation).supportsInterface(type(IPayoutActionEncoder).interfaceId) returns (
            bool supported
        ) {
            if (!supported) {
                revert InvalidImplementation(
                    _encoderImplementation, "Implementation must support IPayoutActionEncoder interface"
                );
            }
        } catch {
            revert InvalidImplementation(
                _encoderImplementation, "Implementation must support IPayoutActionEncoder interface"
            );
        }

        // Register the type
        registeredTypes[_encoderId] = RegisteredType({ implementation: _encoderImplementation, metadata: _metadata });
        emit TypeRegistered(_encoderId, _encoderImplementation, _metadata, msg.sender);
        emit ActionEncoderTypeRegistered(_encoderId, _encoderImplementation, _metadata);
    }

    /// @notice Deploys a new instance of a registered action encoder type
    /// @param _encoderId The unique identifier for the action encoder
    /// @param _dao The DAO address for which the encoder is being deployed
    /// @param _initializationParams Initialization parameters for the action encoder
    /// @return encoder The address of the deployed action encoder instance
    function deployActionEncoder(
        bytes32 _encoderId,
        IDAO _dao,
        bytes calldata _initializationParams
    )
        public
        returns (IPayoutActionEncoder encoder)
    {
        bytes32 deploymentId = _computeDeploymentId(_encoderId, _dao, _initializationParams);

        // Check if encoder with these parameters already exists
        IPayoutActionEncoder existingEncoder = deployedInstances[deploymentId];
        if (address(existingEncoder) != address(0)) {
            revert InstanceAlreadyDeployed(deploymentId, address(existingEncoder));
        }

        return _deployActionEncoder(_encoderId, _dao, _initializationParams, deploymentId);
    }

    /// @notice Gets an existing action encoder or deploys a new one if it doesn't exist
    /// @param _encoderId The unique identifier for the action encoder
    /// @param _dao The DAO address for which the encoder is being deployed
    /// @param _initializationParams Initialization parameters for the action encoder
    /// @return encoder The address of the action encoder instance
    function getOrDeployActionEncoder(
        bytes32 _encoderId,
        IDAO _dao,
        bytes calldata _initializationParams
    )
        external
        returns (IPayoutActionEncoder encoder)
    {
        bytes32 deploymentId = _computeDeploymentId(_encoderId, _dao, _initializationParams);

        encoder = deployedInstances[deploymentId];
        if (address(encoder) != address(0)) {
            return encoder;
        }

        return _deployActionEncoder(_encoderId, _dao, _initializationParams, deploymentId);
    }

    /// @notice Checks if an action encoder deployment exists for given parameters
    /// @param _encoderId The unique identifier for the action encoder
    /// @param _dao The DAO address to check for
    /// @param _initializationParams Additional deployment parameters
    /// @return exists True if a deployment exists, false otherwise
    /// @return encoder The address of the deployed encoder if it exists, zero address otherwise
    function hasDeployment(
        bytes32 _encoderId,
        IDAO _dao,
        bytes calldata _initializationParams
    )
        external
        view
        returns (bool exists, IPayoutActionEncoder encoder)
    {
        bytes32 deploymentId = _computeDeploymentId(_encoderId, _dao, _initializationParams);
        encoder = deployedInstances[deploymentId];
        exists = address(encoder) != address(0);
    }

    /// @notice Internal function to deploy an action encoder instance
    /// @param _encoderId The unique identifier for the action encoder
    /// @param _dao The DAO address for which the encoder is being deployed
    /// @param _initializationParams Initialization parameters for the action encoder
    /// @param _deploymentId The unique deployment identifier
    /// @return encoder The address of the deployed action encoder instance
    function _deployActionEncoder(
        bytes32 _encoderId,
        IDAO _dao,
        bytes calldata _initializationParams,
        bytes32 _deploymentId
    )
        internal
        returns (IPayoutActionEncoder encoder)
    {
        RegisteredType storage encoderType = registeredTypes[_encoderId];

        if (encoderType.implementation == address(0)) {
            revert TypeNotFound(_encoderId);
        }

        bytes memory initCalldata = abi.encodeWithSignature(
            "initialize(bytes32,address,address,bytes)", _encoderId, address(_dao), msg.sender, _initializationParams
        );

        address instance = _deployAndInitialize(_encoderId, encoderType.implementation, initCalldata);
        encoder = IPayoutActionEncoder(instance);

        deployedInstances[_deploymentId] = encoder;
        instanceToType[address(encoder)] = _encoderId;

        emit InstanceDeployed(_encoderId, address(encoder), _deploymentId, msg.sender);
        emit ActionEncoderDeployed(_encoderId, encoder);

        return encoder;
    }
}
