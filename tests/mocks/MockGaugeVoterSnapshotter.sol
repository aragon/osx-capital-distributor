// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.29 <0.9.0;

import { IGaugeVoterSnapshotter } from "../../src/interfaces/helpers/IGaugeVoterSnapshotter.sol";
import { IAddressGaugeVoter } from "../../src/interfaces/helpers/IAddressGaugeVoter.sol";

/// @title MockGaugeVoterSnapshotter
/// @notice Mock implementation of IGaugeVoterSnapshotter for testing
contract MockGaugeVoterSnapshotter is IGaugeVoterSnapshotter {
    mapping(uint256 => EpochSnapshot) public epochSnapshots;

    /// @notice Mock current epoch for testing
    uint256 public currentEpoch = 1;

    /// @notice Mock gauge voter address for testing
    IAddressGaugeVoter public mockGaugeVoter;

    /// @notice Directly set snapshot data for testing
    function setSnapshot(
        uint256 epochId,
        uint256 totalVotingPowerCast,
        address[] calldata gauges,
        uint256[] calldata votes
    )
        external
    {
        require(gauges.length == votes.length, "Length mismatch");

        EpochSnapshot storage snapshot = epochSnapshots[epochId];
        snapshot.totalVotingPowerCast = totalVotingPowerCast;
        snapshot.snapshotted = true;

        // Clear existing data
        delete snapshot.snapshotGauges;

        // Set new data
        for (uint256 i = 0; i < gauges.length; i++) {
            snapshot.gaugeVotes[gauges[i]] = votes[i];
            snapshot.snapshotGauges.push(gauges[i]);
        }
    }

    /// @inheritdoc IGaugeVoterSnapshotter
    function takeSnapshot() external override {
        // Mock implementation - automatically take snapshot for current epoch
        uint256 epochId = currentEpoch;

        if (epochSnapshots[epochId].snapshotted) {
            revert EpochAlreadySnapshotted(epochId);
        }

        EpochSnapshot storage snapshot = epochSnapshots[epochId];
        snapshot.snapshotted = true;

        // In the mock, the snapshot gauges should be set up via setSnapshot
        uint256 gaugeCount = snapshot.snapshotGauges.length;

        emit SnapshotTaken(epochId, snapshot.totalVotingPowerCast, gaugeCount);
    }

    /// @inheritdoc IGaugeVoterSnapshotter
    function getGaugeVotes(uint256 epochId, address gauge) external view override returns (uint256) {
        return epochSnapshots[epochId].gaugeVotes[gauge];
    }

    /// @inheritdoc IGaugeVoterSnapshotter
    function getTotalVotingPowerCast(uint256 epochId) external view override returns (uint256) {
        return epochSnapshots[epochId].totalVotingPowerCast;
    }

    /// @inheritdoc IGaugeVoterSnapshotter
    function isEpochSnapshotted(uint256 epochId) external view override returns (bool) {
        return epochSnapshots[epochId].snapshotted;
    }

    /// @inheritdoc IGaugeVoterSnapshotter
    function getSnapshotGauges(uint256 epochId) external view override returns (address[] memory) {
        return epochSnapshots[epochId].snapshotGauges;
    }

    /// @notice Helper to set individual gauge votes for testing
    function setGaugeVotes(uint256 epochId, address gauge, uint256 votes) external {
        epochSnapshots[epochId].gaugeVotes[gauge] = votes;
    }

    /// @notice Helper to set total voting power for testing
    function setTotalVotingPowerCast(uint256 epochId, uint256 totalPower) external {
        epochSnapshots[epochId].totalVotingPowerCast = totalPower;
    }

    /// @notice Helper to mark epoch as snapshotted for testing
    function setEpochSnapshotted(uint256 epochId, bool snapshotted) external {
        epochSnapshots[epochId].snapshotted = snapshotted;
    }

    /// @inheritdoc IGaugeVoterSnapshotter
    function getCurrentEpoch() external view override returns (uint256) {
        return currentEpoch;
    }

    /// @notice Helper to set current epoch for testing
    function setCurrentEpoch(uint256 _currentEpoch) external {
        currentEpoch = _currentEpoch;
    }

    /// @inheritdoc IGaugeVoterSnapshotter
    function gaugeVoter() external view override returns (IAddressGaugeVoter) {
        return mockGaugeVoter;
    }

    /// @notice Helper to set gauge voter for testing
    function setGaugeVoter(address _gaugeVoter) external {
        mockGaugeVoter = IAddressGaugeVoter(_gaugeVoter);
    }
}
