// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {IPayoutActionEncoder} from "./interfaces/IPayoutActionEncoder.sol";
import {IActionEncoderFactory} from "./interfaces/IActionEncoderFactory.sol";
import {FactoryBase} from "./FactoryBase.sol";

/// @title ActionEncoderFactory
/// @author AragonX - 2025
/// @notice A factory/registry hybrid for managing and deploying action encoders.
/// @dev This contract allows registering and deploying action encoders instances on demand.
contract ActionEncoderFactory is FactoryBase, IActionEncoderFactory {
    using Clones for address;

    /// @notice Maps encoder IDs to their registered action encoder data
    mapping(bytes32 encoderId => RegisteredType) public registeredActionEncoders;

    /// @notice Maps deployment IDs to deployed encoder addresses
    mapping(bytes32 deployedEncoderId => IPayoutActionEncoder encoder) public deployedEncoders;

    /// @notice Registers a new action encoder implementation
    /// @param _encoderId The unique identifier for the action encoder
    /// @param _implementation The address of the implementation contract
    /// @param _metadata Human-readable metadata describing the action encoder
    /// @dev The implementation address must not be zero and the encoder ID must not be empty
    function registerActionEncoder(bytes32 _encoderId, address _implementation, string calldata _metadata) external {
        _validateRegistration(_encoderId, _implementation, registeredActionEncoders[_encoderId].implementation);

        registeredActionEncoders[_encoderId] = RegisteredType(_implementation, _metadata);

        emit TypeRegistered(_encoderId, _implementation, _metadata, msg.sender);
        emit ActionEncoderRegistered(_encoderId, _implementation, _metadata);
    }

    /// @notice Internal function to deploy an action encoder instance
    /// @param _encoderId The unique identifier for the action encoder
    /// @param _dao The DAO address for which the encoder is being deployed
    /// @param _params Initialization parameters for the action encoder
    /// @param _deploymentId The unique deployment identifier
    /// @return actionEncoder The address of the deployed action encoder instance
    /// @dev Creates a clone of the registered implementation and initializes it
    function _deployActionEncoder(
        bytes32 _encoderId,
        IDAO _dao,
        bytes calldata _params,
        bytes32 _deploymentId
    ) internal returns (IPayoutActionEncoder actionEncoder) {
        RegisteredType storage encoder = registeredActionEncoders[_encoderId];
        address implementation = encoder.implementation;
        if (implementation == address(0)) {
            revert TypeNotFound(_encoderId);
        }

        bytes memory initCalldata = abi.encodeWithSignature("initialize(address,bytes)", address(_dao), _params);

        try this._deployAndInitializeActionEncoder(implementation, initCalldata) returns (address deployedAddress) {
            actionEncoder = IPayoutActionEncoder(deployedAddress);
        } catch {
            revert ActionEncoderDeploymentFailed(_encoderId);
        }

        deployedEncoders[_deploymentId] = actionEncoder;

        emit InstanceDeployed(_encoderId, address(actionEncoder), _deploymentId, msg.sender);
        emit ActionEncoderDeployed(_encoderId, actionEncoder);
    }

    /// @notice Gets an existing action encoder or deploys a new one if it doesn't exist
    /// @param _encoderId The unique identifier for the action encoder
    /// @param _dao The DAO address for which the encoder is being deployed
    /// @param _params Initialization parameters for the action encoder
    /// @return actionEncoder The address of the action encoder instance
    /// @dev If an encoder with the same parameters already exists, returns the existing one
    function getOrDeployActionEncoder(
        bytes32 _encoderId,
        IDAO _dao,
        bytes calldata _params
    ) public returns (IPayoutActionEncoder actionEncoder) {
        bytes32 deploymentId = _computeParamsHash(_encoderId, _dao);

        if (address(deployedEncoders[deploymentId]) != address(0)) {
            return deployedEncoders[deploymentId];
        }

        actionEncoder = _deployActionEncoder(_encoderId, _dao, _params, deploymentId);
    }

    /// @notice Checks if an action encoder deployment exists for given parameters
    /// @param _encoderId The unique identifier for the action encoder
    /// @param _dao The DAO address to check for
    /// @return exists True if a deployment exists, false otherwise
    /// @return deployedEncoder The address of the deployed encoder if it exists, zero address otherwise
    function encoderDeploymentExists(
        bytes32 _encoderId,
        IDAO _dao
    ) external view returns (bool exists, IPayoutActionEncoder deployedEncoder) {
        bytes32 paramsHash = _computeParamsHash(_encoderId, _dao);
        deployedEncoder = deployedEncoders[paramsHash];
        exists = address(deployedEncoder) != address(0);
    }

    /// @notice Retrieves the registered action encoder data for a given encoder ID
    /// @param _encoderId The unique identifier for the action encoder
    /// @return actionEncoder The ActionEncoder struct containing implementation and metadata
    function getEncoder(bytes32 _encoderId) external view returns (RegisteredType memory actionEncoder) {
        return registeredActionEncoders[_encoderId];
    }

    /// @notice Computes a unique hash for deployment parameters
    /// @param _encoderId The encoder id
    /// @param _dao The address of the dao
    /// @return paramsHash The computed hash used as deployment identifier
    /// @dev Uses keccak256 to create a deterministic hash from encoder ID and DAO address
    function _computeParamsHash(bytes32 _encoderId, IDAO _dao) internal pure returns (bytes32 paramsHash) {
        return _computeBasicParamsHash(_encoderId, _dao);
    }

    /// @notice External wrapper for deployment and initialization (needed for try/catch)
    /// @param _implementation The implementation to deploy
    /// @param _initCalldata The initialization calldata
    /// @return deployedAddress The address of the deployed instance
    function _deployAndInitializeActionEncoder(
        address _implementation,
        bytes memory _initCalldata
    ) external returns (address deployedAddress) {
        require(msg.sender == address(this), "Only self-call allowed");
        return _deployAndInitialize(_implementation, _initCalldata);
    }

    /// @notice Gets the registered type information (required by FactoryBase)
    /// @param _typeId The type identifier
    /// @return registeredType The registered type data
    function getRegisteredType(bytes32 _typeId) external view override returns (RegisteredType memory registeredType) {
        return registeredActionEncoders[_typeId];
    }

    /// @notice Checks if a type is registered (required by FactoryBase)
    /// @param _typeId The type identifier to check
    /// @return isRegistered True if the type is registered, false otherwise
    function isTypeRegistered(bytes32 _typeId) external view override returns (bool isRegistered) {
        return registeredActionEncoders[_typeId].implementation != address(0);
    }
}
