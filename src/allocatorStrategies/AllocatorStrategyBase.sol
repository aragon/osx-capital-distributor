// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { IAllocatorStrategy } from "../interfaces/IAllocatorStrategy.sol";
import { IAllocatorStrategyFactory } from "../interfaces/IAllocatorStrategyFactory.sol";
import { DaoAuthorizableUpgradeable } from "@aragon/commons/permission/auth/DaoAuthorizableUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";

/// @title AllocatorStrategyBase
/// @notice Base contract implementing the IAllocatorStrategy interface.
/// @dev Provides common functionality for allocation strategies. Implementing contracts should override
/// abstract functions to define specific allocation logic.
abstract contract AllocatorStrategyBase is
    IAllocatorStrategy,
    DaoAuthorizableUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable
{
    bytes32 public strategyTypeId;
    address public plugin;
    address public factory;

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

    /// @notice Initializes the strategy with the given parameters
    /// @param _strategyTypeId The type ID of the strategy
    /// @param _dao The DAO that will control this strategy
    /// @param _plugin The plugin address that created this strategy
    function initialize(
        bytes32 _strategyTypeId,
        IDAO _dao,
        address _plugin,
        bytes calldata
    )
        public
        virtual
        initializer
    {
        __DaoAuthorizableUpgradeable_init(_dao);
        __ERC165_init();

        // Set plugin as owner for backward compatibility, but store plugin separately
        __Ownable_init();
        _transferOwnership(_plugin);

        plugin = _plugin;
        strategyTypeId = _strategyTypeId;
        factory = msg.sender; // The factory is the one deploying this strategy
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /// @inheritdoc IAllocatorStrategy
    function getInitializationEncodingTypes() external view virtual override returns (string memory types);

    /// @inheritdoc IAllocatorStrategy
    function getCreationEncodingTypes() external view virtual override returns (string memory types);

    /// @inheritdoc IAllocatorStrategy
    function getClaimEncodingTypes() external view virtual override returns (string memory types);

    /// @inheritdoc IAllocatorStrategy
    function setAllocationCampaign(uint256 _campaignId, bytes calldata _auxData) public virtual override;

    /// @inheritdoc IAllocatorStrategy
    function getTotalClaimableAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    )
        public
        view
        virtual
        override
        returns (uint256 amount);

    /// @inheritdoc IAllocatorStrategy
    function getFeeConfiguration() public view virtual override returns (address recipient, uint256 basisPoints) {
        // Call the factory to get fee configuration for this instance
        return IAllocatorStrategyFactory(factory).getStrategyFeeByInstance(address(this));
    }

    /// @notice Returns true if this contract implements the interface defined by `interfaceId`
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return True if the contract implements `interfaceId`
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IAllocatorStrategy).interfaceId || super.supportsInterface(interfaceId);
    }
}
