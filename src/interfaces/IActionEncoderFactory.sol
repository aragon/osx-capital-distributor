// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {IPayoutActionEncoder} from "./IPayoutActionEncoder.sol";
import {FactoryBase} from "../FactoryBase.sol";

/// @title IActionEncoderFactory
/// @notice Interface for the ActionEncoderFactory contract.
interface IActionEncoderFactory {
    /// @notice Emitted when a new action encoder is registered (legacy event)
    /// @param encoderId The unique identifier for the action encoder
    /// @param implementation The address of the implementation contract
    /// @param metadata The metadata associated with the action encoder
    event ActionEncoderRegistered(bytes32 encoderId, address implementation, string metadata);

    /// @notice Emitted when an action encoder is deployed (legacy event)
    /// @param encoderId The unique identifier for the action encoder
    /// @param actionEncoder The address of the deployed action encoder instance
    event ActionEncoderDeployed(bytes32 encoderId, IPayoutActionEncoder actionEncoder);

    /// @notice Thrown when action encoder deployment fails
    /// @param encoderId The encoder ID that failed to deploy
    error ActionEncoderDeploymentFailed(bytes32 encoderId);

    /**
     * @notice Registers a new action encoder implementation
     * @param _encoderId The unique identifier for the action encoder
     * @param _implementation The address of the implementation contract
     * @param _metadata Human-readable metadata describing the action encoder
     */
    function registerActionEncoder(bytes32 _encoderId, address _implementation, string calldata _metadata) external;

    /**
     * @notice Gets an existing action encoder or deploys a new one if it doesn't exist
     * @param _encoderId The unique identifier for the action encoder
     * @param _dao The DAO address for which the encoder is being deployed
     * @param _params Initialization parameters for the action encoder
     * @return actionEncoder The address of the action encoder instance
     */
    function getOrDeployActionEncoder(
        bytes32 _encoderId,
        IDAO _dao,
        bytes calldata _params
    ) external returns (IPayoutActionEncoder actionEncoder);

    /**
     * @notice Checks if an action encoder deployment exists for given parameters
     * @param _encoderId The unique identifier for the action encoder
     * @param _dao The DAO address to check for
     * @return exists True if a deployment exists, false otherwise
     * @return deployedEncoder The address of the deployed encoder if it exists, zero address otherwise
     */
    function encoderDeploymentExists(
        bytes32 _encoderId,
        IDAO _dao
    ) external view returns (bool exists, IPayoutActionEncoder deployedEncoder);

    /**
     * @notice Retrieves the registered action encoder data for a given encoder ID
     * @param _encoderId The unique identifier for the action encoder
     * @return actionEncoder The RegisteredType struct containing implementation and metadata
     */
    function getEncoder(bytes32 _encoderId) external view returns (FactoryBase.RegisteredType memory actionEncoder);

    /**
     * @notice Maps encoder IDs to their registered action encoder data
     * @param encoderId The encoder ID
     * @return implementation The implementation address
     * @return metadata The metadata string
     */
    function registeredActionEncoders(
        bytes32 encoderId
    ) external view returns (address implementation, string memory metadata);

    /**
     * @notice Maps deployment IDs to deployed encoder addresses
     * @param deployedEncoderId The deployment ID
     * @return encoder The deployed encoder address
     */
    function deployedEncoders(bytes32 deployedEncoderId) external view returns (IPayoutActionEncoder encoder);
}
