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
     * @param active Whether the campaign is active and accepting claims
     * @param startTime The timestamp when the campaign becomes active (0 means no start time restriction)
     * @param endTime The timestamp when the campaign ends (0 means no end time restriction)
     */
    struct Campaign {
        bytes metadataURI;
        IAllocatorStrategy allocationStrategy;
        IERC20 token;
        IPayoutActionEncoder defaultPayoutActionEncoder;
        bool multipleClaimsAllowed;
        bool active;
        uint256 startTime; // 0 means no start time restriction
        uint256 endTime; // 0 means no end time restriction
    }

    /**
     * @notice Stores the amount claimed by a receiver for a specific campaign.
     */
    mapping(uint256 campaignId => mapping(address receiver => uint256 amount)) public claimed;

    /**
     * @notice Stores all campaign configurations, mapping a campaign ID to its Campaign struct.
     * The public visibility automatically creates a getter function:
     * `function campaigns(uint256 _campaignId) external view returns (bytes memory metadataURI, address allocationStrategy, address token, address defaultPayoutActionEncoder, bool multipleClaimsAllowed, bool active)`
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
        bool multipleClaimsAllowed,
        uint256 startTime,
        uint256 endTime
    );

    /// @notice Emitted when a payout is successfully claimed.
    /// @param campaignId The ID of the campaign from which the payout was claimed.
    /// @param recipient The address that received the payout.
    /// @param amount The amount of tokens claimed.
    /// @param totalClaimed The total amount claimed by this recipient for this campaign.
    event PayoutClaimed(uint256 indexed campaignId, address indexed recipient, uint256 amount, uint256 totalClaimed);

    /// @notice Emitted when a campaign is deactivated.
    /// @param campaignId The ID of the campaign that was deactivated.
    event CampaignDeactivated(uint256 indexed campaignId);

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

    /// @notice Thrown when a recipient has already claimed the maximum allowed amount.
    /// @param campaignId The ID of the campaign.
    /// @param recipient The address that tried to claim.
    /// @param alreadyClaimed The amount already claimed.
    /// @param maxClaimable The maximum amount claimable.
    error AlreadyClaimedMaxAmount(uint256 campaignId, address recipient, uint256 alreadyClaimed, uint256 maxClaimable);

    /// @notice Thrown when multiple claims are not allowed but recipient has already claimed.
    /// @param campaignId The ID of the campaign.
    /// @param recipient The address that tried to claim again.
    error MultipleClaimsNotAllowed(uint256 campaignId, address recipient);

    /// @notice Thrown when no claimable amount is available for the recipient.
    /// @param campaignId The ID of the campaign.
    /// @param recipient The address that tried to claim.
    error NoClaimableAmount(uint256 campaignId, address recipient);

    /// @notice Thrown when factory deployment returns invalid address.
    /// @param factoryType The type of factory that failed.
    error FactoryDeploymentFailed(string factoryType);

    /// @notice Thrown when external contract call fails during setup.
    /// @param target The contract that failed.
    /// @param functionName The function that failed.
    error ExternalCallFailed(address target, string functionName);

    /// @notice Thrown when trying to operate on an inactive campaign.
    /// @param campaignId The ID of the inactive campaign.
    error CampaignInactive(uint256 campaignId);

    /// @notice Thrown when array parameters have mismatched lengths.
    error ArrayLengthMismatch();

    /// @notice Thrown when invalid time bounds are provided for a campaign.
    error InvalidTimeBounds();

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
     * @param _startTime The timestamp when the campaign becomes active (0 means no start time restriction).
     * @param _endTime The timestamp when the campaign ends (0 means no end time restriction).
     */
    function createCampaign(
        bytes calldata _metadataURI,
        bytes32 _strategyId,
        AllocatorStrategyFactory.DeploymentParams calldata _strategyParams,
        bytes calldata _allocationStrategyAuxData,
        IERC20 _token,
        bytes32 _defaultActionEncoderId,
        bytes calldata _actionEncoderInitializationAuxData,
        bool _multipleClaimsAllowed,
        uint256 _startTime,
        uint256 _endTime
    ) external auth(CAMPAIGN_CREATOR_PERMISSION_ID) returns (uint256 id) {
        // Input validation in isolated scope
        {
            if (address(_token) == address(0)) {
                revert ZeroAddress("_token");
            }
            if (_startTime > 0 && _endTime > 0 && _startTime >= _endTime) {
                revert InvalidTimeBounds();
            }
        }

        // Campaign ID assignment
        {
            id = numCampaigns++;
        }

        // Deploy and setup allocation strategy
        {
            AllocatorStrategyFactory.DeploymentParams memory strategyParams = _strategyParams;
            bytes memory allocationStrategyAuxData = _allocationStrategyAuxData;

            address strategyAddress = allocatorStrategyFactory.getOrDeployStrategy(_strategyId, dao(), strategyParams);
            if (strategyAddress == address(0)) {
                revert FactoryDeploymentFailed("AllocatorStrategy");
            }

            campaigns[id].allocationStrategy = IAllocatorStrategy(strategyAddress);

            try IAllocatorStrategy(strategyAddress).setAllocationCampaign(id, allocationStrategyAuxData) {
                // Strategy setup successful
            } catch {
                revert ExternalCallFailed(strategyAddress, "setAllocationCampaign");
            }
        }

        // Setup action encoder
        {
            if (_defaultActionEncoderId != bytes32(0)) {
                bytes memory actionEncoderInitializationAuxData = _actionEncoderInitializationAuxData;

                IPayoutActionEncoder actionEncoder = actionEncoderFactory.getOrDeployActionEncoder(
                    _defaultActionEncoderId,
                    dao(),
                    actionEncoderInitializationAuxData
                );
                campaigns[id].defaultPayoutActionEncoder = actionEncoder;

                try actionEncoder.setupCampaign(id, actionEncoderInitializationAuxData) {
                    // Action encoder setup successful
                } catch {
                    revert ExternalCallFailed(address(actionEncoder), "setupCampaign");
                }
            }
        }

        // Set campaign fields
        {
            bytes memory metadataURI = _metadataURI;
            campaigns[id].metadataURI = metadataURI;
            campaigns[id].token = _token;
            campaigns[id].multipleClaimsAllowed = _multipleClaimsAllowed;
            campaigns[id].active = true;
            campaigns[id].startTime = _startTime;
            campaigns[id].endTime = _endTime;
        }

        // Emit event
        {
            emit CampaignCreated(
                id,
                campaigns[id].metadataURI,
                address(campaigns[id].allocationStrategy),
                _token,
                campaigns[id].defaultPayoutActionEncoder,
                _multipleClaimsAllowed,
                _startTime,
                _endTime
            );
        }
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
     * @param _recipient The address to get the payout
     * @param _auxData The data needed by the strategy to calculate the payout
     * @return amountToSend The amount of tokens the recipient should get
     */
    function claimCampaignPayout(
        uint256 _campaignId,
        address _recipient,
        bytes calldata _auxData
    ) public returns (uint256 amountToSend) {
        Campaign storage campaign = campaigns[_campaignId];

        // Check if campaign exists
        if (address(campaign.allocationStrategy) == address(0)) {
            revert CampaignNotFound(_campaignId);
        }

        // Check if campaign is active
        if (!campaign.active) {
            revert CampaignInactive(_campaignId);
        }

        // Check if campaign is within time bounds
        if (!_isCampaignWithinTimeBounds(campaign)) {
            revert CampaignInactive(_campaignId);
        }

        // Cache claimed amount to avoid repeated storage reads
        uint256 alreadyClaimed = claimed[_campaignId][_recipient];

        // Check if multiple claims are allowed first (fastest check)
        if (!campaign.multipleClaimsAllowed && alreadyClaimed > 0) {
            revert MultipleClaimsNotAllowed(_campaignId, _recipient);
        }

        amountToSend = campaign.allocationStrategy.getClaimeableAmount(_campaignId, _recipient, _auxData);

        // Check if there's anything to claim
        if (amountToSend == 0) {
            revert NoClaimableAmount(_campaignId, _recipient);
        }

        // Check if already claimed maximum amount
        if (alreadyClaimed >= amountToSend) {
            revert AlreadyClaimedMaxAmount(_campaignId, _recipient, alreadyClaimed, amountToSend);
        }

        Action[] memory actions;
        if (address(campaign.defaultPayoutActionEncoder) == address(0)) {
            actions = new Action[](1);
            actions[0].to = address(campaign.token);
            actions[0].data = abi.encodeCall(IERC20.transfer, (_recipient, amountToSend));
        } else {
            actions = campaign.defaultPayoutActionEncoder.buildActions(
                campaign.token,
                _recipient,
                amountToSend,
                msg.sender,
                _campaignId
            );
        }

        claimed[_campaignId][_recipient] = alreadyClaimed + amountToSend;

        // Generate dynamic execution ID for uniqueness and context
        bytes32 executionId = keccak256(abi.encodePacked(address(this), _campaignId));
        IExecutor(address(dao())).execute(executionId, actions, 0);

        emit PayoutClaimed(_campaignId, _recipient, amountToSend, claimed[_campaignId][_recipient]);

        return amountToSend;
    }

    /// @notice Returns the amount of tokens claimed by an account for a specific campaign.
    /// @param _campaignId The ID of the campaign.
    /// @param _account The address of the account.
    /// @return amount The amount of tokens claimed.
    function getClaimedAmount(uint256 _campaignId, address _account) public view returns (uint256 amount) {
        return claimed[_campaignId][_account];
    }

    /// @notice Checks if a campaign is currently active (both flag and time bounds).
    /// @param _campaignId The ID of the campaign to check.
    /// @return active Returns `true` if the campaign is active and within time bounds.
    function isCampaignActive(uint256 _campaignId) public view returns (bool active) {
        Campaign storage campaign = campaigns[_campaignId];

        // Check if campaign exists
        if (address(campaign.allocationStrategy) == address(0)) {
            return false;
        }

        // Check if campaign is flagged as active and within time bounds
        return campaign.active && _isCampaignWithinTimeBounds(campaign);
    }

    /// @notice Deactivates a campaign, preventing further claims.
    /// @param _campaignId The ID of the campaign to deactivate.
    function deactivateCampaign(uint256 _campaignId) external auth(CAMPAIGN_CREATOR_PERMISSION_ID) {
        Campaign storage campaign = campaigns[_campaignId];

        // Check if campaign exists
        if (address(campaign.allocationStrategy) == address(0)) {
            revert CampaignNotFound(_campaignId);
        }

        // Check if campaign is already inactive
        if (!campaign.active) {
            revert CampaignInactive(_campaignId);
        }

        campaign.active = false;
        emit CampaignDeactivated(_campaignId);
    }

    /// @notice Claims payouts from multiple campaigns in a single transaction.
    /// @param _campaignIds Array of campaign IDs to claim from.
    /// @param _recipients Array of recipient addresses (must match campaignIds length).
    /// @param _auxData Array of auxiliary data for each claim (must match campaignIds length).
    /// @return amounts Array of amounts claimed for each campaign.
    function batchClaimCampaignPayout(
        uint256[] calldata _campaignIds,
        address[] calldata _recipients,
        bytes[] calldata _auxData
    ) external returns (uint256[] memory amounts) {
        uint256 length = _campaignIds.length;
        if (length != _recipients.length || length != _auxData.length) {
            revert ArrayLengthMismatch();
        }

        amounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            amounts[i] = claimCampaignPayout(_campaignIds[i], _recipients[i], _auxData[i]);
        }

        return amounts;
    }

    /// @notice Checks if a campaign is currently within its time bounds.
    /// @param _campaign The campaign to check.
    /// @return Returns `true` if the campaign is within its time bounds.
    function _isCampaignWithinTimeBounds(Campaign storage _campaign) internal view returns (bool) {
        uint256 currentTime = block.timestamp;

        // Check start time (0 means no start restriction)
        if (_campaign.startTime > 0 && currentTime < _campaign.startTime) {
            return false;
        }

        // Check end time (0 means no end restriction)
        if (_campaign.endTime > 0 && currentTime >= _campaign.endTime) {
            return false;
        }

        return true;
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
