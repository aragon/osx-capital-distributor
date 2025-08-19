// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {IPayoutActionEncoder} from "./IPayoutActionEncoder.sol";
import {FactoryBase} from "../factories/FactoryBase.sol";

/// @title IActionEncoderFactory
/// @notice Interface for the ActionEncoderFactory contract.
interface IActionEncoderFactory {
    /// @notice Emitted when an action encoder is deployed (legacy event)
    /// @param encoderId The unique identifier for the action encoder
    /// @param encoder The address of the deployed action encoder instance
    event ActionEncoderDeployed(bytes32 indexed encoderId, IPayoutActionEncoder indexed encoder);

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
}
