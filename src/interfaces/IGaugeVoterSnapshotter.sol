// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

/// @title IGaugeVoterSnapshotter
/// @notice Interface for the gauge voter snapshotter contract that captures historical voting data
interface IGaugeVoterSnapshotter {
    /// @notice Represents snapshot data for an epoch
    struct EpochSnapshot {
        uint256 totalVotingPowerCast;
        mapping(address => uint256) gaugeVotes;
        address[] snapshotGauges;
        bool snapshotted;
    }

    /// @notice Emitted when a snapshot is taken for an epoch
    /// @param epochId The epoch that was snapshotted
    /// @param totalVotingPowerCast The total voting power cast in the epoch
    /// @param gaugeCount The number of gauges included in the snapshot
    event SnapshotTaken(uint256 indexed epochId, uint256 totalVotingPowerCast, uint256 gaugeCount);

    /// @notice Thrown when trying to snapshot an epoch that has already been snapshotted
    /// @param epochId The epoch that was already snapshotted
    error EpochAlreadySnapshotted(uint256 epochId);

    /// @notice Thrown when trying to snapshot while voting is still active
    error VotingStillActive();

    /// @notice Thrown when gauge voter address is zero
    error InvalidGaugeVoter();

    /// @notice Takes a snapshot of gauge voting data for the current epoch
    /// @dev Can only be called after voting has ended for the epoch
    /// @dev Automatically snapshots all gauges from the gauge voter
    function takeSnapshot() external;

    /// @notice Returns the votes received by a gauge in a specific epoch
    /// @param epochId The epoch to query
    /// @param gauge The gauge address
    /// @return The number of votes received
    function getGaugeVotes(uint256 epochId, address gauge) external view returns (uint256);

    /// @notice Returns the total voting power cast in a specific epoch
    /// @param epochId The epoch to query
    /// @return The total voting power cast
    function getTotalVotingPowerCast(uint256 epochId) external view returns (uint256);

    /// @notice Checks if an epoch has been snapshotted
    /// @param epochId The epoch to check
    /// @return True if the epoch has been snapshotted
    function isEpochSnapshotted(uint256 epochId) external view returns (bool);

    /// @notice Returns all gauges that were snapshotted in an epoch
    /// @param epochId The epoch to query
    /// @return The list of gauge addresses
    function getSnapshotGauges(uint256 epochId) external view returns (address[] memory);

    /// @notice Returns the current epoch from the gauge voter
    /// @return The current epoch number
    function getCurrentEpoch() external view returns (uint256);
}
