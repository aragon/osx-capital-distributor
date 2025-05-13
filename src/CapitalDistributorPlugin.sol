// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PluginUUPSUpgradeable} from "@aragon/commons/plugin/PluginUUPSUpgradeable.sol";

import {IAllocatorStrategy} from "./interfaces/IAllocatorStrategy.sol";

/// @title OptimisticTokenVotingPlugin
/// @author Aragon Association - 2023
/// @notice The abstract implementation of optimistic majority plugins.
///
/// @dev This contract implements the `IOptimisticTokenVoting` interface.
contract CapitalDistributorPlugin is Initializable, ERC165Upgradeable, PluginUUPSUpgradeable {
    using SafeCastUpgradeable for uint256;

    /// @notice The ID of the permission required to create a proposal.
    bytes32 public constant CAMPAIGN_CREATOR_PERMISSION_ID = keccak256("CAMPAIGN_CREATOR_PERMISSION");

    /**
     * @notice Represents a distribution campaign.
     * @custom:storage-location erc7201:capital.distributor.campaigns.struct
     * @param metadataURI URI pointing to the campaign's metadata (e.g., IPFS hash).
     * @param allocationStrategy The contract address responsible for determining allocation logic.
     * @param vault The contract address of the vault holding the assets for this campaign.
     */
    struct Campaign {
        bytes metadataURI;
        IAllocatorStrategy allocationStrategy;
        address vault;
    }

    /**
     * @notice Stores all campaign configurations, mapping a campaign ID to its Campaign struct.
     * The public visibility automatically creates a getter function:
     * `function campaigns(uint256 _campaignId) external view returns (bytes memory metadataURI, address allocationStrategy, address vault)`
     */
    mapping(uint256 => Campaign) public campaigns;

    /**
     * @notice Emitted when a campaign's details are created.
     * @param campaignId The unique identifier of the campaign that was updated.
     * @param metadataURI The new metadata URI for the campaign.
     * @param allocationStrategy The new allocation strategy address for the campaign.
     * @param vault The new vault address for the campaign.
     */
    event CampaignCreated(
        uint256 indexed campaignId,
        bytes metadataURI,
        address indexed allocationStrategy,
        address indexed vault
    );

    /// @notice Thrown if a date is out of bounds.
    /// @param limit The limit value.
    /// @param actual The actual value.
    error DateOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Initializes the component to be used by inheriting contracts.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    function initialize(IDAO _dao) external initializer {
        __PluginUUPSUpgradeable_init(_dao);
    }

    /**
     * @notice Creates the details for a specific campaign.
     * @dev This function allows an authorized address to configure a new campaign or modify an existing one.
     * @param _campaignId The unique identifier for the campaign.
     * @param _metadataURI The URI for the campaign's metadata.
     * @param _allocationStrategy The address of the allocation strategy contract.
     * @param _vault The address of the vault contract.
     */
    function setCampaign(
        uint256 _campaignId,
        bytes calldata _metadataURI,
        address _allocationStrategy,
        address _vault
    ) external auth(CAMPAIGN_CREATOR_PERMISSION_ID) returns (uint256 id) {
        // Add appropriate access control
        campaigns[_campaignId] = Campaign({
            metadataURI: _metadataURI,
            allocationStrategy: IAllocatorStrategy(_allocationStrategy),
            vault: _vault
        });

        emit CampaignCreated(_campaignId, _metadataURI, _allocationStrategy, _vault);
        return _campaignId;
    }

    /**
     * @notice Retrieves the full Campaign struct for a given campaign ID.
     * @param _campaignId The unique identifier for the campaign.
     * @return The Campaign struct containing its metadataURI, allocationStrategy, and vault.
     */
    function getCampaign(uint256 _campaignId) public view returns (Campaign memory) {
        return campaigns[_campaignId];
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override(ERC165Upgradeable, PluginUUPSUpgradeable) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    /// @notice This empty reserved space is put in place to allow future versions to add new variables without shifting down storage in the inheritance chain (see [OpenZeppelin's guide about storage gaps](https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps)).
    uint256[47] private __gap;
}
