// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.29 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { AragonTest } from "./helpers/AragonTest.sol";
import { GaugeVoterSnapshotter } from "../src/GaugeVoterSnapshotter.sol";
import { IGaugeVoterSnapshotter } from "../src/interfaces/IGaugeVoterSnapshotter.sol";
import { MockAddressGaugeVoter } from "./mocks/MockAddressGaugeVoter.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { PermissionLib } from "@aragon/commons/permission/PermissionLib.sol";

/// @title GaugeVoterSnapshotterTest
/// @notice Test suite for GaugeVoterSnapshotter contract
contract GaugeVoterSnapshotterTest is AragonTest {
    // =========================================================================
    // State Variables
    // =========================================================================

    GaugeVoterSnapshotter public snapshotter;
    MockAddressGaugeVoter public mockGaugeVoter;

    bytes32 public constant SNAPSHOTTER_ROLE = keccak256("SNAPSHOTTER_ROLE");
    
    address gauge1 = address(0x1111);
    address gauge2 = address(0x2222);
    address gauge3 = address(0x3333);

    // =========================================================================
    // Events
    // =========================================================================

    event SnapshotTaken(uint256 indexed epochId, uint256 totalVotingPowerCast, uint256 gaugeCount);

    // =========================================================================
    // Setup
    // =========================================================================

    function setUp() public {
        // Deploy mock gauge voter
        mockGaugeVoter = new MockAddressGaugeVoter();

        // Deploy snapshotter
        snapshotter = new GaugeVoterSnapshotter();
        snapshotter.initialize(createdDAO, mockGaugeVoter);

        // Grant snapshotter role to test address
        vm.startPrank(address(createdDAO));
        createdDAO.grant(address(snapshotter), address(this), SNAPSHOTTER_ROLE);
        vm.stopPrank();
    }

    // =========================================================================
    // Initialization Tests
    // =========================================================================

    function testInitialization() public {
        assertEq(address(snapshotter.gaugeVoter()), address(mockGaugeVoter), "Gauge voter not set correctly");
        assertEq(address(snapshotter.dao()), address(createdDAO), "DAO not set correctly");
    }

    function testCannotInitializeWithZeroGaugeVoter() public {
        GaugeVoterSnapshotter newSnapshotter = new GaugeVoterSnapshotter();
        
        vm.expectRevert(IGaugeVoterSnapshotter.InvalidGaugeVoter.selector);
        newSnapshotter.initialize(createdDAO, MockAddressGaugeVoter(address(0)));
    }

    // =========================================================================
    // Snapshot Tests
    // =========================================================================

    function testTakeSnapshot() public {
        // Setup gauge votes
        mockGaugeVoter.setGaugeVotes(gauge1, 100);
        mockGaugeVoter.setGaugeVotes(gauge2, 200);
        mockGaugeVoter.setGaugeVotes(gauge3, 300);
        mockGaugeVoter.setTotalVotingPowerCast(600);
        mockGaugeVoter.setEpoch(1);
        mockGaugeVoter.setVotingActive(false);

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit SnapshotTaken(1, 600, 3);

        // Take snapshot - no parameters needed, it uses current epoch and all gauges
        snapshotter.takeSnapshot();

        // Verify snapshot data
        assertEq(snapshotter.getGaugeVotes(1, gauge1), 100, "Gauge1 votes incorrect");
        assertEq(snapshotter.getGaugeVotes(1, gauge2), 200, "Gauge2 votes incorrect");
        assertEq(snapshotter.getGaugeVotes(1, gauge3), 300, "Gauge3 votes incorrect");
        assertEq(snapshotter.getTotalVotingPowerCast(1), 600, "Total voting power incorrect");
        assertTrue(snapshotter.isEpochSnapshotted(1), "Epoch not marked as snapshotted");

        // Verify snapshot gauges
        address[] memory snapshotGauges = snapshotter.getSnapshotGauges(1);
        assertEq(snapshotGauges.length, 3, "Snapshot gauges length incorrect");
        assertEq(snapshotGauges[0], gauge1, "Gauge1 not in snapshot");
        assertEq(snapshotGauges[1], gauge2, "Gauge2 not in snapshot");
        assertEq(snapshotGauges[2], gauge3, "Gauge3 not in snapshot");
    }

    function testCannotSnapshotSameEpochTwice() public {
        mockGaugeVoter.setEpoch(1);
        mockGaugeVoter.setVotingActive(false);
        mockGaugeVoter.setGaugeVotes(gauge1, 100);

        // First snapshot succeeds
        snapshotter.takeSnapshot();

        // Second snapshot fails
        vm.expectRevert(abi.encodeWithSelector(IGaugeVoterSnapshotter.EpochAlreadySnapshotted.selector, 1));
        snapshotter.takeSnapshot();
    }

    function testCannotSnapshotWhileVotingActive() public {
        mockGaugeVoter.setEpoch(1);
        mockGaugeVoter.setVotingActive(true);

        vm.expectRevert(IGaugeVoterSnapshotter.VotingStillActive.selector);
        snapshotter.takeSnapshot();
    }

    // Note: testCannotSnapshotFutureEpoch is no longer needed since takeSnapshot
    // automatically uses the current epoch from the gauge voter

    function testSnapshotWithNoGauges() public {
        mockGaugeVoter.setEpoch(1);
        mockGaugeVoter.setVotingActive(false);
        mockGaugeVoter.setTotalVotingPowerCast(1000);
        // Don't add any gauges to mockGaugeVoter

        // Should succeed with no gauges returned from getAllGauges
        snapshotter.takeSnapshot();

        assertEq(snapshotter.getTotalVotingPowerCast(1), 1000, "Total voting power should be recorded");
        assertTrue(snapshotter.isEpochSnapshotted(1), "Epoch should be marked as snapshotted");
        assertEq(snapshotter.getSnapshotGauges(1).length, 0, "Should have no gauges");
    }

    // =========================================================================
    // Access Control Tests
    // =========================================================================

    function testOnlySnapshotterRoleCanSnapshot() public {
        mockGaugeVoter.setEpoch(1);
        mockGaugeVoter.setVotingActive(false);

        // Revoke role from test address
        vm.prank(address(createdDAO));
        createdDAO.revoke(address(snapshotter), address(this), SNAPSHOTTER_ROLE);

        // Should fail without role
        vm.expectRevert();
        snapshotter.takeSnapshot();
    }

    // =========================================================================
    // Data Retrieval Tests
    // =========================================================================

    function testGetGaugeVotesForUnsnapshotted() public {
        // Should return 0 for unsnapshotted epoch
        assertEq(snapshotter.getGaugeVotes(99, gauge1), 0, "Should return 0 for unsnapshotted epoch");
    }

    function testGetTotalVotingPowerForUnsnapshotted() public {
        // Should return 0 for unsnapshotted epoch
        assertEq(snapshotter.getTotalVotingPowerCast(99), 0, "Should return 0 for unsnapshotted epoch");
    }

    function testIsEpochSnapshottedForUnsnapshotted() public {
        // Should return false for unsnapshotted epoch
        assertFalse(snapshotter.isEpochSnapshotted(99), "Should return false for unsnapshotted epoch");
    }

    function testGetSnapshotGaugesForUnsnapshotted() public {
        // Should return empty array for unsnapshotted epoch
        address[] memory gauges = snapshotter.getSnapshotGauges(99);
        assertEq(gauges.length, 0, "Should return empty array for unsnapshotted epoch");
    }

    // =========================================================================
    // Complex Scenario Tests
    // =========================================================================

    function testMultipleEpochSnapshots() public {
        mockGaugeVoter.setVotingActive(false);

        // Epoch 1
        mockGaugeVoter.setEpoch(1);
        mockGaugeVoter.setGaugeVotes(gauge1, 100);
        mockGaugeVoter.setGaugeVotes(gauge2, 200);
        mockGaugeVoter.setTotalVotingPowerCast(300);
        
        snapshotter.takeSnapshot();

        // Epoch 2 - different votes
        mockGaugeVoter.setEpoch(2);
        // Update votes - note that setGaugeVotes will add gauges automatically
        mockGaugeVoter.setGaugeVotes(gauge1, 150);
        mockGaugeVoter.setGaugeVotes(gauge2, 250);
        mockGaugeVoter.setGaugeVotes(gauge3, 100);
        mockGaugeVoter.setTotalVotingPowerCast(500);
        
        snapshotter.takeSnapshot();

        // Verify epoch 1 data unchanged
        assertEq(snapshotter.getGaugeVotes(1, gauge1), 100, "Epoch 1 gauge1 votes changed");
        assertEq(snapshotter.getGaugeVotes(1, gauge2), 200, "Epoch 1 gauge2 votes changed");
        assertEq(snapshotter.getGaugeVotes(1, gauge3), 0, "Epoch 1 gauge3 should be 0");
        assertEq(snapshotter.getTotalVotingPowerCast(1), 300, "Epoch 1 total changed");

        // Verify epoch 2 data
        assertEq(snapshotter.getGaugeVotes(2, gauge1), 150, "Epoch 2 gauge1 votes incorrect");
        assertEq(snapshotter.getGaugeVotes(2, gauge2), 250, "Epoch 2 gauge2 votes incorrect");
        assertEq(snapshotter.getGaugeVotes(2, gauge3), 100, "Epoch 2 gauge3 votes incorrect");
        assertEq(snapshotter.getTotalVotingPowerCast(2), 500, "Epoch 2 total incorrect");
    }
}