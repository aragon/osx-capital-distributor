// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.29 <0.9.0;

import { IAddressGaugeVoter } from "../../src/interfaces/helpers/IAddressGaugeVoter.sol";
import { IGaugeManager } from "../../src/interfaces/helpers/IGaugeVoter.sol";

/// @title MockAddressGaugeVoter
/// @notice Mock implementation of IAddressGaugeVoter for testing purposes
/// @dev Provides configurable state for testing different voting scenarios
contract MockAddressGaugeVoter is IAddressGaugeVoter {
    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice Current epoch ID
    uint256 private _epochId;

    /// @notice Whether voting is currently active
    bool private _votingActive;

    /// @notice Total voting power cast in current epoch
    uint256 private _totalVotingPowerCast;

    /// @notice Mapping of user addresses to their used voting power
    mapping(address => uint256) private _userVotingPower;

    /// @notice Mapping of user addresses to their voting status
    mapping(address => bool) private _userIsVoting;

    /// @notice Mapping of gauge addresses to their active status
    mapping(address => bool) private _gaugeIsActive;

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor() {
        _epochId = 1;
        _votingActive = false;
        _totalVotingPowerCast = 0;
    }

    // =========================================================================
    // Test Configuration Functions
    // =========================================================================

    /// @notice Set the current epoch ID for testing
    /// @param epochId_ New epoch ID
    function setEpoch(uint256 epochId_) external {
        _epochId = epochId_;
    }

    /// @notice Set the voting active status for testing
    /// @param active_ Whether voting should be active
    function setVotingActive(bool active_) external {
        _votingActive = active_;
    }

    /// @notice Set a user's voting power for testing
    /// @param user_ User address
    /// @param power_ Voting power amount
    function setUserVotingPower(address user_, uint256 power_) external {
        _userVotingPower[user_] = power_;
    }

    /// @notice Set the total voting power cast for testing
    /// @param total_ Total voting power amount
    function setTotalVotingPowerCast(uint256 total_) external {
        _totalVotingPowerCast = total_;
    }

    /// @notice Set a user's voting status for testing
    /// @param user_ User address
    /// @param voting_ Whether user is currently voting
    function setUserIsVoting(address user_, bool voting_) external {
        _userIsVoting[user_] = voting_;
    }

    /// @notice Set a gauge's active status for testing
    /// @param gauge_ Gauge address
    /// @param active_ Whether gauge is active
    function setGaugeActive(address gauge_, bool active_) external {
        _gaugeIsActive[gauge_] = active_;
    }

    // =========================================================================
    // IAddressGaugeVoter Implementation
    // =========================================================================

    /// @inheritdoc IAddressGaugeVoter
    function vote(GaugeVote[] memory) external override {
        // Mock implementation - just marks user as voting
        _userIsVoting[msg.sender] = true;
    }

    /// @inheritdoc IAddressGaugeVoter
    function reset() external override {
        // Mock implementation - marks user as not voting
        _userIsVoting[msg.sender] = false;
        _userVotingPower[msg.sender] = 0;
    }

    /// @inheritdoc IAddressGaugeVoter
    function isVoting(address _address) external view override returns (bool) {
        return _userIsVoting[_address];
    }

    /// @inheritdoc IAddressGaugeVoter
    function updateVotingPower(address, address) external override {
        // Mock implementation - no-op for testing
    }

    /// @inheritdoc IAddressGaugeVoter
    function usedVotingPower(address _address) external view override returns (uint256) {
        return _userVotingPower[_address];
    }

    /// @inheritdoc IAddressGaugeVoter
    function totalVotingPowerCast() external view override returns (uint256) {
        return _totalVotingPowerCast;
    }

    /// @inheritdoc IAddressGaugeVoter
    function epochId() external view override returns (uint256) {
        return _epochId;
    }

    /// @inheritdoc IAddressGaugeVoter
    function votingActive() external view override returns (bool) {
        return _votingActive;
    }

    /// @inheritdoc IAddressGaugeVoter
    function epochStart() external view override returns (uint256) {
        // Mock implementation - returns fixed timestamp
        return block.timestamp - 1 days;
    }

    /// @inheritdoc IAddressGaugeVoter
    function epochVoteStart() external view override returns (uint256) {
        // Mock implementation - returns fixed timestamp
        return block.timestamp - 12 hours;
    }

    /// @inheritdoc IAddressGaugeVoter
    function epochVoteEnd() external view override returns (uint256) {
        // Mock implementation - returns fixed timestamp based on voting status
        return _votingActive ? block.timestamp + 12 hours : block.timestamp - 1 hours;
    }

    // =========================================================================
    // IGaugeManager Implementation
    // =========================================================================

    /// @inheritdoc IGaugeManager
    function isActive(address gauge) external view override returns (bool) {
        return _gaugeIsActive[gauge];
    }

    /// @inheritdoc IGaugeManager
    function createGauge(address _gauge, string calldata _metadata) external override returns (address) {
        _gaugeIsActive[_gauge] = true;
        emit GaugeCreated(_gauge, msg.sender, _metadata);
        return _gauge;
    }

    /// @inheritdoc IGaugeManager
    function deactivateGauge(address _gauge) external override {
        if (!_gaugeIsActive[_gauge]) revert GaugeActivationUnchanged();
        _gaugeIsActive[_gauge] = false;
        emit GaugeDeactivated(_gauge);
    }

    /// @inheritdoc IGaugeManager
    function activateGauge(address _gauge) external override {
        if (_gaugeIsActive[_gauge]) revert GaugeActivationUnchanged();
        _gaugeIsActive[_gauge] = true;
        emit GaugeActivated(_gauge);
    }

    /// @inheritdoc IGaugeManager
    function updateGaugeMetadata(address _gauge, string calldata _metadata) external override {
        emit GaugeMetadataUpdated(_gauge, _metadata);
    }
}
