// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.29 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { AragonTest } from "../helpers/AragonTest.sol";
import { GaugeDistributionStrategy } from "../../src/allocatorStrategies/GaugeDistributionStrategy.sol";
import { MockGaugeVoterSnapshotter } from "../mocks/MockGaugeVoterSnapshotter.sol";
import { MockAddressGaugeVoter } from "../mocks/MockAddressGaugeVoter.sol";
import { MintableERC20 } from "../mocks/MintableERC20.sol";
import { IAllocatorStrategy } from "../../src/interfaces/IAllocatorStrategy.sol";
import { CapitalDistributorPlugin } from "../../src/CapitalDistributorPlugin.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title GaugeDistributionStrategyTest
/// @notice Test suite for GaugeDistributionStrategy contract
contract GaugeDistributionStrategyTest is AragonTest {
    // =========================================================================
    // State Variables
    // =========================================================================

    CapitalDistributorPlugin capitalDistributorPlugin;
    GaugeDistributionStrategy public strategy;
    MockGaugeVoterSnapshotter public mockSnapshotter;
    MockAddressGaugeVoter public mockGaugeVoter;
    MintableERC20 public token;

    bytes32 public constant STRATEGY_TYPE_ID = keccak256("GaugeDistributionStrategy");
    uint256 public constant DEFAULT_CAMPAIGN_ID = 1;
    uint256 public constant DEFAULT_START_EPOCH = 1;
    uint256 public constant DEFAULT_END_EPOCH = 0; // Continuous

    address gauge1 = address(0x1111);
    address gauge2 = address(0x2222);
    address gauge3 = address(0x3333);

    // =========================================================================
    // Events
    // =========================================================================

    event AllocationCampaignCreated(address indexed plugin, uint256 indexed campaignId);

    // =========================================================================
    // Setup
    // =========================================================================

    function setUp() public virtual {
        // Initialize plugin from AragonTest
        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddress[0]);

        // Deploy mock gauge voter
        mockGaugeVoter = new MockAddressGaugeVoter();
        
        // Deploy mock snapshotter and set gauge voter
        mockSnapshotter = new MockGaugeVoterSnapshotter();
        mockSnapshotter.setGaugeVoter(address(mockGaugeVoter));

        // Deploy test token
        token = new MintableERC20();

        // Deploy strategy implementation and register with factory
        strategy = new GaugeDistributionStrategy();
        vm.startPrank(address(createdDAO));
        allocatorStrategyFactory.registerStrategyType(
            STRATEGY_TYPE_ID, address(strategy), "GaugeDistributionStrategy", address(0), 0
        );
        vm.stopPrank();

        // Mint tokens to DAO treasury for distribution
        token.mint(address(createdDAO), 100_000 ether);
    }

    // =========================================================================
    // Helper Functions
    // =========================================================================

    /// @notice Create a test campaign with default parameters
    function createTestCampaign() internal returns (uint256 campaignId) {
        return createTestCampaign(DEFAULT_START_EPOCH, DEFAULT_END_EPOCH);
    }

    /// @notice Create a test campaign with specified parameters
    function createTestCampaign(uint256 _startEpoch, uint256 _endEpoch) internal returns (uint256 campaignId) {
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = abi.encode(address(mockSnapshotter));
        bytes memory allocationCampaignAuxData = abi.encode(_startEpoch, _endEpoch);

        campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            STRATEGY_TYPE_ID,
            allocatorDeploymentParams,
            allocationCampaignAuxData,
            IERC20(token),
            bytes32(0),
            metadata,
            true, // Allow multiple claims
            0, // No start time restriction
            0 // No end time restriction
        );

        vm.stopPrank();
        return campaignId;
    }

    /// @notice Get the deployed strategy instance from a campaign
    function getDeployedStrategy(uint256 _campaignId)
        internal
        view
        returns (GaugeDistributionStrategy deployedStrategy)
    {
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(_campaignId);
        return GaugeDistributionStrategy(address(campaign.allocationStrategy));
    }

    /// @notice Setup snapshot data for testing
    function setupSnapshot(uint256 epochId, uint256 totalPower) internal {
        mockSnapshotter.setEpochSnapshotted(epochId, true);
        mockSnapshotter.setTotalVotingPowerCast(epochId, totalPower);
    }

    /// @notice Setup gauge votes for testing
    function setupGaugeVotes(uint256 epochId, address gauge, uint256 votes) internal {
        mockSnapshotter.setGaugeVotes(epochId, gauge, votes);
        // Also set in gauge voter for current epoch live data
        if (epochId == mockSnapshotter.getCurrentEpoch()) {
            mockGaugeVoter.setGaugeVotes(gauge, votes);
        }
    }

    // =========================================================================
    // Initialization Tests
    // =========================================================================

    function testInitialization() public {
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = abi.encode(address(mockSnapshotter));
        bytes memory allocationCampaignAuxData = abi.encode(1, 10); // Epoch 1 to 10

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            STRATEGY_TYPE_ID,
            allocatorDeploymentParams,
            allocationCampaignAuxData,
            IERC20(token),
            bytes32(0),
            metadata,
            true,
            0,
            0
        );

        vm.stopPrank();

        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);
        assertEq(address(deployedStrategy.snapshotter()), address(mockSnapshotter), "Snapshotter not set correctly");
    }

    function testGetEncodingTypes() public {
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        assertEq(deployedStrategy.getInitializationEncodingTypes(), "address", "Init encoding types incorrect");
        assertEq(deployedStrategy.getCreationEncodingTypes(), "uint256,uint256", "Creation encoding types incorrect");
        assertEq(deployedStrategy.getClaimEncodingTypes(), "", "Claim encoding types incorrect");
    }

    // =========================================================================
    // Campaign Creation Tests
    // =========================================================================

    function testCampaignCreation() public {
        vm.expectEmit(true, true, false, false);
        emit AllocationCampaignCreated(address(capitalDistributorPlugin), 0);

        uint256 campaignId = createTestCampaign(5, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        (uint256 startEpoch, uint256 endEpoch) = deployedStrategy.campaigns(campaignId);
        assertEq(startEpoch, 5, "Start epoch not set correctly");
        assertEq(endEpoch, 10, "End epoch not set correctly");
    }

    function testContinuousCampaignCreation() public {
        uint256 campaignId = createTestCampaign(1, 0); // 0 means continuous
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        (uint256 startEpoch, uint256 endEpoch) = deployedStrategy.campaigns(campaignId);
        assertEq(startEpoch, 1, "Start epoch not set correctly");
        assertEq(endEpoch, 0, "End epoch should be 0 for continuous");
    }

    function testCannotCreateCampaignWithInvalidEpochs() public {
        // Start epoch 0 is invalid
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = abi.encode(address(mockSnapshotter));
        bytes memory invalidAuxData = abi.encode(0, 10);

        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            metadata,
            STRATEGY_TYPE_ID,
            allocatorDeploymentParams,
            invalidAuxData,
            IERC20(token),
            bytes32(0),
            metadata,
            true,
            0,
            0
        );
        vm.stopPrank();
    }

    // =========================================================================
    // Distribution Setting Tests
    // =========================================================================

    function testSetEpochDistribution() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 5, 1000 ether);

        assertEq(deployedStrategy.getEpochDistribution(campaignId, 5), 1000 ether, "Distribution not set correctly");
    }

    function testSetMultipleEpochDistributions() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        uint256[] memory epochs = new uint256[](3);
        epochs[0] = 2;
        epochs[1] = 3;
        epochs[2] = 4;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 300 ether;

        vm.prank(address(createdDAO));
        deployedStrategy.setMultipleEpochDistributions(campaignId, epochs, amounts);

        assertEq(deployedStrategy.getEpochDistribution(campaignId, 2), 100 ether, "Epoch 2 distribution incorrect");
        assertEq(deployedStrategy.getEpochDistribution(campaignId, 3), 200 ether, "Epoch 3 distribution incorrect");
        assertEq(deployedStrategy.getEpochDistribution(campaignId, 4), 300 ether, "Epoch 4 distribution incorrect");
    }

    function testCannotSetDistributionForPastEpochWithoutSnapshot() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set current epoch to 5 (so epoch 3 is in the past)
        mockSnapshotter.setCurrentEpoch(5);

        // Don't snapshot epoch 3, try to set distribution for it
        vm.prank(address(createdDAO));
        vm.expectRevert(abi.encodeWithSelector(GaugeDistributionStrategy.EpochNotSnapshotted.selector, 3));
        deployedStrategy.setEpochDistribution(campaignId, 3, 1000 ether);
    }

    function testCanSetDistributionForPastEpochWithSnapshot() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set current epoch to 5 (so epoch 3 is in the past)
        mockSnapshotter.setCurrentEpoch(5);

        // Mark epoch 3 as snapshotted
        setupSnapshot(3, 1000);

        // Should succeed for past epoch with snapshot
        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 3, 1000 ether);

        assertEq(deployedStrategy.getEpochDistribution(campaignId, 3), 1000 ether, "Distribution should be set");
    }

    // =========================================================================
    // Claiming Tests
    // =========================================================================

    function testSuccessfulSingleEpochAccumulation() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set current epoch to 3 (so epoch 2 is complete)
        mockSnapshotter.setCurrentEpoch(3);

        // Setup snapshot data for epoch 2 first
        setupSnapshot(2, 1000);
        setupGaugeVotes(2, gauge1, 300); // 30%
        setupGaugeVotes(2, gauge2, 700); // 70%

        // Then set distribution for epoch 2
        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 2, 1000 ether);

        // Check accumulated amount (should only include epoch 2)
        bytes memory auxData = "";
        uint256 claimableGauge1 = deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData);
        uint256 claimableGauge2 = deployedStrategy.getClaimeableAmount(campaignId, gauge2, auxData);

        assertEq(claimableGauge1, 300 ether, "Gauge1 should get 30%");
        assertEq(claimableGauge2, 700 ether, "Gauge2 should get 70%");

        // Also test the individual epoch helper
        assertEq(
            deployedStrategy.getEpochClaimableAmount(campaignId, gauge1, 2), 300 ether, "Individual epoch amount wrong"
        );
    }

    function testUnsnapshotteEpochNotIncluded() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set distribution but don't snapshot
        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 2, 1000 ether);

        // Should return 0 since no epochs are snapshotted
        bytes memory auxData = "";
        uint256 claimable = deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData);
        assertEq(claimable, 0, "Should return 0 for unsnapshotted epochs");
    }

    function testEpochWithoutDistributionNotIncluded() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Setup snapshot but no distribution
        setupSnapshot(2, 1000);
        setupGaugeVotes(2, gauge1, 300);

        // Should return 0 since epoch has no distribution
        bytes memory auxData = "";
        uint256 claimable = deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData);
        assertEq(claimable, 0, "Should return 0 for epochs without distribution");
    }

    function testEpochsOutsideCampaignBoundsNotIncluded() public {
        uint256 campaignId = createTestCampaign(5, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set distributions and snapshots for epochs outside bounds
        vm.startPrank(address(createdDAO));
        // Can't set distribution for epoch 4 (before start)
        vm.expectRevert(abi.encodeWithSelector(GaugeDistributionStrategy.EpochNotInCampaign.selector, 4, 5, 10));
        deployedStrategy.setEpochDistribution(campaignId, 4, 1000 ether);

        // Can't set distribution for epoch 11 (after end)
        vm.expectRevert(abi.encodeWithSelector(GaugeDistributionStrategy.EpochNotInCampaign.selector, 11, 5, 10));
        deployedStrategy.setEpochDistribution(campaignId, 11, 1000 ether);
        vm.stopPrank();

        // Even if we somehow had snapshots for these epochs, accumulation should return 0
        bytes memory auxData = "";
        uint256 claimable = deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData);
        assertEq(claimable, 0, "Should return 0 when no valid epochs");
    }

    function testAccumulationWithMultipleCallsReturnsSameAmount() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set current epoch to 3 (so epoch 2 is complete)
        mockSnapshotter.setCurrentEpoch(3);

        // Setup snapshot for epoch 2 first
        setupSnapshot(2, 1000);
        setupGaugeVotes(2, gauge1, 500);

        // Then set distribution
        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 2, 1000 ether);

        bytes memory auxData = "";

        // Multiple calls should return the same accumulated amount
        uint256 firstCall = deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData);
        assertEq(firstCall, 500 ether, "First call should return 50%");

        uint256 secondCall = deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData);
        assertEq(secondCall, 500 ether, "Second call should return same amount");

        // The plugin will track actual claims and prevent double claiming
    }

    // =========================================================================
    // Multi-Epoch Tests
    // =========================================================================

    function testMultipleEpochAccumulation() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set current epoch to 4 (so epochs 1-3 are complete)
        mockSnapshotter.setCurrentEpoch(4);

        // Setup snapshots first
        setupSnapshot(1, 1000);
        setupGaugeVotes(1, gauge1, 400); // 40%

        setupSnapshot(2, 2000);
        setupGaugeVotes(2, gauge1, 1000); // 50%

        setupSnapshot(3, 3000);
        setupGaugeVotes(3, gauge1, 900); // 30%

        // Setup distributions after snapshots
        vm.startPrank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 1, 1000 ether);
        deployedStrategy.setEpochDistribution(campaignId, 2, 2000 ether);
        deployedStrategy.setEpochDistribution(campaignId, 3, 3000 ether);
        vm.stopPrank();

        // Check individual epoch amounts using helper
        assertEq(deployedStrategy.getEpochClaimableAmount(campaignId, gauge1, 1), 400 ether, "Epoch 1 incorrect");
        assertEq(deployedStrategy.getEpochClaimableAmount(campaignId, gauge1, 2), 1000 ether, "Epoch 2 incorrect");
        assertEq(deployedStrategy.getEpochClaimableAmount(campaignId, gauge1, 3), 900 ether, "Epoch 3 incorrect");

        // Check total accumulated amount
        bytes memory auxData = "";
        uint256 totalClaimable = deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData);
        assertEq(totalClaimable, 2300 ether, "Total should be sum of all epochs (400 + 1000 + 900)");

        // Test gauge2 accumulation
        setupGaugeVotes(1, gauge2, 600); // 60% of epoch 1
        setupGaugeVotes(2, gauge2, 1000); // 50% of epoch 2
        setupGaugeVotes(3, gauge2, 2100); // 70% of epoch 3

        uint256 gauge2Total = deployedStrategy.getClaimeableAmount(campaignId, gauge2, auxData);
        assertEq(gauge2Total, 3700 ether, "Gauge2 total should be 600 + 1000 + 2100");
    }

    function testAccumulationWithPartialSnapshots() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set current epoch to 6 (so epochs 1-5 are complete)
        mockSnapshotter.setCurrentEpoch(6);

        // Only snapshot epochs 1, 3, and 5
        setupSnapshot(1, 1000);
        setupGaugeVotes(1, gauge1, 500); // 50%

        setupSnapshot(3, 1000);
        setupGaugeVotes(3, gauge1, 500); // 50%

        setupSnapshot(5, 1000);
        setupGaugeVotes(5, gauge1, 500); // 50%

        // Setup distributions for snapshotted epochs
        vm.startPrank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 1, 1000 ether);
        deployedStrategy.setEpochDistribution(campaignId, 3, 3000 ether);
        deployedStrategy.setEpochDistribution(campaignId, 5, 5000 ether);

        // For future epochs (7 and up), we can set distribution without snapshot
        deployedStrategy.setEpochDistribution(campaignId, 7, 7000 ether); // Future epoch, ok without snapshot
        vm.stopPrank();

        // Should only accumulate snapshotted epochs
        bytes memory auxData = "";
        uint256 totalClaimable = deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData);
        assertEq(totalClaimable, 4500 ether, "Should only sum snapshotted epochs (500 + 1500 + 2500)");

        // Verify unsnapshotted epochs are not claimable individually
        assertEq(deployedStrategy.getEpochClaimableAmount(campaignId, gauge1, 2), 0, "Unsnapshotted epoch 2");
        assertEq(deployedStrategy.getEpochClaimableAmount(campaignId, gauge1, 4), 0, "Unsnapshotted epoch 4");
    }

    // =========================================================================
    // View Function Tests
    // =========================================================================

    function testIsEpochClaimable() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Initially not claimable
        assertFalse(deployedStrategy.isEpochClaimable(campaignId, 2), "Should not be claimable without setup");

        // Set distribution only
        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 2, 1000 ether);
        assertFalse(deployedStrategy.isEpochClaimable(campaignId, 2), "Should not be claimable without snapshot");

        // Add snapshot
        setupSnapshot(2, 1000);
        assertTrue(
            deployedStrategy.isEpochClaimable(campaignId, 2), "Should be claimable with distribution and snapshot"
        );
    }

    function testContinuousCampaignAccumulation() public {
        // Create continuous campaign (endEpoch = 0)
        uint256 campaignId = createTestCampaign(1, 0);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set current epoch to 21 (so epoch 20 and below are complete)
        mockSnapshotter.setCurrentEpoch(21);

        // Snapshot some epochs first
        setupSnapshot(1, 1000);
        setupGaugeVotes(1, gauge1, 500);

        setupSnapshot(5, 1000);
        setupGaugeVotes(5, gauge1, 500);

        setupSnapshot(10, 1000);
        setupGaugeVotes(10, gauge1, 500);

        setupSnapshot(20, 1000);
        setupGaugeVotes(20, gauge1, 500);

        // Set distributions for the snapshotted epochs
        vm.startPrank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 1, 1000 ether);
        deployedStrategy.setEpochDistribution(campaignId, 5, 5000 ether);
        deployedStrategy.setEpochDistribution(campaignId, 10, 10_000 ether);
        deployedStrategy.setEpochDistribution(campaignId, 20, 20_000 ether);
        vm.stopPrank();

        // Should accumulate all snapshotted epochs up to current epoch
        bytes memory auxData = "";
        uint256 totalClaimable = deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData);
        assertEq(totalClaimable, 18_000 ether, "Should accumulate epochs 1, 5, 10, 20 (500 + 2500 + 5000 + 10000)");
    }

    // =========================================================================
    // Edge Case Tests
    // =========================================================================

    function testCannotLowerDistribution() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set initial distribution
        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 2, 1000 ether);

        // Try to lower it
        vm.prank(address(createdDAO));
        vm.expectRevert(
            abi.encodeWithSelector(GaugeDistributionStrategy.CannotLowerDistribution.selector, 2, 1000 ether, 500 ether)
        );
        deployedStrategy.setEpochDistribution(campaignId, 2, 500 ether);
    }

    function testCanIncreaseDistribution() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set initial distribution
        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 2, 1000 ether);

        // Increase it - should succeed
        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 2, 1500 ether);

        assertEq(deployedStrategy.getEpochDistribution(campaignId, 2), 1500 ether, "Distribution should be increased");
    }

    function testCannotLowerMultipleDistributions() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set initial distributions
        uint256[] memory epochs = new uint256[](3);
        epochs[0] = 2;
        epochs[1] = 3;
        epochs[2] = 4;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 300 ether;

        vm.prank(address(createdDAO));
        deployedStrategy.setMultipleEpochDistributions(campaignId, epochs, amounts);

        // Try to lower epoch 3's distribution
        amounts[1] = 150 ether; // Lower than 200 ether

        vm.prank(address(createdDAO));
        vm.expectRevert(
            abi.encodeWithSelector(GaugeDistributionStrategy.CannotLowerDistribution.selector, 3, 200 ether, 150 ether)
        );
        deployedStrategy.setMultipleEpochDistributions(campaignId, epochs, amounts);
    }

    function testZeroVotesGauge() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 1, 1000 ether);

        setupSnapshot(1, 1000);
        setupGaugeVotes(1, gauge1, 1000);
        setupGaugeVotes(1, gauge2, 0); // No votes

        bytes memory auxData = "";
        assertEq(deployedStrategy.getClaimeableAmount(campaignId, gauge2, auxData), 0, "Zero votes should get 0");
    }

    function testZeroTotalVotingPower() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 1, 1000 ether);

        setupSnapshot(1, 0); // No total voting power
        setupGaugeVotes(1, gauge1, 0);

        bytes memory auxData = "";
        assertEq(deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData), 0, "Should return 0 when no votes");
    }

    // =========================================================================
    // Live Data Tests
    // =========================================================================

    function testCurrentEpochUsesLiveData() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set current epoch to 5
        uint256 currentEpoch = 5;
        mockSnapshotter.setCurrentEpoch(currentEpoch);
        mockGaugeVoter.setEpoch(currentEpoch);

        // Set live gauge votes (no snapshot taken yet)
        mockGaugeVoter.setTotalVotingPowerCast(1000);
        mockGaugeVoter.setGaugeVotes(gauge1, 400); // 40%
        mockGaugeVoter.setGaugeVotes(gauge2, 600); // 60%

        // Set distribution for current epoch
        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, currentEpoch, 1000 ether);

        // Should be able to claim using live data (no snapshot required)
        bytes memory auxData = "";
        
        // Debug: Check if gauge voter is properly set
        address gaugeVoterAddr = address(deployedStrategy.gaugeVoter());
        assertEq(gaugeVoterAddr, address(mockGaugeVoter), "Gauge voter should be set correctly");
        
        uint256 claimableGauge1 = deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData);
        uint256 claimableGauge2 = deployedStrategy.getClaimeableAmount(campaignId, gauge2, auxData);

        assertEq(claimableGauge1, 400 ether, "Gauge1 should get 40% from live data");
        assertEq(claimableGauge2, 600 ether, "Gauge2 should get 60% from live data");
    }

    function testCurrentEpochClaimableWithoutSnapshot() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Set current epoch
        uint256 currentEpoch = 3;
        mockSnapshotter.setCurrentEpoch(currentEpoch);
        mockGaugeVoter.setEpoch(currentEpoch);

        // Verify current epoch is claimable even without snapshot
        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, currentEpoch, 1000 ether);

        assertTrue(
            deployedStrategy.isEpochClaimable(campaignId, currentEpoch),
            "Current epoch should be claimable without snapshot"
        );
    }

    function testMixedEpochsWithLiveDataForCurrent() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Current epoch is 4
        uint256 currentEpoch = 4;
        mockSnapshotter.setCurrentEpoch(currentEpoch);
        mockGaugeVoter.setEpoch(currentEpoch);

        // Setup past epochs with snapshots
        setupSnapshot(2, 1000);
        setupGaugeVotes(2, gauge1, 500); // 50%

        setupSnapshot(3, 1000);
        setupGaugeVotes(3, gauge1, 300); // 30%

        // Setup current epoch with live data (no snapshot)
        mockGaugeVoter.setTotalVotingPowerCast(1000);
        mockGaugeVoter.setGaugeVotes(gauge1, 700); // 70%

        // Set distributions
        vm.startPrank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, 2, 1000 ether);
        deployedStrategy.setEpochDistribution(campaignId, 3, 2000 ether);
        deployedStrategy.setEpochDistribution(campaignId, 4, 3000 ether); // Current epoch
        vm.stopPrank();

        // Check total claimable (past epochs from snapshot + current from live data)
        bytes memory auxData = "";
        uint256 totalClaimable = deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData);
        
        // Expected: 500 (epoch 2) + 600 (epoch 3) + 2100 (epoch 4 live)
        assertEq(totalClaimable, 3200 ether, "Should accumulate past snapshots + current live data");
    }

    function testCanSetDistributionForCurrentEpochAnytime() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Current epoch is 5
        uint256 currentEpoch = 5;
        mockSnapshotter.setCurrentEpoch(currentEpoch);
        mockGaugeVoter.setEpoch(currentEpoch);

        // Set voting active (simulating voting period)
        mockGaugeVoter.setVotingActive(true);

        // Should still be able to set distribution for current epoch during voting
        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, currentEpoch, 1000 ether);

        assertEq(
            deployedStrategy.getEpochDistribution(campaignId, currentEpoch),
            1000 ether,
            "Should set distribution for current epoch even during voting"
        );
    }

    function testLiveDataChangesReflectInClaims() public {
        uint256 campaignId = createTestCampaign(1, 10);
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Current epoch
        uint256 currentEpoch = 3;
        mockSnapshotter.setCurrentEpoch(currentEpoch);
        mockGaugeVoter.setEpoch(currentEpoch);

        // Set distribution
        vm.prank(address(createdDAO));
        deployedStrategy.setEpochDistribution(campaignId, currentEpoch, 1000 ether);

        // Initial votes
        mockGaugeVoter.setTotalVotingPowerCast(1000);
        mockGaugeVoter.setGaugeVotes(gauge1, 500); // 50%

        bytes memory auxData = "";
        uint256 claimable1 = deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData);
        assertEq(claimable1, 500 ether, "Initial claim should be 50%");

        // Votes change (still in distribution period)
        mockGaugeVoter.setGaugeVotes(gauge1, 700); // Now 70%

        uint256 claimable2 = deployedStrategy.getClaimeableAmount(campaignId, gauge1, auxData);
        assertEq(claimable2, 700 ether, "Claim should reflect new votes immediately");
    }
}
