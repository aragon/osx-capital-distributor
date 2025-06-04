// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {IPayoutActionEncoder} from "../interfaces/IPayoutActionEncoder.sol";
import {Action} from "@aragon/commons/executors/IExecutor.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {DaoAuthorizableUpgradeable} from "@aragon/commons/permission/auth/DaoAuthorizableUpgradeable.sol";

// Sablier imports
import {ud60x18} from "@prb/math/src/UD60x18.sol";

/// @title ISablierLockup
/// @notice Interface for Sablier V2 Lockup contracts
interface ISablierLockup {
    function createWithDurationsLL(
        address lockup,
        address token,
        CreateWithDurationsLL[] calldata params
    ) external returns (uint256 streamId);

    function nextStreamId() external view returns (uint256);

    function withdrawMax(uint256 streamId, address recipient) external returns (uint256);
}

/// @title Sablier Data Types
/// @notice Structs used by Sablier V2 Lockup contracts
struct Broker {
    address account;
    uint256 fee; // Using uint256 instead of UD60x18 for simplicity in encoding
}

struct CreateWithDurations {
    address sender;
    address recipient;
    uint128 totalAmount;
    IERC20 asset;
    bool cancelable;
    bool transferable;
    Broker broker;
}

struct Durations {
    uint40 cliff;
    uint40 total;
}

struct UnlockAmounts {
    uint128 start;
    uint128 cliff;
}

struct CreateWithDurationsLL {
    address sender;
    address recipient;
    uint128 totalAmount;
    bool cancelable;
    bool transferable;
    Durations durations;
    UnlockAmounts unlockAmounts;
    string shape;
    Broker broker;
}

