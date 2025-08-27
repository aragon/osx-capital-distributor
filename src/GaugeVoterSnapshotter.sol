// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { DaoAuthorizableUpgradeable } from "@aragon/commons/permission/auth/DaoAuthorizableUpgradeable.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { IGaugeVoterSnapshotter } from "./interfaces/IGaugeVoterSnapshotter.sol";
import { IAddressGaugeVoter } from "./interfaces/helpers/IAddressGaugeVoter.sol";

/// @title GaugeVoterSnapshotter
/// @notice Contract that captures and stores historical gauge voting data
/// @dev Stores snapshots of gauge votes and total voting power for each epoch
contract GaugeVoterSnapshotter is IGaugeVoterSnapshotter, DaoAuthorizableUpgradeable {
    /// @notice The ID of the permission required to take snapshots
    bytes32 public constant SNAPSHOTTER_ROLE = keccak256("SNAPSHOTTER_ROLE");

    /// @notice Storage of epoch snapshots
    mapping(uint256 => EpochSnapshot) public epochSnapshots;

    /// @notice Reference to the gauge voter contract
    IAddressGaugeVoter public gaugeVoter;

    /// @notice Initializes the snapshotter with DAO and gauge voter
    /// @param _dao The DAO that controls this snapshotter
    /// @param _gaugeVoter The gauge voter contract to snapshot data from
    function initialize(IDAO _dao, IAddressGaugeVoter _gaugeVoter) external initializer {
        if (address(_gaugeVoter) == address(0)) revert InvalidGaugeVoter();

        __DaoAuthorizableUpgradeable_init(_dao);
        gaugeVoter = _gaugeVoter;
    }

    /// @inheritdoc IGaugeVoterSnapshotter
    function takeSnapshot() external auth(SNAPSHOTTER_ROLE) {
        uint256 epochId = gaugeVoter.epochId();

        // Check if already snapshotted
        if (epochSnapshots[epochId].snapshotted) {
            revert EpochAlreadySnapshotted(epochId);
        }

        // Check voting is not active (must be in distribution period)
        if (gaugeVoter.votingActive()) {
            revert VotingStillActive();
        }

        // Store the snapshot
        EpochSnapshot storage snapshot = epochSnapshots[epochId];
        snapshot.totalVotingPowerCast = gaugeVoter.totalVotingPowerCast();
        snapshot.snapshotted = true;

        // Store gauge votes
        address[] memory gauges = gaugeVoter.getAllGauges();
        for (uint256 i = 0; i < gauges.length;) {
            address gauge = gauges[i];
            uint256 votes = gaugeVoter.gaugeVotes(gauge);

            snapshot.gaugeVotes[gauge] = votes;
            snapshot.snapshotGauges.push(gauge);

            unchecked {
                ++i;
            }
        }

        emit SnapshotTaken(epochId, snapshot.totalVotingPowerCast, gauges.length);
    }

    /// @inheritdoc IGaugeVoterSnapshotter
    function getGaugeVotes(uint256 epochId, address gauge) external view returns (uint256) {
        return epochSnapshots[epochId].gaugeVotes[gauge];
    }

    /// @inheritdoc IGaugeVoterSnapshotter
    function getTotalVotingPowerCast(uint256 epochId) external view returns (uint256) {
        return epochSnapshots[epochId].totalVotingPowerCast;
    }

    /// @inheritdoc IGaugeVoterSnapshotter
    function isEpochSnapshotted(uint256 epochId) external view returns (bool) {
        return epochSnapshots[epochId].snapshotted;
    }

    /// @inheritdoc IGaugeVoterSnapshotter
    function getSnapshotGauges(uint256 epochId) external view returns (address[] memory) {
        return epochSnapshots[epochId].snapshotGauges;
    }

    /// @inheritdoc IGaugeVoterSnapshotter
    function getCurrentEpoch() external view returns (uint256) {
        return gaugeVoter.epochId();
    }

    /// @dev Reserved storage space to allow for future upgrades without storage collision.
    uint256[48] private __gap;
}
