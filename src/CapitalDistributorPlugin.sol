// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.29;

import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {Action, IExecutor} from "@aragon/commons/executors/IExecutor.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PluginUUPSUpgradeable} from "@aragon/commons/plugin/PluginUUPSUpgradeable.sol";

import {IAllocatorStrategy} from "./interfaces/IAllocatorStrategy.sol";
import {IPayoutActionEncoder} from "./interfaces/IPayoutActionEncoder.sol";
import {AllocatorStrategyFactory} from "./AllocatorStrategyFactory.sol";
import {ActionEncoderFactory} from "./ActionEncoderFactory.sol";

/// @title CapitalDistributorPlugin
/// @author AragonX - 2025
/// @notice A plugin for Aragon DAOs that enables the creation and management of token distribution campaigns.
/// @dev This plugin allows DAOs to create campaigns with configurable allocation strategies and payout mechanisms.
/// Recipients can claim their allocated tokens based on the campaign's strategy rules and configuration.
contract CapitalDistributorPlugin is Initializable, ERC165Upgradeable, PluginUUPSUpgradeable {
    using SafeCastUpgradeable for uint256;

    /// @notice The ID of the permission required to create a campaign.
    bytes32 public constant CAMPAIGN_CREATOR_PERMISSION_ID = keccak256("CAMPAIGN_CREATOR_PERMISSION");

    /// @notice The AllocatorStrategyFactory instance used to deploy strategies.
    AllocatorStrategyFactory public allocatorStrategyFactory;

    /// @notice The ActionEncoderFactory instance used to encode actions.
    ActionEncoderFactory public actionEncoderFactory;

    /// @notice The number of campaigns created.
    uint256 public numCampaigns = 0;

    /**
     * @notice Represents a distribution campaign.
     * @custom:storage-location erc7201:capital.distributor.campaigns.struct
     * @param metadataURI URI pointing to the campaign's metadata (e.g., IPFS hash).
     * @param allocationStrategy The contract address responsible for determining allocation logic.
     * @param token The address of the token that will be used for the payouts
     * @param defaultPayoutActionEncoder The logic to execute when claiming the payout
     * @param multipleClaimsAllowed Whether recipients can claim multiple times for this campaign
     */
    struct Campaign {
        bytes metadataURI;
        IAllocatorStrategy allocationStrategy;
        IERC20 token;
        IPayoutActionEncoder defaultPayoutActionEncoder;
        bool multipleClaimsAllowed;
    }

    /**
     * @notice Stores the amount claimed by a receiver for a specific campaign.
     */
    mapping(uint256 campaignId => mapping(address receiver => uint256 amount)) public claimed;

    /**
     * @notice Stores all campaign configurations, mapping a campaign ID to its Campaign struct.
     * The public visibility automatically creates a getter function:
     * `function campaigns(uint256 _campaignId) external view returns (bytes memory metadataURI, address allocationStrategy, address vault, address token, address defaultPayoutActionEncoder, bool multipleClaimsAllowed)`
     */
    mapping(uint256 campaignId => Campaign) public campaigns;

    /**
     * @notice Stores all campaign recipient payout encoders, mapping a campaign ID to its recipient payout encoders.
     * The public visibility automatically creates a getter function:
     * `function campaignRecipientPayoutEncoder(uint256 _campaignId, address _recipient) external view returns (IPayoutActionEncoder)`
     */
    mapping(uint256 campaignId => mapping(address recipient => IPayoutActionEncoder actionEncoder))
        public campaignRecipientPayoutEncoder;

    /**
     * @notice Emitted when a campaign's details are created.
     * @param campaignId The unique identifier of the campaign that was created.
     * @param metadataURI The metadata URI for the campaign.
     * @param allocationStrategy The allocation strategy address for the campaign.
     * @param token The token address for the campaign.
     * @param defaultPayoutActionEncoder The default payout action encoder for the campaign.
     * @param multipleClaimsAllowed Whether multiple claims are allowed for this campaign.
     */
    event CampaignCreated(
        uint256 indexed campaignId,
        bytes metadataURI,
        address indexed allocationStrategy,
        IERC20 token,
        IPayoutActionEncoder defaultPayoutActionEncoder,
        bool multipleClaimsAllowed
    );

    /// @notice Thrown when a zero address is provided where a valid address is required.
    /// @param parameter The name of the parameter that was zero.
    error ZeroAddress(string parameter);

    /// @notice Thrown when trying to access a campaign that doesn't exist.
    /// @param campaignId The ID of the non-existent campaign.
    error CampaignNotFound(uint256 campaignId);

    /// @notice Thrown when the DAO in strategy params doesn't match the plugin's DAO.
    /// @param expected The expected DAO address.
    /// @param provided The provided DAO address.
    error DAOMismatch(address expected, address provided);

    /// @notice Thrown when empty metadata URI is provided.
    error EmptyMetadataURI();

    error NoPayoutToClaim();

    /// @notice Initializes the component to be used by inheriting contracts.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _allocatorStrategyFactory The AllocatorStrategyFactory instance.
    /// @param _actionEncoderFactory The ActionEncoderFactory instance.
    function initialize(
        IDAO _dao,
        AllocatorStrategyFactory _allocatorStrategyFactory,
        ActionEncoderFactory _actionEncoderFactory
    ) external initializer {
        __PluginUUPSUpgradeable_init(_dao);
        allocatorStrategyFactory = _allocatorStrategyFactory;
        actionEncoderFactory = _actionEncoderFactory;
    }

    /**
     * @notice Creates the details for a specific campaign.
     * @dev This function allows an authorized address to configure a new campaign.
     * @param _metadataURI The URI for the campaign's metadata.
     * @param _strategyId The strategy type ID to deploy or use.
     * @param _strategyParams Deployment parameters for the strategy.
     * @param _allocationStrategyAuxData Additional data needed to initialize the allocation strategy.
     * @param _token The token address that will be used for payouts.
     * @param _defaultActionEncoderId The action encoder type ID to deploy (use bytes32(0) for simple transfers).
     * @param _actionEncoderInitializationAuxData Additional data needed to initialize the action encoder.
     * @param _multipleClaimsAllowed Whether recipients can claim multiple times for this campaign.
     */
    function createCampaign(
        bytes calldata _metadataURI,
        bytes32 _strategyId,
        AllocatorStrategyFactory.DeploymentParams calldata _strategyParams,
        bytes calldata _allocationStrategyAuxData,
        IERC20 _token,
        bytes32 _defaultActionEncoderId,
        bytes calldata _actionEncoderInitializationAuxData,
        bool _multipleClaimsAllowed
    ) external auth(CAMPAIGN_CREATOR_PERMISSION_ID) returns (uint256 id) {
        // Input validation
        if (address(_token) == address(0)) {
            revert ZeroAddress("_token");
        }

        uint256 campaignId = numCampaigns++;
        // Get or deploy the allocation strategy using the factory
        address strategyAddress = allocatorStrategyFactory.getOrDeployStrategy(_strategyId, dao(), _strategyParams);
        IPayoutActionEncoder actionEncoder = IPayoutActionEncoder(address(0));
        if (_defaultActionEncoderId != bytes32(0)) {
            actionEncoder = actionEncoderFactory.getOrDeployActionEncoder(
                _defaultActionEncoderId,
                dao(),
                _actionEncoderInitializationAuxData
            );
        }

        Campaign storage campaign = campaigns[campaignId];
        campaign.metadataURI = _metadataURI;
        campaign.allocationStrategy = IAllocatorStrategy(strategyAddress);
        campaign.token = _token;
        campaign.defaultPayoutActionEncoder = actionEncoder;
        campaign.multipleClaimsAllowed = _multipleClaimsAllowed;

        IAllocatorStrategy(strategyAddress).setAllocationCampaign(campaignId, _allocationStrategyAuxData);

        if (actionEncoder != IPayoutActionEncoder(address(0))) {
            actionEncoder.setupCampaign(campaignId, _actionEncoderInitializationAuxData);
        }

        emit CampaignCreated(campaignId, _metadataURI, strategyAddress, _token, actionEncoder, _multipleClaimsAllowed);
        return campaignId;
    }

    /**
     * @notice Retrieves the publicly accessible fields of a Campaign for a given campaign ID.
     * @param _campaignId The unique identifier for the campaign.
     * @return The campaign details.
     */
    function getCampaign(uint256 _campaignId) public view returns (Campaign memory) {
        return campaigns[_campaignId];
    }

    /**
     * @notice Retrieves the amount of tokens to send to the recipient of a campaign
     * @param _campaignId The unique identifier for the campaign.
     * @param _recipient The address to get the payout
     * @param _auxData The data needed by the strategy to calculate the payout
     * @return amountToSend The amount of tokens the recipient should get
     */
    function getCampaignPayout(
        uint256 _campaignId,
        address _recipient,
        bytes calldata _auxData
    ) public view returns (uint256 amountToSend) {
        Campaign storage campaign = campaigns[_campaignId];

        // Check if campaign exists
        if (address(campaign.allocationStrategy) == address(0)) {
            revert CampaignNotFound(_campaignId);
        }

        amountToSend = campaign.allocationStrategy.getClaimeableAmount(_campaignId, _recipient, _auxData);
    }

    /**
     * @notice Sends the amount of tokens to the recipient of a campaign
     * @param _campaignId The unique identifier for the campaign.
     * @param _receiver The address to get the payout
     * @param _auxData The data needed by the strategy to calculate the payout
     * @return amountToSend The amount of tokens the recipient should get
     */
    function claimCampaignPayout(
        uint256 _campaignId,
        address _receiver,
        bytes calldata _auxData
    ) public returns (uint256 amountToSend) {
        Campaign storage campaign = campaigns[_campaignId];

        // Check if campaign exists
        if (address(campaign.allocationStrategy) == address(0)) {
            revert CampaignNotFound(_campaignId);
        }

        amountToSend = campaign.allocationStrategy.getClaimeableAmount(_campaignId, _receiver, _auxData);

        // Cache claimed amount to avoid repeated storage reads
        uint256 alreadyClaimed = claimed[_campaignId][_receiver];

        if (alreadyClaimed >= amountToSend || (!campaign.multipleClaimsAllowed && alreadyClaimed > 0)) {
            revert NoPayoutToClaim();
        }

        Action[] memory actions;
        if (address(campaign.defaultPayoutActionEncoder) == address(0)) {
            actions = new Action[](1);
            actions[0].to = address(campaign.token);
            actions[0].data = abi.encodeCall(IERC20.transfer, (_receiver, amountToSend));
        } else {
            actions = campaign.defaultPayoutActionEncoder.buildActions(
                campaign.token,
                _receiver,
                amountToSend,
                msg.sender,
                _campaignId
            );
        }

        claimed[_campaignId][_receiver] = alreadyClaimed + amountToSend;

        // TODO: Change the call Id for something dynamic
        IExecutor(address(dao())).execute(bytes32(uint256(1)), actions, 0);
    }

    /// @notice Returns the amount of tokens claimed by an account for a specific campaign.
    /// @param _campaignId The ID of the campaign.
    /// @param _account The address of the account.
    /// @return amount The amount of tokens claimed.
    function getClaimedAmount(uint256 _campaignId, address _account) public view returns (uint256 amount) {
        return claimed[_campaignId][_account];
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
    uint256[46] private __gap;
}
