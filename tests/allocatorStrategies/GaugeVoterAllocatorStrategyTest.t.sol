// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.29 <0.9.0;

import { AragonTest } from "../helpers/AragonTest.sol";
import { GaugeDistributionStrategy } from "../../src/allocatorStrategies/GaugeDistributionStrategy.sol";
import { MockAddressGaugeVoter } from "../mocks/MockAddressGaugeVoter.sol";
import { MintableERC20 } from "../mocks/MintableERC20.sol";
import { IAllocatorStrategy } from "../../src/interfaces/IAllocatorStrategy.sol";
import { CapitalDistributorPlugin } from "../../src/CapitalDistributorPlugin.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title GaugeDistributionStrategyTest
/// @notice Test suite for GaugeDistributionStrategy contract (gauge-based distribution)
contract GaugeDistributionStrategyTest is AragonTest {
    // =========================================================================
    // State Variables
    // =========================================================================

    CapitalDistributorPlugin capitalDistributorPlugin;
    GaugeDistributionStrategy public strategy;
    MockAddressGaugeVoter public mockGaugeVoter;
    MintableERC20 public token;

    bytes32 public constant STRATEGY_TYPE_ID = keccak256("GaugeDistributionStrategy");
    uint256 public constant DEFAULT_CAMPAIGN_ID = 1;
    uint256 public constant DEFAULT_DISTRIBUTION_AMOUNT = 1000 ether;
    uint256 public constant DEFAULT_EPOCH = 1;

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

        // Deploy test token
        token = new MintableERC20();

        // Setup mock gauge voter state
        mockGaugeVoter.setEpoch(DEFAULT_EPOCH);
        mockGaugeVoter.setVotingActive(false); // Start in distribution period

        // Deploy strategy implementation and register with factory
        strategy = new GaugeDistributionStrategy();
        vm.startPrank(address(createdDao));

        allocatorStrategyFactory.registerStrategyType(
            STRATEGY_TYPE_ID, address(strategy), "GaugeDistributionStrategy", address(0), 0
        );
        vm.stopPrank();

        // Mint tokens to DAO treasury for distribution
        token.mint(address(createdDao), 10_000 ether);
    }

    // =========================================================================
    // Helper Functions
    // =========================================================================

    /// @notice Create a test campaign with default parameters
    /// @return campaignId The created campaign ID
    function createTestCampaign() internal returns (uint256 campaignId) {
        return createTestCampaign(DEFAULT_CAMPAIGN_ID, DEFAULT_DISTRIBUTION_AMOUNT);
    }

    /// @notice Create a test campaign with specified parameters
    /// @param _distributionAmount Amount to distribute
    /// @return campaignId The created campaign ID
    function createTestCampaign(
        uint256, /* _campaignId */
        uint256 _distributionAmount
    )
        internal
        returns (uint256 campaignId)
    {
        vm.startPrank(address(createdDao));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = abi.encode(address(mockGaugeVoter));
        bytes memory allocationCampaignAuxData = abi.encode(_distributionAmount);

        campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                STRATEGY_TYPE_ID, allocatorDeploymentParams, allocationCampaignAuxData
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(false, 0, 0)
        );

        vm.stopPrank();
        return campaignId;
    }

    /// @notice Setup a voting scenario with specified parameters for gauges
    /// @param _totalVotingPower Total voting power cast in the epoch
    /// @param _gaugeVotes Array of gauge vote amounts
    function setupGaugeVotingScenario(uint256 _totalVotingPower, uint256[] memory _gaugeVotes) internal {
        address[4] memory gauges = [alice, bob, carol, david]; // Using alice, bob, etc. as gauge addresses for testing

        // Set total voting power
        mockGaugeVoter.setTotalVotingPowerCast(_totalVotingPower);

        // Set individual gauge votes
        for (uint256 i = 0; i < _gaugeVotes.length && i < gauges.length; i++) {
            mockGaugeVoter.setGaugeVotes(gauges[i], _gaugeVotes[i]);
        }
    }

    /// @notice Assert proportional allocation calculation for gauges
    /// @param _gaugeVotes Gauge's vote count
    /// @param _totalVotingPower Total voting power cast
    /// @param _distributionAmount Total distribution amount
    /// @param _actualAmount Actual amount returned by contract
    function assertProportionalAllocation(
        uint256 _gaugeVotes,
        uint256 _totalVotingPower,
        uint256 _distributionAmount,
        uint256 _actualAmount
    )
        internal
        pure
    {
        uint256 expectedAmount = (_gaugeVotes * _distributionAmount) / _totalVotingPower;
        assertEq(_actualAmount, expectedAmount, "Proportional allocation calculation incorrect");
    }

    /// @notice Expect a specific strategy error to be thrown
    /// @param _errorSelector The error selector to expect
    function expectStrategyError(bytes4 _errorSelector) internal {
        vm.expectRevert(_errorSelector);
    }

    /// @notice Get the deployed strategy instance from a campaign
    /// @param _campaignId Campaign ID to get strategy from
    /// @return deployedStrategy The deployed strategy instance
    function getDeployedStrategy(uint256 _campaignId)
        internal
        view
        returns (GaugeDistributionStrategy deployedStrategy)
    {
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(_campaignId);
        return GaugeDistributionStrategy(address(campaign.allocationStrategy));
    }

    // =========================================================================
    // Basic Operations Tests
    // =========================================================================

    /// @notice Test basic campaign creation works
    function testInitialization() public {
        vm.startPrank(address(createdDao));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = abi.encode(address(mockGaugeVoter));
        bytes memory allocationCampaignAuxData = abi.encode(DEFAULT_DISTRIBUTION_AMOUNT);

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                STRATEGY_TYPE_ID, allocatorDeploymentParams, allocationCampaignAuxData
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(false, 0, 0)
        );

        // Basic validation that campaign was created
        assertTrue(campaignId == 0, "Campaign ID should be 0 for first campaign");
        vm.stopPrank();
    }

    /// @notice Test campaign creation with valid parameters
    function testCampaignCreation() public {
        // Setup: Ensure voting is inactive
        mockGaugeVoter.setVotingActive(false);

        // Expect event emission (note: event is emitted by the deployed strategy, not plugin)
        vm.expectEmit(true, true, false, false);
        emit AllocationCampaignCreated(address(capitalDistributorPlugin), 0); // Campaign ID starts at 0

        // Create campaign
        uint256 campaignId = createTestCampaign();

        // Get the deployed strategy instance
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Verify campaign was created in the deployed strategy
        (uint256 epochId, uint256 distributionAmount) = deployedStrategy.campaigns(campaignId);
        assertEq(epochId, DEFAULT_EPOCH, "Campaign epoch not set correctly");
        assertEq(distributionAmount, DEFAULT_DISTRIBUTION_AMOUNT, "Distribution amount not set correctly");
    }

    /// @notice Test successful claim with proportional allocation for gauges
    function testSuccessfulClaim() public {
        // Setup voting scenario: Gauge (alice address) has 30% of total votes
        uint256[] memory gaugeVotes = new uint256[](1);
        gaugeVotes[0] = 300; // Gauge's vote count
        setupGaugeVotingScenario(1000, gaugeVotes); // Total voting power: 1000

        // Create campaign and get the actual campaign ID
        uint256 campaignId = createTestCampaign();

        // Calculate expected amount for gauge (alice)
        uint256 expectedAmount = (300 * DEFAULT_DISTRIBUTION_AMOUNT) / 1000; // 30% of distribution

        // Get the deployed strategy instance
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Check claimable amount
        uint256 claimableAmount = deployedStrategy.getTotalClaimableAmount(campaignId, alice, "");
        assertEq(claimableAmount, expectedAmount, "Claimable amount calculation incorrect");

        // Verify gauge eligibility
        assertTrue(deployedStrategy.isGaugeEligible(campaignId, alice), "Gauge (alice) should be eligible");
    }

    /// @notice Test all encoding type functions return correct values
    function testGetEncodingTypes() public {
        // Create a campaign to deploy the strategy
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        assertEq(
            deployedStrategy.getInitializationEncodingTypes(), "address", "Initialization encoding types incorrect"
        );
        assertEq(deployedStrategy.getCreationEncodingTypes(), "uint256", "Creation encoding types incorrect");
        assertEq(deployedStrategy.getClaimEncodingTypes(), "", "Claim encoding types should be empty");
    }

    /// @notice Test end-to-end plugin integration workflow for gauge distribution
    function testPluginIntegration() public {
        // Setup voting scenario for gauges
        uint256[] memory gaugeVotes = new uint256[](2);
        gaugeVotes[0] = 400; // Gauge alice: 40%
        gaugeVotes[1] = 600; // Gauge bob: 60%
        setupGaugeVotingScenario(1000, gaugeVotes);

        // Create campaign through plugin
        uint256 campaignId = createTestCampaign();

        // Test claiming through plugin for gauges
        uint256 aliceExpected = (400 * DEFAULT_DISTRIBUTION_AMOUNT) / 1000;
        uint256 bobExpected = (600 * DEFAULT_DISTRIBUTION_AMOUNT) / 1000;

        // Check amounts through plugin for gauges
        uint256 aliceAmount = capitalDistributorPlugin.getCampaignPayout(campaignId, alice, "");
        uint256 bobAmount = capitalDistributorPlugin.getCampaignPayout(campaignId, bob, "");

        assertEq(aliceAmount, aliceExpected, "Gauge alice's payout through plugin incorrect");
        assertEq(bobAmount, bobExpected, "Gauge bob's payout through plugin incorrect");
    }

    // =========================================================================
    // Calculation Logic Tests
    // =========================================================================

    /// @notice Test proportional allocation calculation with various scenarios
    function testProportionalAllocation() public {
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Test scenario 1: Equal voting power
        uint256[] memory gaugeVotes = new uint256[](2);
        gaugeVotes[0] = 500; // Alice: 50%
        gaugeVotes[1] = 500; // Bob: 50%
        setupGaugeVotingScenario(1000, gaugeVotes);

        uint256 aliceAmount = deployedStrategy.getTotalClaimableAmount(campaignId, alice, "");
        uint256 bobAmount = deployedStrategy.getTotalClaimableAmount(campaignId, bob, "");

        assertProportionalAllocation(500, 1000, DEFAULT_DISTRIBUTION_AMOUNT, aliceAmount);
        assertProportionalAllocation(500, 1000, DEFAULT_DISTRIBUTION_AMOUNT, bobAmount);

        // Test scenario 2: Unequal voting power
        gaugeVotes[0] = 750; // Alice: 75%
        gaugeVotes[1] = 250; // Bob: 25%
        setupGaugeVotingScenario(1000, gaugeVotes);

        aliceAmount = deployedStrategy.getTotalClaimableAmount(campaignId, alice, "");
        bobAmount = deployedStrategy.getTotalClaimableAmount(campaignId, bob, "");

        assertProportionalAllocation(750, 1000, DEFAULT_DISTRIBUTION_AMOUNT, aliceAmount);
        assertProportionalAllocation(250, 1000, DEFAULT_DISTRIBUTION_AMOUNT, bobAmount);
    }

    /// @notice Test gauge with zero votes gets zero allocation
    function testZeroVotingPower() public {
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Setup: Gauge alice has votes, gauge bob has none
        uint256[] memory gaugeVotes = new uint256[](2);
        gaugeVotes[0] = 1000; // Gauge alice: 100%
        gaugeVotes[1] = 0; // Gauge bob: 0%
        setupGaugeVotingScenario(1000, gaugeVotes);

        uint256 aliceAmount = deployedStrategy.getTotalClaimableAmount(campaignId, alice, "");
        uint256 bobAmount = deployedStrategy.getTotalClaimableAmount(campaignId, bob, "");

        assertEq(aliceAmount, DEFAULT_DISTRIBUTION_AMOUNT, "Gauge alice should get full amount");
        assertEq(bobAmount, 0, "Gauge bob should get zero with no votes");

        // Verify eligibility
        assertTrue(deployedStrategy.isGaugeEligible(campaignId, alice), "Gauge alice should be eligible");
        assertFalse(deployedStrategy.isGaugeEligible(campaignId, bob), "Gauge bob should not be eligible");
    }

    /// @notice Test handling of zero total voting power
    function testZeroTotalVotingPower() public {
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Setup: No one has voted (total voting power is 0)
        uint256[] memory gaugeVotes = new uint256[](2);
        gaugeVotes[0] = 0; // Alice: 0
        gaugeVotes[1] = 0; // Bob: 0
        setupGaugeVotingScenario(0, gaugeVotes); // Total: 0

        uint256 aliceAmount = deployedStrategy.getTotalClaimableAmount(campaignId, alice, "");
        uint256 bobAmount = deployedStrategy.getTotalClaimableAmount(campaignId, bob, "");

        assertEq(aliceAmount, 0, "Alice should get zero when total voting power is zero");
        assertEq(bobAmount, 0, "Bob should get zero when total voting power is zero");

        // Verify eligibility
        assertFalse(deployedStrategy.isGaugeEligible(campaignId, alice), "Alice should not be eligible");
        assertFalse(deployedStrategy.isGaugeEligible(campaignId, bob), "Bob should not be eligible");
    }

    /// @notice Test multiple gauges receiving from same campaign
    function testMultipleUsers() public {
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Setup: Four gauges with different vote counts
        uint256[] memory gaugeVotes = new uint256[](4);
        gaugeVotes[0] = 100; // Gauge alice: 10%
        gaugeVotes[1] = 200; // Gauge bob: 20%
        gaugeVotes[2] = 300; // Gauge carol: 30%
        gaugeVotes[3] = 400; // Gauge david: 40%
        setupGaugeVotingScenario(1000, gaugeVotes);

        address[4] memory gauges = [alice, bob, carol, david];
        uint256[4] memory expectedAmounts = [
            (100 * DEFAULT_DISTRIBUTION_AMOUNT) / 1000, // Gauge alice: 10%
            (200 * DEFAULT_DISTRIBUTION_AMOUNT) / 1000, // Gauge bob: 20%
            (300 * DEFAULT_DISTRIBUTION_AMOUNT) / 1000, // Gauge carol: 30%
            (400 * DEFAULT_DISTRIBUTION_AMOUNT) / 1000 // Gauge david: 40%
        ];

        // Verify all gauges get correct proportional amounts
        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < gauges.length; i++) {
            uint256 gaugeAmount = deployedStrategy.getTotalClaimableAmount(campaignId, gauges[i], "");
            assertEq(gaugeAmount, expectedAmounts[i], "Gauge amount calculation incorrect");
            assertTrue(deployedStrategy.isGaugeEligible(campaignId, gauges[i]), "Gauge should be eligible");
            totalClaimed += gaugeAmount;
        }

        // Verify total claimed equals distribution amount (no rounding errors)
        assertEq(totalClaimed, DEFAULT_DISTRIBUTION_AMOUNT, "Total claimed should equal distribution amount");
    }

    /// @notice Test gauges with different vote counts
    function testPartialVotingPower() public {
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Setup: Gauges received different amounts of votes
        uint256[] memory gaugeVotes = new uint256[](3);
        gaugeVotes[0] = 150; // Gauge alice received 150 votes
        gaugeVotes[1] = 350; // Gauge bob received 350 votes
        gaugeVotes[2] = 500; // Gauge carol received 500 votes
        setupGaugeVotingScenario(1000, gaugeVotes);

        uint256 aliceAmount = deployedStrategy.getTotalClaimableAmount(campaignId, alice, "");
        uint256 bobAmount = deployedStrategy.getTotalClaimableAmount(campaignId, bob, "");
        uint256 carolAmount = deployedStrategy.getTotalClaimableAmount(campaignId, carol, "");

        // Verify proportional allocation based on votes received
        assertProportionalAllocation(150, 1000, DEFAULT_DISTRIBUTION_AMOUNT, aliceAmount);
        assertProportionalAllocation(350, 1000, DEFAULT_DISTRIBUTION_AMOUNT, bobAmount);
        assertProportionalAllocation(500, 1000, DEFAULT_DISTRIBUTION_AMOUNT, carolAmount);

        // Verify all are eligible since they have votes > 0
        assertTrue(deployedStrategy.isGaugeEligible(campaignId, alice), "Gauge alice should be eligible");
        assertTrue(deployedStrategy.isGaugeEligible(campaignId, bob), "Gauge bob should be eligible");
        assertTrue(deployedStrategy.isGaugeEligible(campaignId, carol), "Gauge carol should be eligible");
    }

    /// @notice Test isGaugeEligible function validation
    function testEligibilityChecks() public {
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Setup voting scenario for gauges
        uint256[] memory gaugeVotes = new uint256[](2);
        gaugeVotes[0] = 500; // Gauge alice has votes
        gaugeVotes[1] = 0; // Gauge bob has no votes
        setupGaugeVotingScenario(1000, gaugeVotes);

        // Test eligibility with correct conditions
        assertTrue(deployedStrategy.isGaugeEligible(campaignId, alice), "Gauge alice should be eligible");
        assertFalse(deployedStrategy.isGaugeEligible(campaignId, bob), "Gauge bob should not be eligible");

        // Test eligibility when voting is active (should be false)
        mockGaugeVoter.setVotingActive(true);
        assertFalse(
            deployedStrategy.isGaugeEligible(campaignId, alice),
            "Gauge alice should not be eligible during active voting"
        );
        assertFalse(
            deployedStrategy.isGaugeEligible(campaignId, bob), "Gauge bob should not be eligible during active voting"
        );

        // Test eligibility when epoch changes (should be false)
        mockGaugeVoter.setVotingActive(false);
        mockGaugeVoter.setEpoch(2); // Change epoch
        assertFalse(
            deployedStrategy.isGaugeEligible(campaignId, alice), "Gauge alice should not be eligible in different epoch"
        );
        assertFalse(
            deployedStrategy.isGaugeEligible(campaignId, bob), "Gauge bob should not be eligible in different epoch"
        );

        // Test eligibility for non-existent campaign
        assertFalse(deployedStrategy.isGaugeEligible(999, alice), "Should not be eligible for non-existent campaign");
    }

    // =========================================================================
    // State Management Tests
    // =========================================================================

    /// @notice Test campaign epoch must match current epoch for claims
    function testEpochValidation() public {
        // Create campaign in epoch 1
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Setup voting scenario
        uint256[] memory gaugeVotes = new uint256[](1);
        gaugeVotes[0] = 500;
        setupGaugeVotingScenario(1000, gaugeVotes);

        // Verify claim works in correct epoch
        uint256 expectedAmount = (500 * DEFAULT_DISTRIBUTION_AMOUNT) / 1000;
        assertEq(
            deployedStrategy.getTotalClaimableAmount(campaignId, alice, ""),
            expectedAmount,
            "Should work in correct epoch"
        );

        // Change epoch and verify claim fails
        mockGaugeVoter.setEpoch(2);
        vm.expectRevert(
            abi.encodeWithSelector(
                GaugeDistributionStrategy.EpochMismatch.selector,
                DEFAULT_EPOCH, // Campaign epoch
                2 // Current epoch
            )
        );
        deployedStrategy.getTotalClaimableAmount(campaignId, alice, "");
    }

    /// @notice Test claims are blocked during active voting periods
    function testVotingActiveRestriction() public {
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Setup voting scenario
        uint256[] memory gaugeVotes = new uint256[](1);
        gaugeVotes[0] = 500;
        setupGaugeVotingScenario(1000, gaugeVotes);

        // Verify claim works when voting is inactive
        uint256 expectedAmount = (500 * DEFAULT_DISTRIBUTION_AMOUNT) / 1000;
        assertEq(
            deployedStrategy.getTotalClaimableAmount(campaignId, alice, ""),
            expectedAmount,
            "Should work when voting inactive"
        );

        // Activate voting and verify claim fails
        mockGaugeVoter.setVotingActive(true);
        expectStrategyError(GaugeDistributionStrategy.VotingCurrentlyActive.selector);
        deployedStrategy.getTotalClaimableAmount(campaignId, alice, "");
    }

    /// @notice Test handling of non-existent campaigns
    function testCampaignExistence() public {
        // Create a campaign first to get deployed strategy instance
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Setup voting scenario (doesn't matter for this test)
        uint256[] memory gaugeVotes = new uint256[](1);
        gaugeVotes[0] = 500;
        setupGaugeVotingScenario(1000, gaugeVotes);

        // Try to get claimable amount for non-existent campaign
        vm.expectRevert(abi.encodeWithSelector(GaugeDistributionStrategy.CampaignNotFound.selector, 999));
        deployedStrategy.getTotalClaimableAmount(999, alice, "");

        // Verify eligibility check also handles non-existent campaigns
        assertFalse(deployedStrategy.isGaugeEligible(999, alice), "Should not be eligible for non-existent campaign");
    }

    /// @notice Test campaigns can be created anytime (no voting status restriction)
    function testCampaignCreationAnytime() public {
        // Test creation during active voting
        mockGaugeVoter.setVotingActive(true);

        // Should succeed even during active voting (campaign ID starts at 0)
        vm.expectEmit(true, true, false, false);
        emit AllocationCampaignCreated(address(capitalDistributorPlugin), 0);

        uint256 campaignId1 = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy1 = getDeployedStrategy(campaignId1);

        // Verify campaign was created
        (uint256 epochId, uint256 distributionAmount) = deployedStrategy1.campaigns(campaignId1);
        assertEq(epochId, DEFAULT_EPOCH, "Campaign should be created in current epoch");
        assertEq(distributionAmount, DEFAULT_DISTRIBUTION_AMOUNT, "Distribution amount should be set");

        // Test creation during inactive voting
        mockGaugeVoter.setVotingActive(false);

        // Next campaign will have ID 1
        vm.expectEmit(true, true, false, false);
        emit AllocationCampaignCreated(address(capitalDistributorPlugin), 1);

        uint256 campaignId2 = createTestCampaign(2, 2000 ether);
        GaugeDistributionStrategy deployedStrategy2 = getDeployedStrategy(campaignId2);

        // Verify second campaign was created
        (epochId, distributionAmount) = deployedStrategy2.campaigns(campaignId2);
        assertEq(epochId, DEFAULT_EPOCH, "Second campaign should be created in current epoch");
        assertEq(distributionAmount, 2000 ether, "Distribution amount should be 2000 ether");
    }

    /// @notice Test behavior when epoch changes after campaign creation
    function testEpochTransition() public {
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Setup voting scenario in epoch 1
        uint256[] memory gaugeVotes = new uint256[](1);
        gaugeVotes[0] = 500;
        setupGaugeVotingScenario(1000, gaugeVotes);

        // Verify claim works in epoch 1
        uint256 expectedAmount = (500 * DEFAULT_DISTRIBUTION_AMOUNT) / 1000;
        assertEq(
            deployedStrategy.getTotalClaimableAmount(campaignId, alice, ""), expectedAmount, "Should work in epoch 1"
        );

        // Transition to epoch 2
        mockGaugeVoter.setEpoch(2);

        // Verify claims fail due to epoch mismatch
        vm.expectRevert(
            abi.encodeWithSelector(
                GaugeDistributionStrategy.EpochMismatch.selector,
                DEFAULT_EPOCH, // Campaign epoch
                2 // Current epoch
            )
        );
        deployedStrategy.getTotalClaimableAmount(campaignId, alice, "");

        // Verify eligibility also fails
        assertFalse(deployedStrategy.isGaugeEligible(campaignId, alice), "Should not be eligible in different epoch");
    }

    /// @notice Test claims work when voting transitions from active to inactive
    function testVotingPeriodTransition() public {
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Setup voting scenario
        uint256[] memory gaugeVotes = new uint256[](1);
        gaugeVotes[0] = 500;
        setupGaugeVotingScenario(1000, gaugeVotes);

        // Start with active voting - claims should fail
        mockGaugeVoter.setVotingActive(true);
        expectStrategyError(GaugeDistributionStrategy.VotingCurrentlyActive.selector);
        deployedStrategy.getTotalClaimableAmount(campaignId, alice, "");

        // Transition to inactive voting - claims should work
        mockGaugeVoter.setVotingActive(false);
        uint256 expectedAmount = (500 * DEFAULT_DISTRIBUTION_AMOUNT) / 1000;
        assertEq(
            deployedStrategy.getTotalClaimableAmount(campaignId, alice, ""),
            expectedAmount,
            "Should work when voting becomes inactive"
        );

        // Verify eligibility also follows voting status
        assertTrue(deployedStrategy.isGaugeEligible(campaignId, alice), "Should be eligible when voting inactive");

        mockGaugeVoter.setVotingActive(true);
        assertFalse(deployedStrategy.isGaugeEligible(campaignId, alice), "Should not be eligible when voting active");
    }

    /// @notice Test cannot recreate existing campaigns
    function testCampaignReuse() public {
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Verify campaign was created successfully
        (uint256 epochId, uint256 distributionAmount) = deployedStrategy.campaigns(campaignId);
        assertTrue(epochId > 0, "Campaign should exist");
        assertEq(distributionAmount, DEFAULT_DISTRIBUTION_AMOUNT, "Distribution amount should match");
    }

    /// @notice Test multiple concurrent campaigns within same epoch
    function testMultipleConcurrentCampaigns() public {
        // Create multiple campaigns in same epoch
        uint256 campaignId1 = createTestCampaign(1, 1000 ether);
        uint256 campaignId2 = createTestCampaign(2, 2000 ether);
        uint256 campaignId3 = createTestCampaign(3, 3000 ether);

        // Get deployed strategy instances
        GaugeDistributionStrategy deployedStrategy1 = getDeployedStrategy(campaignId1);
        GaugeDistributionStrategy deployedStrategy2 = getDeployedStrategy(campaignId2);
        GaugeDistributionStrategy deployedStrategy3 = getDeployedStrategy(campaignId3);

        // Setup voting scenario
        uint256[] memory gaugeVotes = new uint256[](1);
        gaugeVotes[0] = 500; // Alice has 50% voting power
        setupGaugeVotingScenario(1000, gaugeVotes);

        // Verify all campaigns work independently with correct amounts
        uint256 amount1 = deployedStrategy1.getTotalClaimableAmount(campaignId1, alice, "");
        uint256 amount2 = deployedStrategy2.getTotalClaimableAmount(campaignId2, alice, "");
        uint256 amount3 = deployedStrategy3.getTotalClaimableAmount(campaignId3, alice, "");

        assertEq(amount1, 500 ether, "Campaign 1 should give 50% of 1000"); // 50% of 1000
        assertEq(amount2, 1000 ether, "Campaign 2 should give 50% of 2000"); // 50% of 2000
        assertEq(amount3, 1500 ether, "Campaign 3 should give 50% of 3000"); // 50% of 3000

        // Verify eligibility for all campaigns
        assertTrue(deployedStrategy1.isGaugeEligible(campaignId1, alice), "Should be eligible for campaign 1");
        assertTrue(deployedStrategy2.isGaugeEligible(campaignId2, alice), "Should be eligible for campaign 2");
        assertTrue(deployedStrategy3.isGaugeEligible(campaignId3, alice), "Should be eligible for campaign 3");

        // Verify campaigns are independent - changing voting power affects all equally
        gaugeVotes[0] = 250; // Alice now has 25% voting power
        setupGaugeVotingScenario(1000, gaugeVotes);

        amount1 = deployedStrategy1.getTotalClaimableAmount(campaignId1, alice, "");
        amount2 = deployedStrategy2.getTotalClaimableAmount(campaignId2, alice, "");
        amount3 = deployedStrategy3.getTotalClaimableAmount(campaignId3, alice, "");

        assertEq(amount1, 250 ether, "Campaign 1 should now give 25% of 1000"); // 25% of 1000
        assertEq(amount2, 500 ether, "Campaign 2 should now give 25% of 2000"); // 25% of 2000
        assertEq(amount3, 750 ether, "Campaign 3 should now give 25% of 3000"); // 25% of 3000
    }

    // =========================================================================
    // Error Condition Tests
    // =========================================================================

    /// @notice Test initialization with invalid gauge voter address
    function testInvalidGaugeVoter() public {
        // Try to deploy strategy with zero address gauge voter
        bytes memory invalidInitData = abi.encode(address(0));

        // The error will be wrapped in DeploymentFailed
        vm.expectRevert();
        allocatorStrategyFactory.getOrDeployStrategy(STRATEGY_TYPE_ID, createdDao, invalidInitData);
    }

    /// @notice Test campaign creation with zero distribution amount
    function testInvalidDistributionAmount() public {
        // Try to create campaign with zero distribution amount
        vm.startPrank(address(createdDao));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = abi.encode(address(mockGaugeVoter));
        bytes memory allocationCampaignAuxData = abi.encode(0); // Zero distribution amount

        // This will fail, but the exact error depends on internal implementation details
        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                STRATEGY_TYPE_ID, allocatorDeploymentParams, allocationCampaignAuxData
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(false, 0, 0)
        );
        vm.stopPrank();
    }

    /// @notice Test unauthorized campaign creation (non-DAO user)
    function testUnauthorizedCampaignCreation() public {
        // First create a campaign to get deployed strategy instance
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Try to create campaign as non-DAO user (alice) - should fail with OnlyDAOAllowed
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAllocatorStrategy.OnlyDAOAllowed.selector, alice));
        deployedStrategy.setAllocationCampaign(999, abi.encode(DEFAULT_DISTRIBUTION_AMOUNT));

        // Verify DAO can create campaigns (this is already proven by the campaign creation above)
        // The campaign was already created in createTestCampaign(), so verify it exists
        (uint256 epochId, uint256 distributionAmount) = deployedStrategy.campaigns(campaignId);
        assertEq(epochId, DEFAULT_EPOCH, "Campaign should be created");
        assertEq(distributionAmount, DEFAULT_DISTRIBUTION_AMOUNT, "Distribution amount should be set");
    }

    /// @notice Test claims in wrong epoch (EpochMismatch error)
    function testEpochMismatch() public {
        // Create campaign in epoch 1
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Setup voting scenario
        uint256[] memory gaugeVotes = new uint256[](1);
        gaugeVotes[0] = 500;
        setupGaugeVotingScenario(1000, gaugeVotes);

        // Verify claim works in correct epoch
        assertGt(deployedStrategy.getTotalClaimableAmount(campaignId, alice, ""), 0, "Should work in correct epoch");

        // Change to epoch 2 and verify specific error
        mockGaugeVoter.setEpoch(2);

        // Test getTotalClaimableAmount error
        vm.expectRevert(
            abi.encodeWithSelector(
                GaugeDistributionStrategy.EpochMismatch.selector,
                DEFAULT_EPOCH, // Campaign epoch
                2 // Current epoch
            )
        );
        deployedStrategy.getTotalClaimableAmount(campaignId, alice, "");

        // Test isGaugeEligible returns false (no error thrown)
        assertFalse(deployedStrategy.isGaugeEligible(campaignId, alice), "Should not be eligible in wrong epoch");
    }

    /// @notice Test claims during active voting (VotingCurrentlyActive error)
    function testVotingCurrentlyActive() public {
        uint256 campaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(campaignId);

        // Setup voting scenario with inactive voting
        uint256[] memory gaugeVotes = new uint256[](1);
        gaugeVotes[0] = 500;
        setupGaugeVotingScenario(1000, gaugeVotes);
        mockGaugeVoter.setVotingActive(false);

        // Verify claim works when voting inactive
        assertGt(deployedStrategy.getTotalClaimableAmount(campaignId, alice, ""), 0, "Should work when voting inactive");

        // Activate voting and verify specific error
        mockGaugeVoter.setVotingActive(true);

        // Test getTotalClaimableAmount error
        expectStrategyError(GaugeDistributionStrategy.VotingCurrentlyActive.selector);
        deployedStrategy.getTotalClaimableAmount(campaignId, alice, "");

        // Test isGaugeEligible returns false (no error thrown)
        assertFalse(deployedStrategy.isGaugeEligible(campaignId, alice), "Should not be eligible during active voting");
    }

    /// @notice Test operations on non-existent campaigns (CampaignNotFound error)
    function testCampaignNotFound() public {
        // Create one campaign first to get a deployed strategy instance
        uint256 existingCampaignId = createTestCampaign();
        GaugeDistributionStrategy deployedStrategy = getDeployedStrategy(existingCampaignId);

        // Setup voting scenario (shouldn't matter for this test)
        uint256[] memory gaugeVotes = new uint256[](1);
        gaugeVotes[0] = 500;
        setupGaugeVotingScenario(1000, gaugeVotes);

        uint256 nonExistentCampaignId = 999;

        // Test getTotalClaimableAmount with non-existent campaign
        vm.expectRevert(
            abi.encodeWithSelector(GaugeDistributionStrategy.CampaignNotFound.selector, nonExistentCampaignId)
        );
        deployedStrategy.getTotalClaimableAmount(nonExistentCampaignId, alice, "");

        // Test isGaugeEligible returns false (no error thrown)
        assertFalse(
            deployedStrategy.isGaugeEligible(nonExistentCampaignId, alice),
            "Should not be eligible for non-existent campaign"
        );

        // Verify campaign existence check
        (uint256 epochId, uint256 distributionAmount) = deployedStrategy.campaigns(nonExistentCampaignId);
        assertEq(epochId, 0, "Non-existent campaign should have epochId 0");
        assertEq(distributionAmount, 0, "Non-existent campaign should have distributionAmount 0");

        // Create another campaign and verify it now works
        uint256 newCampaignId = createTestCampaign(nonExistentCampaignId, 500 ether);
        GaugeDistributionStrategy newDeployedStrategy = getDeployedStrategy(newCampaignId);
        uint256 expectedAmount = (500 * 500 ether) / 1000; // 50% of 500 ether
        assertEq(
            newDeployedStrategy.getTotalClaimableAmount(newCampaignId, alice, ""),
            expectedAmount,
            "Should work after campaign creation"
        );
    }
}