/// @title SablierLinearPayoutActionEncoder
/// @notice An IPayoutActionEncoder that creates Sablier linear streams for payouts
/// @dev This contract creates actions to approve tokens and create linear streams on Sablier V2
contract SablierLinearPayoutActionEncoder is IPayoutActionEncoder, DaoAuthorizableUpgradeable {
    address constant SABLIER_V2_LOCKUP = 0x7C01AA3783577E15fD7e272443D44B92d5b21056;
    /// @notice Struct containing stream configuration for a campaign
    struct StreamConfig {
        address sablierContract;
        uint40 streamDuration;
        uint40 cliffDuration;
        uint128 unlockAmountAtStart;
        uint128 unlockAmountAtCliff;
        bool cancelable;
        bool transferable;
        address brokerAccount;
        uint256 brokerFee; // Fee as a percentage in basis points (e.g., 100 = 1%)
    }

    /// @notice Mapping from campaignId to stream configuration
    mapping(uint256 => StreamConfig) public campaignStreamConfigs;

    /// @notice Emitted when a stream configuration is set for a campaign
    event CampaignStreamConfigSet(
        uint256 indexed campaignId,
        address indexed sablierContract,
        uint40 streamDuration,
        uint40 cliffDuration,
        address indexed setter
    );

    /// @notice Thrown if the amount to payout is zero
    error AmountCannotBeZero();
    /// @notice Thrown if no stream config is set for the given campaignId
    error StreamConfigNotSetForCampaign(uint256 campaignId);
    /// @notice Thrown if the Sablier contract address is zero
    error ZeroAddressNotAllowed();
    /// @notice Thrown if the stream duration is zero
    error InvalidStreamDuration();

    /**
     * @notice Constructor to disable initializers in implementation
     */
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the encoder with the given DAO
    /// @param _dao The DAO that will control this encoder
    function initialize(IDAO _dao, bytes calldata) public virtual initializer {
        __DaoAuthorizableUpgradeable_init(_dao);
    }

    /// @inheritdoc IPayoutActionEncoder
    function setupCampaign(uint256 _campaignId, bytes calldata _auxData) external override {
        StreamConfig memory config = abi.decode(_auxData, (StreamConfig));

        if (config.sablierContract == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        if (config.streamDuration == 0) {
            revert InvalidStreamDuration();
        }

        campaignStreamConfigs[_campaignId] = config;

        emit CampaignStreamConfigSet(
            _campaignId,
            config.sablierContract,
            config.streamDuration,
            config.cliffDuration,
            msg.sender
        );
    }

    /// @inheritdoc IPayoutActionEncoder
    /// @dev Creates two actions:
    ///      1. Approve the Sablier contract to spend the tokens
    ///      2. Create a linear stream with the specified parameters
    function buildActions(
        IERC20 _token,
        address _recipient,
        uint256 _amount,
        address, // _caller - not used in this implementation
        uint256 _campaignId
    ) external view override returns (Action[] memory actions) {
        if (_amount == 0) {
            revert AmountCannotBeZero();
        }

        StreamConfig memory config = campaignStreamConfigs[_campaignId];
        if (config.sablierContract == address(0)) {
            revert StreamConfigNotSetForCampaign(_campaignId);
        }

        actions = new Action[](2);

        // Action 1: Approve the Sablier contract to spend the tokens
        actions[0] = Action({
            to: address(_token),
            value: 0,
            data: abi.encodeCall(IERC20.approve, (config.sablierContract, _amount))
        });

        // Action 2: Create the linear stream
        actions[1] = Action({
            to: config.sablierContract,
            value: 0,
            data: _buildCreateStreamCalldata(_token, _recipient, _amount, config)
        });

        return actions;
    }

    /// @notice Builds the calldata for creating a linear stream
    /// @param _token The token to be streamed
    /// @param _recipient The recipient of the stream
    /// @param _amount The total amount to be streamed
    /// @param _config The stream configuration for this campaign
    /// @return calldata The encoded function call for createWithDurationsLL
    function _buildCreateStreamCalldata(
        IERC20 _token,
        address _recipient,
        uint256 _amount,
        StreamConfig memory _config
    ) internal view returns (bytes memory) {
        // Create the durations struct
        Durations memory durations = Durations({cliff: _config.cliffDuration, total: _config.streamDuration});

        // Create the unlock amounts struct
        UnlockAmounts memory unlockAmounts = UnlockAmounts({
            start: _config.unlockAmountAtStart,
            cliff: _config.unlockAmountAtCliff
        });
        // Create the parameters struct
        CreateWithDurationsLL[] memory params = new CreateWithDurationsLL[](1);
        params[0] = CreateWithDurationsLL({
            sender: address(dao()), // The DAO is the sender
            recipient: _recipient,
            totalAmount: uint128(_amount),
            cancelable: _config.cancelable,
            transferable: _config.transferable,
            durations: durations,
            unlockAmounts: unlockAmounts,
            shape: "linear",
            broker: Broker({account: _config.brokerAccount, fee: _config.brokerFee})
        });

        return abi.encodeCall(ISablierLockup.createWithDurationsLL, (SABLIER_V2_LOCKUP, address(_token), params));
    }

    /// @notice Gets the stream configuration for a campaign
    /// @param _campaignId The campaign ID to get the configuration for
    /// @return config The stream configuration
    function getCampaignStreamConfig(uint256 _campaignId) external view returns (StreamConfig memory config) {
        return campaignStreamConfigs[_campaignId];
    }

    /// @notice Encodes the stream configuration for use in setupCampaign
    /// @param _sablierContract The address of the Sablier contract
    /// @param _streamDuration Total duration of the stream in seconds
    /// @param _cliffDuration Cliff duration in seconds (0 for no cliff)
    /// @param _unlockAmountAtStart Amount to unlock immediately at start
    /// @param _unlockAmountAtCliff Amount to unlock at cliff
    /// @param _cancelable Whether the stream can be canceled
    /// @param _transferable Whether the stream can be transferred
    /// @param _brokerAccount Address of the broker (use address(0) for no broker)
    /// @param _brokerFee Broker fee in basis points (e.g., 100 = 1%)
    /// @return encodedConfig The encoded configuration
    function encodeStreamConfig(
        address _sablierContract,
        uint40 _streamDuration,
        uint40 _cliffDuration,
        uint128 _unlockAmountAtStart,
        uint128 _unlockAmountAtCliff,
        bool _cancelable,
        bool _transferable,
        address _brokerAccount,
        uint256 _brokerFee
    ) external pure returns (bytes memory encodedConfig) {
        StreamConfig memory config = StreamConfig({
            sablierContract: _sablierContract,
            streamDuration: _streamDuration,
            cliffDuration: _cliffDuration,
            unlockAmountAtStart: _unlockAmountAtStart,
            unlockAmountAtCliff: _unlockAmountAtCliff,
            cancelable: _cancelable,
            transferable: _transferable,
            brokerAccount: _brokerAccount,
            brokerFee: _brokerFee
        });

        return abi.encode(config);
    }
}
