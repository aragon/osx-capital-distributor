// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { IPayoutActionEncoder } from "../interfaces/IPayoutActionEncoder.sol";
import { DaoAuthorizableUpgradeable } from "@aragon/commons/permission/auth/DaoAuthorizableUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { Action } from "@aragon/commons/executors/IExecutor.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";

/// @title PayoutActionEncoderBase
/// @notice Base contract implementing the IPayoutActionEncoder interface.
/// @dev Provides common functionality for action encoders. Implementing contracts should override
/// abstract functions to define specific allocation logic.
abstract contract PayoutActionEncoderBase is
    IPayoutActionEncoder,
    DaoAuthorizableUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable
{
    bytes32 public encoderId;

    // =========================================================================
    // Constructor
    // =========================================================================
    constructor() {
        // Disable initializers to prevent implementation contract from being initialized
        _disableInitializers();
    }

    // =========================================================================
    // Initializer
    // =========================================================================

    /// @notice Initializes the action encoder with the given parameters
    /// @param _encoderId The type ID of the strategy
    /// @param _dao The DAO that will control this strategy
    function initialize(bytes32 _encoderId, IDAO _dao, address _owner, bytes calldata) public virtual initializer {
        __DaoAuthorizableUpgradeable_init(_dao);
        // Owner will be set directly to the plugin who's calling the initialize
        __Ownable_init();
        __ERC165_init();
        _transferOwnership(_owner);

        encoderId = _encoderId;
    }

    // =========================================================================
    // View Functions
    // =========================================================================
    /// @inheritdoc IPayoutActionEncoder
    function getCreationEncodingTypes() external view virtual override returns (string memory types);

    /// @inheritdoc IPayoutActionEncoder
    function getClaimEncodingTypes() external view virtual override returns (string memory types);

    /// @inheritdoc IPayoutActionEncoder
    function setupCampaign(uint256 _campaignId, bytes calldata _auxData) external virtual override;

    /// @inheritdoc IPayoutActionEncoder
    function buildActions(
        IERC20 _token,
        address _recipient,
        uint256 _amount,
        address _caller, // Added for context, might be useful for builders
        uint256 _campaignId, // Added for context
        bytes calldata _encoderAuxData
    )
        external
        view
        virtual
        override
        returns (Action[] memory actions);

    /// @notice Returns whether the contract supports a given interface
    /// @param interfaceId The interface identifier
    /// @return True if the contract supports the interface
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IPayoutActionEncoder).interfaceId || super.supportsInterface(interfaceId);
    }
}
