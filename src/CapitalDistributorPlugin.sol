// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.29;

import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { SafeCastUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { Action, IExecutor } from "@aragon/commons/executors/IExecutor.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { PluginUUPSUpgradeable } from "@aragon/commons/plugin/PluginUUPSUpgradeable.sol";
import { MetadataExtensionUpgradeable } from "@aragon/commons/utils/metadata/MetadataExtensionUpgradeable.sol";

import { IAllocatorStrategy } from "./interfaces/IAllocatorStrategy.sol";
import { IPayoutActionEncoder } from "./interfaces/IPayoutActionEncoder.sol";
import { AllocatorStrategyFactory } from "./factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "./factories/ActionEncoderFactory.sol";

/// @title CapitalDistributorPlugin
/// @author AragonX - 2025
/// @notice A plugin for Aragon DAOs that enables the creation and management of token distribution campaigns.
/// @dev This plugin allows DAOs to create campaigns with configurable allocation strategies and payout mechanisms.
/// Recipients can claim their allocated tokens based on the campaign's strategy rules and configuration.
contract CapitalDistributorPlugin is
    Initializable,
    ERC165Upgradeable,
    PluginUUPSUpgradeable,
    MetadataExtensionUpgradeable
{
    using SafeCastUpgradeable for uint256;

    /// @notice The ID of the permission required to create a campaign.
    bytes32 public constant CAMPAIGN_MANAGER_PERMISSION_ID = keccak256("CAMPAIGN_MANAGER_PERMISSION");

    /// @notice Represents the different states a campaign can be in
    enum CampaignState {
        ACTIVE, // Normal operation, claims allowed
        PAUSED, // Temporarily paused (for updates), can be resumed
        ENDED // Permanently ended, cannot be resumed

    }

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
     * @param actionEncoder The logic to execute when claiming the payout
     * @param multipleClaimsAllowed Whether recipients can claim multiple times for this campaign
     * @param state The current state of the campaign (ACTIVE, PAUSED, or ENDED)
     * @param startTime The timestamp when the campaign becomes active (0 means no start time restriction)
     * @param endTime The timestamp when the campaign ends (0 means no end time restriction)
     */
    struct Campaign {
        bytes metadataUri;
        IAllocatorStrategy allocationStrategy;
        IERC20 token;
        IPayoutActionEncoder actionEncoder;
        bool multipleClaimsAllowed;
        CampaignState state;
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
     * `function campaigns(uint256 _campaignId) external view returns (bytes memory metadataURI, address
     * allocationStrategy, address token, address actionEncoder, bool multipleClaimsAllowed, CampaignState state)`
     */
    mapping(uint256 campaignId => Campaign) public campaigns;

    /**
     * @notice Strategy configuration for a campaign
     * @param strategyId The strategy type ID to deploy or use
     * @param strategyParams Deployment parameters for the strategy
     * @param initData Additional data needed to initialize the allocation strategy
     */
    struct StrategyConfig {
        bytes32 strategyId;
        bytes strategyParams;
        bytes initData;
    }

    /**
     * @notice Payout configuration for a campaign
     * @param token The token address that will be used for payouts
     * @param actionEncoderId The action encoder type ID to deploy (use bytes32(0) for simple transfers)
     * @param actionEncoderInitData Additional data needed to initialize the action encoder
     */
    struct PayoutConfig {
        IERC20 token;
        bytes32 actionEncoderId;
        bytes actionEncoderInitData;
    }

    /**
     * @notice Campaign settings for time bounds and claim behavior
     * @param multipleClaimsAllowed Whether recipients can claim multiple times for this campaign
     * @param startTime The timestamp when the campaign becomes active (0 means no start time restriction)
     * @param endTime The timestamp when the campaign ends (0 means no end time restriction)
     */
    struct CampaignSettings {
        bool multipleClaimsAllowed;
        uint256 startTime;
        uint256 endTime;
    }

    /**
     * @notice Emitted when a campaign's details are created.
     * @param campaignId The unique identifier of the campaign that was created.
     * @param metadataUri The metadata URI for the campaign.
     * @param allocationStrategy The allocation strategy address for the campaign.
     * @param token The token address for the campaign.
     * @param actionEncoder The default payout action encoder for the campaign.
     * @param multipleClaimsAllowed Whether multiple claims are allowed for this campaign.
     */
    event CampaignCreated(
        uint256 indexed campaignId,
        bytes metadataUri,
        address indexed allocationStrategy,
        IERC20 token,
        IPayoutActionEncoder actionEncoder,
        bool multipleClaimsAllowed,
        uint256 startTime,
        uint256 endTime
    );

    /// @notice Emitted when a payout is successfully claimed.
    /// @param campaignId The ID of the campaign from which the payout was claimed.
    /// @param recipient The address that received the payout.
    /// @param amount The amount of tokens claimed.
    event PayoutClaimed(uint256 indexed campaignId, address indexed recipient, uint256 amount);

    /// @notice Emitted when a fee is collected during a claim.
    /// @param campaignId The ID of the campaign.
    /// @param feeRecipient The address that received the fee.
    /// @param feeAmount The amount of the fee.
    event FeeCollected(uint256 indexed campaignId, address indexed feeRecipient, uint256 feeAmount);

    /// @notice Emitted when a campaign is paused.
    /// @param campaignId The ID of the campaign that was paused.
    event CampaignPaused(uint256 indexed campaignId);

    /// @notice Emitted when a campaign is resumed from pause.
    /// @param campaignId The ID of the campaign that was resumed.
    event CampaignResumed(uint256 indexed campaignId);

    /// @notice Emitted when a campaign is permanently ended.
    /// @param campaignId The ID of the campaign that was ended.
    event CampaignEnded(uint256 indexed campaignId);

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

    /// @notice Thrown when trying to claim from a campaign that is not active.
    /// @param campaignId The ID of the campaign.
    /// @param currentState The current state of the campaign.
    error CampaignNotActive(uint256 campaignId, CampaignState currentState);

    /// @notice Thrown when trying to perform an invalid state transition.
    /// @param campaignId The ID of the campaign.
    /// @param currentState The current state of the campaign.
    /// @param attemptedState The attempted new state.
    error InvalidStateTransition(uint256 campaignId, CampaignState currentState, CampaignState attemptedState);

    /// @notice Thrown when trying to claim from a campaign outside its time bounds.
    /// @param campaignId The ID of the campaign.
    /// @param currentTime The current block timestamp.
    /// @param startTime The campaign start time (0 if no restriction).
    /// @param endTime The campaign end time (0 if no restriction).
    error CampaignOutsideTimeBounds(uint256 campaignId, uint256 currentTime, uint256 startTime, uint256 endTime);

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
    )
        external
        initializer
    {
        __PluginUUPSUpgradeable_init(_dao);
        allocatorStrategyFactory = _allocatorStrategyFactory;
        actionEncoderFactory = _actionEncoderFactory;
    }

    /**
     * @notice Creates the details for a specific campaign.
     * @dev This function allows an authorized address to configure a new campaign.
     * @param _metadataURI URI pointing to the campaign's metadata (e.g., IPFS hash).
     * @param _strategy The strategy configuration.
     * @param _payout The payout configuration.
     * @param _settings The campaign settings (time bounds and claim behavior).
     */
    function createCampaign(
        bytes calldata _metadataURI,
        StrategyConfig calldata _strategy,
        PayoutConfig calldata _payout,
        CampaignSettings calldata _settings
    )
        external
        auth(CAMPAIGN_MANAGER_PERMISSION_ID)
        returns (uint256 id)
    {
        // Input validation
        if (address(_payout.token) == address(0)) {
            revert ZeroAddress("_token");
        }
        if (_settings.startTime > 0 && _settings.endTime > 0 && _settings.startTime >= _settings.endTime) {
            revert InvalidTimeBounds();
        }

        // Campaign ID assignment
        id = numCampaigns;
        ++numCampaigns;

        // Get storage reference early to reduce stack usage
        Campaign storage campaign = campaigns[id];

        // Deploy and setup allocation strategy
        address strategyAddress = allocatorStrategyFactory.getOrDeployStrategy(
            _strategy.strategyId, 
            dao(), 
            _strategy.strategyParams
        );
        if (strategyAddress == address(0)) {
            revert FactoryDeploymentFailed("AllocatorStrategy");
        }

        campaign.allocationStrategy = IAllocatorStrategy(strategyAddress);

        try IAllocatorStrategy(strategyAddress).setAllocationCampaign(
            id, 
            _strategy.initData
        ) {
            // Strategy setup successful
        } catch {
            revert ExternalCallFailed(strategyAddress, "setAllocationCampaign");
        }

        // Setup action encoder if provided
        if (_payout.actionEncoderId != bytes32(0)) {
            IPayoutActionEncoder actionEncoder = actionEncoderFactory.getOrDeployActionEncoder(
                _payout.actionEncoderId, 
                dao(), 
                _payout.actionEncoderInitData
            );
            campaign.actionEncoder = actionEncoder;

            try actionEncoder.setupCampaign(id, _payout.actionEncoderInitData) {
                // Action encoder setup successful
            } catch {
                revert ExternalCallFailed(address(actionEncoder), "setupCampaign");
            }
        }

        // Set campaign fields
        campaign.metadataUri = _metadataURI;
        campaign.token = _payout.token;
        campaign.multipleClaimsAllowed = _settings.multipleClaimsAllowed;
        campaign.state = CampaignState.ACTIVE;
        campaign.startTime = _settings.startTime;
        campaign.endTime = _settings.endTime;

        // Emit event
        emit CampaignCreated(
            id,
            _metadataURI,
            address(campaign.allocationStrategy),
            _payout.token,
            campaign.actionEncoder,
            _settings.multipleClaimsAllowed,
            _settings.startTime,
            _settings.endTime
        );
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
     * @notice Retrieves strategy id for a given campaign ID.
     * @param _campaignId The unique identifier for the campaign.
     * @return The campaign strategy id.
     */
    function getCampaignStrategyId(uint256 _campaignId) public view returns (bytes32) {
        return campaigns[_campaignId].allocationStrategy.strategyTypeId();
    }

    /**
     * @notice Retrieves encoder id for a given campaign ID.
     * @param _campaignId The unique identifier for the campaign.
     * @return The campaign encoder id.
     */
    function getCampaignEncoderId(uint256 _campaignId) public view returns (bytes32) {
        return campaigns[_campaignId].actionEncoder.encoderId();
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
    )
        public
        view
        returns (uint256 amountToSend)
    {
        _requireCampaignExists(_campaignId);
        Campaign storage campaign = campaigns[_campaignId];

        amountToSend = campaign.allocationStrategy.getClaimeableAmount(_campaignId, _recipient, _auxData);
    }

    /// @notice Internal helper to validate campaign claim eligibility
    /// @dev Checks campaign existence, state, and time bounds
    /// @param _campaignId The campaign ID to validate
    /// @return campaign The validated campaign storage reference
    function _validateCampaignClaimEligibility(uint256 _campaignId) internal view returns (Campaign storage campaign) {
        _requireCampaignExists(_campaignId);
        campaign = campaigns[_campaignId];

        // Check if campaign is active
        if (campaign.state != CampaignState.ACTIVE) {
            revert CampaignNotActive(_campaignId, campaign.state);
        }

        // Check if campaign is within time bounds
        if (!_isCampaignWithinTimeBounds(campaign)) {
            revert CampaignOutsideTimeBounds(_campaignId, block.timestamp, campaign.startTime, campaign.endTime);
        }
    }

    /// @notice Internal helper to execute payout actions through the DAO
    /// @dev Builds actions and executes them through the DAO
    /// @param _campaign The campaign being claimed from
    /// @param _campaignId The campaign ID
    /// @param _payoutAddress Where to send the funds
    /// @param _amountToSend The amount to send
    /// @param _feeRecipient The fee recipient address (if applicable)
    /// @param _feeAmount The fee amount (if applicable)
    /// @param _encoderAuxData Auxiliary data for the action encoder
    function _executePayout(
        Campaign storage _campaign,
        uint256 _campaignId,
        address _payoutAddress,
        uint256 _amountToSend,
        address _feeRecipient,
        uint256 _feeAmount,
        bytes calldata _encoderAuxData
    )
        internal
    {
        Action[] memory actions = _buildPayoutActions(
            _campaign, _payoutAddress, _amountToSend, _feeRecipient, _feeAmount, _campaignId, _encoderAuxData
        );

        bytes32 executionId = keccak256(abi.encodePacked(address(this), _campaignId, _payoutAddress, block.timestamp));

        IExecutor(address(dao())).execute(executionId, actions, 0);

        // Note: Event emission will be handled by the calling function
        // since it knows who the actual recipient is and can control event order
    }

    /**
     * @notice Sends the amount of tokens to the recipient of a campaign
     * @param _campaignId The unique identifier for the campaign.
     * @param _recipient The address to get the payout
     * @param _strategyAuxData The data needed by the strategy to calculate the payout
     * @param _encoderAuxData The data needed by the encoder to send the payout
     * @return amountToSend The amount of tokens the recipient should get
     */
    function claimCampaignPayout(
        uint256 _campaignId,
        address _recipient,
        bytes calldata _strategyAuxData,
        bytes calldata _encoderAuxData
    )
        public
        returns (uint256 amountToSend)
    {
        Campaign storage campaign = _validateCampaignClaimEligibility(_campaignId);

        // Check if multiple claims are allowed
        if (!campaign.multipleClaimsAllowed && claimed[_campaignId][_recipient] > 0) {
            revert MultipleClaimsNotAllowed(_campaignId, _recipient);
        }

        uint256 totalAmountToSend =
            campaign.allocationStrategy.getClaimeableAmount(_campaignId, _recipient, _strategyAuxData);

        if (totalAmountToSend == 0) {
            revert NoClaimableAmount(_campaignId, _recipient);
        }

        // Check if already claimed all payout assigned
        if (claimed[_campaignId][_recipient] >= totalAmountToSend) {
            revert AlreadyClaimedMaxAmount(_campaignId, _recipient, claimed[_campaignId][_recipient], totalAmountToSend);
        }

        amountToSend = totalAmountToSend - claimed[_campaignId][_recipient];
        
        // Get fee configuration and calculate
        (address feeRecipient, uint256 feeBasisPoints) = campaign.allocationStrategy.getFeeConfiguration();
        uint256 feeAmount = 0;
        if (feeBasisPoints > 0 && feeRecipient != address(0)) {
            feeAmount = (amountToSend * feeBasisPoints) / 10_000;
            amountToSend = amountToSend - feeAmount;
        }

        claimed[_campaignId][_recipient] = totalAmountToSend;

        // Execute payout using helper
        _executePayout(
            campaign,
            _campaignId,
            _recipient, // Send to recipient address
            amountToSend,
            feeRecipient,
            feeAmount,
            _encoderAuxData
        );

        emit PayoutClaimed(_campaignId, _recipient, amountToSend);
        if (feeAmount > 0) {
            emit FeeCollected(_campaignId, feeRecipient, feeAmount);
        }
    }

    /// @notice Claims the caller's campaign payout and sends it to a specified address.
    /// @dev Security: Only msg.sender can claim their own allocation. This prevents claiming
    ///      on behalf of others while allowing redirection of one's own payout to a different
    ///      address (e.g., a savings wallet, vault, or payment processor).
    /// @param _campaignId The ID of the campaign to claim from.
    /// @param _payoutAddress The address where the payout will be sent.
    /// @param _strategyAuxData Auxiliary data for the allocation strategy.
    /// @param _encoderAuxData Auxiliary data for the action encoder.
    /// @return amountToSend The amount of tokens sent to the payout address.
    function claimCampaignPayoutToAddress(
        uint256 _campaignId,
        address _payoutAddress,
        bytes calldata _strategyAuxData,
        bytes calldata _encoderAuxData
    )
        public
        returns (uint256 amountToSend)
    {
        // Common validation
        Campaign storage campaign = _validateCampaignClaimEligibility(_campaignId);

        // Check multiple claims allowed
        if (!campaign.multipleClaimsAllowed && claimed[_campaignId][msg.sender] > 0) {
            revert MultipleClaimsNotAllowed(_campaignId, msg.sender);
        }

        // Get claimable amount for msg.sender
        uint256 totalAmountToSend =
            campaign.allocationStrategy.getClaimeableAmount(_campaignId, msg.sender, _strategyAuxData);

        if (totalAmountToSend == 0) {
            revert NoClaimableAmount(_campaignId, msg.sender);
        }

        if (claimed[_campaignId][msg.sender] >= totalAmountToSend) {
            revert AlreadyClaimedMaxAmount(_campaignId, msg.sender, claimed[_campaignId][msg.sender], totalAmountToSend);
        }

        amountToSend = totalAmountToSend - claimed[_campaignId][msg.sender];

        // Get fee configuration and calculate
        (address feeRecipient, uint256 feeBasisPoints) = campaign.allocationStrategy.getFeeConfiguration();
        uint256 feeAmount = 0;
        if (feeBasisPoints > 0 && feeRecipient != address(0)) {
            feeAmount = (amountToSend * feeBasisPoints) / 10_000;
            amountToSend = amountToSend - feeAmount;
        }

        // Update claimed amount
        claimed[_campaignId][msg.sender] = totalAmountToSend;

        // Execute payout using helper - send to specified address
        _executePayout(
            campaign,
            _campaignId,
            _payoutAddress, // Send to specified address
            amountToSend,
            feeRecipient,
            feeAmount,
            _encoderAuxData
        );

        emit PayoutClaimed(_campaignId, msg.sender, amountToSend);
        if (feeAmount > 0) {
            emit FeeCollected(_campaignId, feeRecipient, feeAmount);
        }
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

        // Check if campaign is in active state and within time bounds
        return campaign.state == CampaignState.ACTIVE && _isCampaignWithinTimeBounds(campaign);
    }

    /// @notice Checks if a campaign is currently paused (both flag and time bounds).
    /// @param _campaignId The ID of the campaign to check.
    /// @return active Returns `true` if the campaign is paused and within time bounds.
    function isCampaignPaused(uint256 _campaignId) public view returns (bool active) {
        Campaign storage campaign = campaigns[_campaignId];

        // Check if campaign exists
        if (address(campaign.allocationStrategy) == address(0)) {
            return false;
        }

        // Check if campaign is in active state and within time bounds
        return campaign.state == CampaignState.PAUSED && _isCampaignWithinTimeBounds(campaign);
    }

    /// @notice Pauses a campaign temporarily, preventing further claims.
    /// @dev Can only be called on ACTIVE campaigns. Paused campaigns can be resumed.
    /// @param _campaignId The ID of the campaign to pause.
    function pauseCampaign(uint256 _campaignId) external auth(CAMPAIGN_MANAGER_PERMISSION_ID) {
        _requireCampaignExists(_campaignId);
        Campaign storage campaign = campaigns[_campaignId];

        if (campaign.state != CampaignState.ACTIVE) {
            revert InvalidStateTransition(_campaignId, campaign.state, CampaignState.PAUSED);
        }

        campaign.state = CampaignState.PAUSED;
        emit CampaignPaused(_campaignId);
    }

    /// @notice Resumes a paused campaign, allowing claims again.
    /// @dev Can only be called on PAUSED campaigns.
    /// @param _campaignId The ID of the campaign to resume.
    function resumeCampaign(uint256 _campaignId) external auth(CAMPAIGN_MANAGER_PERMISSION_ID) {
        _requireCampaignExists(_campaignId);
        Campaign storage campaign = campaigns[_campaignId];

        if (campaign.state != CampaignState.PAUSED) {
            revert InvalidStateTransition(_campaignId, campaign.state, CampaignState.ACTIVE);
        }

        campaign.state = CampaignState.ACTIVE;
        emit CampaignResumed(_campaignId);
    }

    /// @notice Permanently ends a campaign, preventing all future claims.
    /// @dev Can be called on ACTIVE or PAUSED campaigns. This action is irreversible.
    /// @param _campaignId The ID of the campaign to end.
    function endCampaign(uint256 _campaignId) external auth(CAMPAIGN_MANAGER_PERMISSION_ID) {
        _requireCampaignExists(_campaignId);
        Campaign storage campaign = campaigns[_campaignId];

        if (campaign.state == CampaignState.ENDED) {
            revert InvalidStateTransition(_campaignId, campaign.state, CampaignState.ENDED);
        }

        campaign.state = CampaignState.ENDED;
        emit CampaignEnded(_campaignId);
    }

    /// @notice Claims payouts from multiple campaigns in a single transaction.
    /// @param _campaignIds Array of campaign IDs to claim from.
    /// @param _recipients Array of recipient addresses (must match campaignIds length).
    /// @param _strategiesAuxData Array of auxiliary data for each claim (must match campaignIds length).
    /// @param _encodersAuxData Array of auxiliary data for each claim (must match campaignIds length).
    /// @return amounts Array of amounts claimed for each campaign.
    function batchClaimCampaignPayout(
        uint256[] calldata _campaignIds,
        address[] calldata _recipients,
        bytes[] calldata _strategiesAuxData,
        bytes[] calldata _encodersAuxData
    )
        external
        returns (uint256[] memory amounts)
    {
        uint256 length = _campaignIds.length;
        if (length != _recipients.length || length != _strategiesAuxData.length || length != _encodersAuxData.length) {
            revert ArrayLengthMismatch();
        }

        amounts = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] =
                claimCampaignPayout(_campaignIds[i], _recipients[i], _strategiesAuxData[i], _encodersAuxData[i]);
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

    /// @notice Gets the strategy initialization encoding types for a strategy type
    /// @param _strategyTypeId The strategy type ID
    /// @return types Comma-separated string of Solidity type strings expected for strategy initialization
    function getStrategyInitializationEncodingTypes(bytes32 _strategyTypeId)
        external
        view
        returns (string memory types)
    {
        // Get the implementation address from the factory's registeredTypes mapping
        (address implementation,) = allocatorStrategyFactory.registeredTypes(_strategyTypeId);
        require(implementation != address(0), "Strategy type not found");

        // Query the implementation directly for encoding types
        return IAllocatorStrategy(implementation).getInitializationEncodingTypes();
    }

    /// @notice Gets the strategy creation encoding types for a campaign
    /// @param _campaignId The campaign ID
    /// @return types Comma-separated string of Solidity type strings expected for strategy creation
    function getStrategyCreationEncodingTypes(uint256 _campaignId) external view returns (string memory types) {
        _requireCampaignExists(_campaignId);
        return campaigns[_campaignId].allocationStrategy.getCreationEncodingTypes();
    }

    /// @notice Gets the strategy claim encoding types for a campaign
    /// @param _campaignId The campaign ID
    /// @return types Comma-separated string of Solidity type strings expected for strategy claiming
    function getStrategyClaimEncodingTypes(uint256 _campaignId) external view returns (string memory types) {
        _requireCampaignExists(_campaignId);
        return campaigns[_campaignId].allocationStrategy.getClaimEncodingTypes();
    }

    /// @notice Gets the encoder creation encoding types for a campaign
    /// @param _campaignId The campaign ID
    /// @return types Comma-separated string of Solidity type strings expected for encoder creation
    function getEncoderCreationEncodingTypes(uint256 _campaignId) external view returns (string memory types) {
        _requireCampaignExists(_campaignId);
        return campaigns[_campaignId].actionEncoder.getCreationEncodingTypes();
    }

    /// @notice Gets the encoder claim encoding types for a campaign
    /// @param _campaignId The campaign ID
    /// @return types Comma-separated string of Solidity type strings expected for encoder claiming
    function getEncoderClaimEncodingTypes(uint256 _campaignId) external view returns (string memory types) {
        _requireCampaignExists(_campaignId);
        return campaigns[_campaignId].actionEncoder.getClaimEncodingTypes();
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable, PluginUUPSUpgradeable, MetadataExtensionUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId);
    }

    /// @notice Internal helper to check if a campaign exists
    /// @param _campaignId The campaign ID to check
    function _requireCampaignExists(uint256 _campaignId) internal view {
        if (address(campaigns[_campaignId].allocationStrategy) == address(0)) {
            revert CampaignNotFound(_campaignId);
        }
    }

    /// @notice Builds all necessary actions for a payout claim.
    /// @param _campaign The campaign configuration.
    /// @param _recipient The recipient of the tokens.
    /// @param _recipientAmount The amount for the recipient after fees.
    /// @param _feeRecipient The recipient of the fee (if any).
    /// @param _feeAmount The amount of the fee (0 if no fee).
    /// @param _campaignId The campaign ID.
    /// @param _encoderAuxData The auxiliary data for the encoder.
    /// @return actions The array of actions to execute.
    function _buildPayoutActions(
        Campaign storage _campaign,
        address _recipient,
        uint256 _recipientAmount,
        address _feeRecipient,
        uint256 _feeAmount,
        uint256 _campaignId,
        bytes calldata _encoderAuxData
    )
        internal
        view
        returns (Action[] memory actions)
    {
        bool hasEncoder = address(_campaign.actionEncoder) != address(0);
        bool hasFee = _feeAmount > 0;

        if (hasEncoder) {
            // Get base actions from encoder
            Action[] memory baseActions = _campaign.actionEncoder.buildActions(
                _campaign.token, _recipient, _recipientAmount, msg.sender, _campaignId, _encoderAuxData
            );

            if (hasFee) {
                // Append fee transfer to encoder actions
                actions = new Action[](baseActions.length + 1);
                for (uint256 i = 0; i < baseActions.length; i++) {
                    actions[i] = baseActions[i];
                }
                actions[baseActions.length] = Action({
                    to: address(_campaign.token),
                    value: 0,
                    data: abi.encodeCall(IERC20.transfer, (_feeRecipient, _feeAmount))
                });
            } else {
                actions = baseActions;
            }
        } else {
            // Direct transfer case
            actions = new Action[](hasFee ? 2 : 1);

            // Recipient transfer
            actions[0] = Action({
                to: address(_campaign.token),
                value: 0,
                data: abi.encodeCall(IERC20.transfer, (_recipient, _recipientAmount))
            });

            // Fee transfer if applicable
            if (hasFee) {
                actions[1] = Action({
                    to: address(_campaign.token),
                    value: 0,
                    data: abi.encodeCall(IERC20.transfer, (_feeRecipient, _feeAmount))
                });
            }
        }
    }

    /// @notice This empty reserved space is put in place to allow future versions to add new variables without shifting
    /// down storage in the inheritance chain (see [OpenZeppelin's guide about storage
    /// gaps](https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps)).
    uint256[44] private __gap;
}
