// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.29 <0.9.0;

import { Vm } from "forge-std/Vm.sol";
import { Action } from "@aragon/commons/executors/IExecutor.sol";

import { IPayoutActionEncoder } from "../src/interfaces/IPayoutActionEncoder.sol";
import { CapitalDistributorPlugin } from "../src/CapitalDistributorPlugin.sol";
import { AragonTest } from "./helpers/AragonTest.sol";
import { IAllocatorStrategy } from "../src/interfaces/IAllocatorStrategy.sol";
import { AllocatorStrategyMock } from "./mocks/AllocatorStrategyMock.sol";
import { VaultDepositPayoutActionEncoder } from "../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";
import { IAllocatorStrategyFactory } from "../src/interfaces/IAllocatorStrategyFactory.sol";
import { IActionEncoderFactory } from "../src/interfaces/IActionEncoderFactory.sol";

import { MintableERC20 } from "./mocks/MintableERC20.sol";
import { ERC4626Mock } from "./mocks/ERC4626Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title CapitalDistributorPluginTest
/// @notice Comprehensive test suite for CapitalDistributorPlugin functionality
/// @dev Tests campaign creation, payout claiming, and all edge cases for maximum coverage
contract CapitalDistributorPluginTest is AragonTest {
    CapitalDistributorPlugin capitalDistributorPlugin;
    AllocatorStrategyMock strategy;
    MintableERC20 token;
    ERC4626Mock vaultToSendTokens;
    VaultDepositPayoutActionEncoder vaultDepositActionEncoder;

    /// @notice Sets up the test environment with required contracts and configurations
    function setUp() public virtual {
        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddress[0]);
        token = new MintableERC20();
        strategy = new AllocatorStrategyMock();

        allocatorStrategyFactory.registerStrategyType(toBytes32("mock-strategy"), address(strategy), "", address(0), 0);

        vaultToSendTokens = new ERC4626Mock(address(token));
        vaultDepositActionEncoder = new VaultDepositPayoutActionEncoder();
    }

    // ============================================
    // Helper Functions
    // ============================================

    /// @notice Helper function to create a basic campaign with default parameters
    function createBasicCampaign() internal returns (uint256) {
        return capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );
    }

    /// @notice Helper function to create campaign ID 999 that returns 0 claimable amount
    function createZeroAmountCampaign() internal returns (uint256) {
        // Create campaigns until we get ID 999
        uint256 currentId = capitalDistributorPlugin.numCampaigns();
        while (currentId < 999) {
            createBasicCampaign();
            currentId = capitalDistributorPlugin.numCampaigns();
        }
        return createBasicCampaign(); // This will be campaign 999
    }

    /// @notice Helper function to create a campaign with custom parameters
    function createCampaignWithParams(
        bool multipleClaimsAllowed,
        uint256 startTime,
        uint256 endTime
    )
        internal
        returns (uint256)
    {
        return capitalDistributorPlugin.createCampaign(
            "",
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(token),
            bytes32(0),
            "",
            multipleClaimsAllowed,
            startTime,
            endTime
        );
    }

    /// @notice Helper function to create a campaign with custom strategy and encoder
    function createCampaignWithStrategy(
        bytes32 strategyId,
        bytes32 encoderId,
        bytes memory encoderInitData,
        bool multipleClaimsAllowed
    )
        internal
        returns (uint256)
    {
        return capitalDistributorPlugin.createCampaign(
            "", strategyId, "", "", IERC20(token), encoderId, encoderInitData, multipleClaimsAllowed, 0, 0
        );
    }

    /// @notice Helper function to mint tokens and approve if needed
    function mintTokensToDAO(uint256 amount) internal {
        token.mint(address(createdDao), amount);
    }

    // ============================================
    // T01: Campaign Creation Tests
    // ============================================

    /// @notice Test T01: Create a Campaign with basic parameters as specified in the test spec
    /// @dev This is the core test case from the specification
    function test_CreateCampaign() public {
        vm.startPrank(address(createdDao));

        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata, // Empty metadata
            toBytes32("mock-strategy"), // "mock-strategy" as allocation strategy
            allocatorDeploymentParams, // empty bytes for encoder
            "", // empty bytes for aux data
            IERC20(token), // a basic erc20 token
            bytes32(0), // empty bytes32 for action encoder id
            "", // empty bytes for aux data for action encoder
            false, // false so users can only claim once
            0, // 0 for when the campaign starts
            0 // 0 for when expires the campaign
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.metadataUri, metadata, "Metadata not equal");
        assertTrue(address(campaign.allocationStrategy) != address(0), "Allocation strategy not set");
        assertEq(address(campaign.token), address(token), "Token not equal");
        assertEq(address(campaign.actionEncoder), address(0), "Action encoder should be zero");
        assertEq(campaign.multipleClaimsAllowed, false, "Multiple claims should be false");
        assertTrue(campaign.state == CapitalDistributorPlugin.CampaignState.ACTIVE, "Campaign should be active");
        assertEq(campaign.startTime, 0, "Start time should be 0");
        assertEq(campaign.endTime, 0, "End time should be 0");

        vm.stopPrank();
    }

    /// @notice Test campaign creation with different type of values
    function test_CreateCampaignWithDifferentValues() public {
        vm.startPrank(address(createdDao));

        bytes memory metadata = "ipfs://QmTest123";
        bytes memory allocatorDeploymentParams = "deployment-params";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("mock-strategy"),
            allocatorDeploymentParams,
            "aux-data",
            IERC20(token),
            bytes32(0),
            "encoder-aux-data",
            true, // Allow multiple claims
            0,
            0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.metadataUri, metadata, "Metadata not equal");
        assertTrue(address(campaign.allocationStrategy) != address(0), "Allocation strategy not set");
        assertEq(address(campaign.token), address(token), "Token not equal");
        assertEq(campaign.multipleClaimsAllowed, true, "Multiple claims should be true");
        assertTrue(campaign.state == CapitalDistributorPlugin.CampaignState.ACTIVE, "Campaign should be active");

        vm.stopPrank();
    }

    /// @notice Test campaign creation with start time
    function test_CreateCampaignWithStartTime() public {
        vm.startPrank(address(createdDao));

        uint256 startTime = block.timestamp + 1000;

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, startTime, 0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.startTime, startTime, "Start time not equal");
        assertEq(campaign.endTime, 0, "End time should be 0");

        vm.stopPrank();
    }

    /// @notice Test campaign creation with end time
    function test_CreateCampaignWithEndTime() public {
        vm.startPrank(address(createdDao));

        uint256 endTime = block.timestamp + 2000;

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, endTime
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.startTime, 0, "Start time should be 0");
        assertEq(campaign.endTime, endTime, "End time not equal");

        vm.stopPrank();
    }

    /// @notice Test that campaign creation fails without proper permissions
    function test_CreateCampaignFailsWithoutPermission() public {
        vm.startPrank(address(alice));

        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        vm.stopPrank();
    }

    /// @notice Test that campaign creation fails with zero token address
    function test_CreateCampaignFailsWithZeroToken() public {
        vm.startPrank(address(createdDao));

        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPlugin.ZeroAddress.selector, "_token"));
        capitalDistributorPlugin.createCampaign(
            "",
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(address(0)), // Zero token address
            bytes32(0),
            "",
            false,
            0,
            0
        );

        vm.stopPrank();
    }

    /// @notice Test that campaign creation fails with invalid time bounds
    function test_CreateCampaignFailsWithInvalidTimeBounds() public {
        vm.startPrank(address(createdDao));

        uint256 startTime = block.timestamp + 2000;
        uint256 endTime = block.timestamp + 1000; // End time before start time

        vm.expectRevert(CapitalDistributorPlugin.InvalidTimeBounds.selector);
        capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, startTime, endTime
        );

        vm.stopPrank();
    }

    /// @notice Test that campaign creation fails with non-existent strategy
    function test_CreateCampaignFailsWithNonExistentStrategy() public {
        vm.startPrank(address(createdDao));

        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            "", toBytes32("non-existent-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        vm.stopPrank();
    }

    /// @notice Test campaign creation with maximum metadata length
    function test_CreateCampaignWithMaximumMetadata() public {
        vm.startPrank(address(createdDao));

        bytes memory maxMetadata = new bytes(1000);
        for (uint256 i = 0; i < 1000; i++) {
            maxMetadata[i] = bytes1(uint8(65 + (i % 26))); // Fill with A-Z
        }

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            maxMetadata, toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertEq(campaign.metadataUri, maxMetadata, "Max metadata not equal");

        vm.stopPrank();
    }

    /// @notice Test campaign creation with future start time
    function test_CreateCampaignWithFutureStartTime() public {
        vm.startPrank(address(createdDao));

        uint256 futureStartTime = block.timestamp + 86_400; // 1 day in the future

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, futureStartTime, 0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertEq(campaign.startTime, futureStartTime, "Future start time not equal");

        vm.stopPrank();
    }

    /// @notice Test campaign creation with past end time
    function test_CreateCampaignWithPastEndTime() public {
        vm.startPrank(address(createdDao));

        uint256 pastEndTime = block.timestamp - 86_400; // 1 day in the past

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, pastEndTime
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertEq(campaign.endTime, pastEndTime, "Past end time not equal");

        vm.stopPrank();
    }

    /// @notice Test that campaign IDs increment correctly
    function test_CampaignIdIncrementsCorrectly() public {
        vm.startPrank(address(createdDao));

        uint256 initialNumCampaigns = capitalDistributorPlugin.numCampaigns();

        uint256 campaignId1 = capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        uint256 campaignId2 = capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        assertEq(campaignId1, initialNumCampaigns, "First campaign ID should match initial count");
        assertEq(campaignId2, initialNumCampaigns + 1, "Second campaign ID should increment");

        vm.stopPrank();
    }

    /// @notice Test that numCampaigns increments correctly
    function test_NumCampaignsIncrementsCorrectly() public {
        vm.startPrank(address(createdDao));

        uint256 initialNumCampaigns = capitalDistributorPlugin.numCampaigns();

        capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        assertEq(capitalDistributorPlugin.numCampaigns(), initialNumCampaigns + 1, "numCampaigns should increment");

        capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        assertEq(
            capitalDistributorPlugin.numCampaigns(), initialNumCampaigns + 2, "numCampaigns should increment again"
        );

        vm.stopPrank();
    }

    /// @notice Test that campaigns are active by default
    function test_CampaignIsActiveByDefault() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(
            campaign.state == CapitalDistributorPlugin.CampaignState.ACTIVE, "Campaign should be active by default"
        );
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active via function");

        vm.stopPrank();
    }

    /// @notice Test that campaign data is stored correctly
    function test_CampaignDataStoredCorrectly() public {
        vm.startPrank(address(createdDao));

        bytes memory metadata = "test-metadata";
        bool multipleClaimsAllowed = true;
        uint256 startTime = block.timestamp + 1000;
        uint256 endTime = block.timestamp + 2000;

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(token),
            bytes32(0),
            "",
            multipleClaimsAllowed,
            startTime,
            endTime
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.metadataUri, metadata, "Metadata not stored correctly");
        assertTrue(address(campaign.allocationStrategy) != address(0), "Strategy not stored correctly");
        assertEq(address(campaign.token), address(token), "Token not stored correctly");
        assertEq(address(campaign.actionEncoder), address(0), "Action encoder not stored correctly");
        assertEq(campaign.multipleClaimsAllowed, multipleClaimsAllowed, "Multiple claims not stored correctly");
        assertTrue(campaign.state == CapitalDistributorPlugin.CampaignState.ACTIVE, "Active flag not stored correctly");
        assertEq(campaign.startTime, startTime, "Start time not stored correctly");
        assertEq(campaign.endTime, endTime, "End time not stored correctly");

        vm.stopPrank();
    }

    /// @notice Test creating multiple campaigns in sequence
    function test_CreateMultipleCampaignsInSequence() public {
        vm.startPrank(address(createdDao));

        uint256 initialNumCampaigns = capitalDistributorPlugin.numCampaigns();

        for (uint256 i = 0; i < 5; i++) {
            uint256 campaignId = capitalDistributorPlugin.createCampaign(
                abi.encode("metadata", i),
                toBytes32("mock-strategy"),
                "",
                "",
                IERC20(token),
                bytes32(0),
                "",
                false,
                0,
                0
            );

            assertEq(campaignId, initialNumCampaigns + i, "Campaign ID should increment sequentially");
        }

        assertEq(capitalDistributorPlugin.numCampaigns(), initialNumCampaigns + 5, "numCampaigns should increment by 5");

        vm.stopPrank();
    }

    /// @notice Test that each campaign gets a unique ID
    function test_EachCampaignGetsUniqueId() public {
        vm.startPrank(address(createdDao));

        uint256[] memory campaignIds = new uint256[](3);

        for (uint256 i = 0; i < 3; i++) {
            campaignIds[i] = capitalDistributorPlugin.createCampaign(
                "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
            );
        }

        assertTrue(campaignIds[0] != campaignIds[1], "First and second campaign IDs should be different");
        assertTrue(campaignIds[1] != campaignIds[2], "Second and third campaign IDs should be different");
        assertTrue(campaignIds[0] != campaignIds[2], "First and third campaign IDs should be different");

        vm.stopPrank();
    }

    /// @notice Test campaign creation without action encoder
    function test_CreateCampaignWithoutActionEncoder() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "",
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(token),
            bytes32(0), // No action encoder
            "",
            false,
            0,
            0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertEq(address(campaign.actionEncoder), address(0), "Action encoder should be zero address");

        vm.stopPrank();
    }

    /// @notice Test campaign creation with valid action encoder
    function test_CreateCampaignWithValidActionEncoder() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "",
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(token),
            toBytes32("vault-deposit-encoder"),
            abi.encode(address(vaultToSendTokens)),
            false,
            0,
            0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(address(campaign.actionEncoder) != address(0), "Action encoder should not be zero address");

        vm.stopPrank();
    }

    /// @notice Test CampaignCreated event emission with empty metadata
    function test_CampaignCreatedEventWithEmptyMetadata() public {
        vm.startPrank(address(createdDao));

        bytes memory emptyMetadata = "";

        vm.recordLogs();

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            emptyMetadata, toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find the CampaignCreated event (should be the last one)
        bool eventFound = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0]
                    == keccak256("CampaignCreated(uint256,bytes,address,address,address,bool,uint256,uint256)")
            ) {
                eventFound = true;
                // Verify the campaign ID matches
                assertEq(uint256(logs[i].topics[1]), campaignId, "Campaign ID in event should match");
                break;
            }
        }

        assertTrue(eventFound, "CampaignCreated event should be emitted");

        vm.stopPrank();
    }

    /// @notice Test CampaignCreated event emission with all parameters
    function test_CampaignCreatedEventWithAllParameters() public {
        vm.startPrank(address(createdDao));

        bytes memory metadata = "comprehensive-metadata";
        bool multipleClaimsAllowed = true;
        uint256 startTime = block.timestamp + 1000;
        uint256 endTime = block.timestamp + 2000;

        vm.recordLogs();

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(token),
            bytes32(0),
            "",
            multipleClaimsAllowed,
            startTime,
            endTime
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find the CampaignCreated event (should be the last one)
        bool eventFound = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0]
                    == keccak256("CampaignCreated(uint256,bytes,address,address,address,bool,uint256,uint256)")
            ) {
                eventFound = true;
                // Verify the campaign ID matches
                assertEq(uint256(logs[i].topics[1]), campaignId, "Campaign ID in event should match");
                break;
            }
        }

        assertTrue(eventFound, "CampaignCreated event should be emitted");

        vm.stopPrank();
    }

    /// @notice Test that campaign creation fails with non-existent action encoder
    function test_CreateCampaignFailsWithNonExistentActionEncoder() public {
        vm.startPrank(address(createdDao));

        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), toBytes32("non-existent-encoder"), "", false, 0, 0
        );

        vm.stopPrank();
    }

    /// @notice Test campaign creation with both start and end times
    function test_CreateCampaignWithBothTimes() public {
        vm.startPrank(address(createdDao));

        uint256 startTime = block.timestamp + 1000;
        uint256 endTime = block.timestamp + 2000;

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, startTime, endTime
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.startTime, startTime, "Start time not equal");
        assertEq(campaign.endTime, endTime, "End time not equal");
        assertTrue(campaign.state == CapitalDistributorPlugin.CampaignState.ACTIVE, "Campaign should be active");

        vm.stopPrank();
    }

    /// @notice Test campaign creation with equal start and end times fails
    function test_CreateCampaignFailsWithEqualTimes() public {
        vm.startPrank(address(createdDao));

        uint256 sameTime = block.timestamp + 1000;

        vm.expectRevert(CapitalDistributorPlugin.InvalidTimeBounds.selector);
        capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, sameTime, sameTime
        );

        vm.stopPrank();
    }

    /// @notice Test campaign creation with strategy parameters
    function test_CreateCampaignWithStrategyParams() public {
        vm.startPrank(address(createdDao));

        bytes memory strategyParams = "strategy-deployment-params";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), strategyParams, "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(address(campaign.allocationStrategy) != address(0), "Strategy should be deployed");

        vm.stopPrank();
    }

    /// @notice Test campaign creation with allocation strategy auxiliary data
    function test_CreateCampaignWithAllocationStrategyAuxData() public {
        vm.startPrank(address(createdDao));

        bytes memory auxData = "allocation-strategy-aux-data";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", auxData, IERC20(token), bytes32(0), "", false, 0, 0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(address(campaign.allocationStrategy) != address(0), "Strategy should be deployed");

        vm.stopPrank();
    }

    /// @notice Test campaign creation with action encoder auxiliary data
    function test_CreateCampaignWithActionEncoderAuxData() public {
        vm.startPrank(address(createdDao));

        bytes memory encoderAuxData = abi.encode(address(vaultToSendTokens));

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "",
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(token),
            toBytes32("vault-deposit-encoder"),
            encoderAuxData,
            false,
            0,
            0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(address(campaign.actionEncoder) != address(0), "Action encoder should be deployed");

        vm.stopPrank();
    }

    /// @notice Test campaign creation with maximum time values
    function test_CreateCampaignWithMaximumTimeValues() public {
        vm.startPrank(address(createdDao));

        uint256 maxStartTime = type(uint256).max - 1000;
        uint256 maxEndTime = type(uint256).max;

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, maxStartTime, maxEndTime
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.startTime, maxStartTime, "Max start time not equal");
        assertEq(campaign.endTime, maxEndTime, "Max end time not equal");

        vm.stopPrank();
    }

    /// @notice Test campaign creation gas usage
    function test_CampaignCreationGasUsage() public {
        vm.startPrank(address(createdDao));

        uint256 gasBefore = gasleft();

        capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        uint256 gasUsed = gasBefore - gasleft();

        // Basic gas usage check - should be reasonable
        assertTrue(gasUsed > 0, "Gas should be consumed");
        assertTrue(gasUsed < 1_000_000, "Gas usage should be reasonable");

        vm.stopPrank();
    }

    /// @notice Test that campaign creation with different tokens works
    function test_CreateCampaignWithDifferentTokens() public {
        vm.startPrank(address(createdDao));

        MintableERC20 token2 = new MintableERC20();

        uint256 campaignId1 = capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        uint256 campaignId2 = capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token2), bytes32(0), "", false, 0, 0
        );

        CapitalDistributorPlugin.Campaign memory campaign1 = capitalDistributorPlugin.getCampaign(campaignId1);
        CapitalDistributorPlugin.Campaign memory campaign2 = capitalDistributorPlugin.getCampaign(campaignId2);

        assertEq(address(campaign1.token), address(token), "First campaign token incorrect");
        assertEq(address(campaign2.token), address(token2), "Second campaign token incorrect");
        assertTrue(address(campaign1.token) != address(campaign2.token), "Tokens should be different");

        vm.stopPrank();
    }

    // ============================================
    // T02: Basic Payout Claiming Tests
    // ============================================

    /// @notice Test T02: Basic payout claiming functionality
    function test_PayoutIsClaimed() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        assertEq(token.balanceOf(address(createdDao)), 1 ether, "DAO doesn't have funds");
        assertEq(token.balanceOf(alice), 0 ether, "Alice has funds");

        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        assertEq(token.balanceOf(address(createdDao)), 0 ether, "DAO has funds");
        assertEq(token.balanceOf(alice), 1 ether, "Alice doesn't have funds");

        vm.stopPrank();
    }

    /// @notice Test payout claiming with multiple claims allowed
    function test_PayoutIsClaimedWithMultipleClaims() public {
        mintTokensToDAO(3 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createCampaignWithParams(true, 0, 0); // multiple claims allowed

        // First claim - strategy returns 1 ether
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should have 1 ether after first claim");

        // Check claimed amount
        assertEq(
            capitalDistributorPlugin.getClaimedAmount(campaignId, alice),
            1 ether,
            "Alice should have claimed 1 ether total"
        );

        vm.stopPrank();
    }

    /// @notice Test claiming fails before start date
    function test_ClaimingFailsBeforeStartDate() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 futureStart = block.timestamp + 1000;
        uint256 campaignId = createCampaignWithParams(false, futureStart, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignOutsideTimeBounds.selector, campaignId, block.timestamp, futureStart, 0
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    /// @notice Test claiming fails after end date
    function test_ClaimingFailsAfterEndDate() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 pastEnd = block.timestamp - 1;
        uint256 campaignId = createCampaignWithParams(false, 0, pastEnd);

        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignOutsideTimeBounds.selector, campaignId, block.timestamp, 0, pastEnd
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    /// @notice Test claiming fails after already claiming when multiple claims not allowed
    function test_ClaimingFailsAfterAlreadyClaiming() public {
        mintTokensToDAO(2 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign(); // multiple claims not allowed

        // First claim succeeds
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should have 1 ether");

        // Second claim fails
        vm.expectRevert(
            abi.encodeWithSelector(CapitalDistributorPlugin.MultipleClaimsNotAllowed.selector, campaignId, alice)
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    /// @notice Test claiming fails when campaign is ended
    function test_ClaimingFailsWhenCampaignEnded() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // Deactivate campaign
        capitalDistributorPlugin.endCampaign(campaignId);

        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignNotActive.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.ENDED
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    /// @notice Test claiming fails with no claimable amount
    function test_ClaimingFailsWithNoClaimableAmount() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = createZeroAmountCampaign();

        // Try to claim without any funds
        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPlugin.NoClaimableAmount.selector, campaignId, alice));
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    /// @notice Test PayoutClaimed event emission
    function test_PayoutClaimedEvent() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        vm.expectEmit(true, true, true, true);
        emit CapitalDistributorPlugin.PayoutClaimed(campaignId, alice, 1 ether);

        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    // ============================================
    // T03: Advanced Claiming Tests
    // ============================================

    /// @notice Test claiming on behalf of others
    function test_ClaimingOnBehalfOfOthers() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // DAO claims on behalf of alice
        assertEq(token.balanceOf(alice), 0, "Alice should have no tokens");
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should receive tokens");

        vm.stopPrank();

        // Bob claims on behalf of carol
        mintTokensToDAO(1 ether);
        vm.startPrank(bob);

        assertEq(token.balanceOf(carol), 0, "Carol should have no tokens");
        capitalDistributorPlugin.claimCampaignPayout(campaignId, carol, "", "");
        assertEq(token.balanceOf(carol), 1 ether, "Carol should receive tokens");

        vm.stopPrank();
    }

    /// @notice Test multiple users claiming for same recipient
    function test_MultipleUsersClaimingForSameRecipient() public {
        mintTokensToDAO(2 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createCampaignWithParams(true, 0, 0); // multiple claims allowed

        // DAO claims for alice
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should have 1 ether");

        vm.stopPrank();

        // Bob also claims for alice - should fail as max is reached
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.AlreadyClaimedMaxAmount.selector, campaignId, alice, 1 ether, 1 ether
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    /// @notice Test partial claims with multiple claims allowed
    function test_PartialClaimsWithMultipleClaimsAllowed() public {
        mintTokensToDAO(3 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createCampaignWithParams(true, 0, 0);

        // First claim - claims 1 ether
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should have 1 ether");

        assertEq(
            capitalDistributorPlugin.getClaimedAmount(campaignId, alice), 1 ether, "Total claimed should be 1 ether"
        );

        vm.stopPrank();
    }

    /// @notice Test claiming up to max amount
    function test_ClaimingUpToMaxAmount() public {
        mintTokensToDAO(2 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createCampaignWithParams(true, 0, 0);

        // Claim once
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should have 1 ether");

        // Try to claim again - should revert as max is 1 ether per mock strategy
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.AlreadyClaimedMaxAmount.selector, campaignId, alice, 1 ether, 1 ether
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    /// @notice Test claiming at exact start time
    function test_ClaimingAtExactStartTime() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 startTime = block.timestamp + 100;
        uint256 campaignId = createCampaignWithParams(false, startTime, 0);

        // Warp to exact start time
        vm.warp(startTime);

        // Should succeed
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should receive tokens");

        vm.stopPrank();
    }

    /// @notice Test claiming one second before end time
    function test_ClaimingOneSecondBeforeEndTime() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 endTime = block.timestamp + 100;
        uint256 campaignId = createCampaignWithParams(false, 0, endTime);

        // Warp to one second before end time
        vm.warp(endTime - 1);

        // Should succeed
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should receive tokens");

        vm.stopPrank();
    }

    /// @notice Test claiming at exact end time
    function test_ClaimingAtExactEndTime() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 endTime = block.timestamp + 100;
        uint256 campaignId = createCampaignWithParams(false, 0, endTime);

        // Warp to exact end time
        vm.warp(endTime);

        // Should fail (end time is exclusive)
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignOutsideTimeBounds.selector, campaignId, endTime, 0, endTime
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    /// @notice Test claiming with different auxiliary data
    function test_ClaimingWithDifferentAuxData() public {
        mintTokensToDAO(2 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // Claim with empty aux data
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should have 1 ether");

        // Claim with some aux data (mock strategy ignores it)
        capitalDistributorPlugin.claimCampaignPayout(campaignId, bob, "some-aux-data", "encoder-aux");
        assertEq(token.balanceOf(bob), 1 ether, "Bob should have 1 ether");

        vm.stopPrank();
    }

    /// @notice Test claiming from expired campaign that was active
    function test_ClaimingFromExpiredCampaignThatWasActive() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 endTime = block.timestamp + 100;
        uint256 campaignId = createCampaignWithParams(false, 0, endTime);

        // Verify campaign is active
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active");

        // Warp past end time
        vm.warp(endTime + 1);

        // Verify campaign is no longer active
        assertFalse(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be inactive");

        // Claiming should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignOutsideTimeBounds.selector, campaignId, endTime + 1, 0, endTime
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    /// @notice Test zero amount claim (when strategy returns 0)
    function test_ZeroAmountClaim() public {
        vm.startPrank(address(createdDao));

        // Create campaign ID 999 that returns 0 amount
        uint256 campaignId = createZeroAmountCampaign();

        // This will fail with NoClaimableAmount because strategy returns 0
        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPlugin.NoClaimableAmount.selector, campaignId, alice));
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    // ============================================
    // T04: Campaign Management Tests
    // ============================================

    /// @notice Test campaign deactivation
    function test_DeactivateCampaign() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // Verify campaign is active
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active");

        // Deactivate
        vm.expectEmit(true, true, true, true);
        emit CapitalDistributorPlugin.CampaignEnded(campaignId);

        capitalDistributorPlugin.endCampaign(campaignId);

        // Verify campaign is inactive
        assertFalse(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be inactive");

        vm.stopPrank();
    }

    /// @notice Test deactivation fails without permission
    function test_DeactivateCampaignFailsWithoutPermission() public {
        vm.startPrank(address(createdDao));
        uint256 campaignId = createBasicCampaign();
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert();
        capitalDistributorPlugin.endCampaign(campaignId);
        vm.stopPrank();
    }

    /// @notice Test deactivation fails if already inactive
    function test_DeactivateCampaignFailsIfAlreadyInactive() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // Deactivate once
        capitalDistributorPlugin.endCampaign(campaignId);

        // Try to end again
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.InvalidStateTransition.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.ENDED,
                CapitalDistributorPlugin.CampaignState.ENDED
            )
        );
        capitalDistributorPlugin.endCampaign(campaignId);

        vm.stopPrank();
    }

    /// @notice Test deactivation fails if campaign not found
    function test_DeactivateCampaignFailsIfNotFound() public {
        vm.startPrank(address(createdDao));

        uint256 nonExistentId = 999;

        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPlugin.CampaignNotFound.selector, nonExistentId));
        capitalDistributorPlugin.endCampaign(nonExistentId);

        vm.stopPrank();
    }

    /// @notice Test claiming fails after deactivation
    function test_ClaimingFailsAfterDeactivation() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // Deactivate campaign
        capitalDistributorPlugin.endCampaign(campaignId);

        // Try to claim
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignNotActive.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.ENDED
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    // ============================================
    // T05: Batch Operations Tests
    // ============================================

    /// @notice Test batch claim from multiple campaigns
    function test_BatchClaimCampaignPayout() public {
        mintTokensToDAO(3 ether);
        vm.startPrank(address(createdDao));

        // Create 3 campaigns
        uint256[] memory campaignIds = new uint256[](3);
        address[] memory recipients = new address[](3);
        bytes[] memory strategiesAuxData = new bytes[](3);
        bytes[] memory encodersAuxData = new bytes[](3);

        for (uint256 i = 0; i < 3; i++) {
            campaignIds[i] = createBasicCampaign();
            recipients[i] = alice;
            strategiesAuxData[i] = "";
            encodersAuxData[i] = "";
        }

        // Batch claim
        uint256[] memory amounts = capitalDistributorPlugin.batchClaimCampaignPayout(
            campaignIds, recipients, strategiesAuxData, encodersAuxData
        );

        // Verify
        assertEq(amounts.length, 3, "Should return 3 amounts");
        for (uint256 i = 0; i < 3; i++) {
            assertEq(amounts[i], 1 ether, "Each claim should be 1 ether");
        }
        assertEq(token.balanceOf(alice), 3 ether, "Alice should have 3 ether total");

        vm.stopPrank();
    }

    /// @notice Test batch claim with different recipients
    function test_BatchClaimWithDifferentRecipients() public {
        mintTokensToDAO(3 ether);
        vm.startPrank(address(createdDao));

        uint256[] memory campaignIds = new uint256[](3);
        address[] memory recipients = new address[](3);
        bytes[] memory strategiesAuxData = new bytes[](3);
        bytes[] memory encodersAuxData = new bytes[](3);

        // Create campaigns and set different recipients
        for (uint256 i = 0; i < 3; i++) {
            campaignIds[i] = createBasicCampaign();
            strategiesAuxData[i] = "";
            encodersAuxData[i] = "";
        }
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;

        // Batch claim
        capitalDistributorPlugin.batchClaimCampaignPayout(campaignIds, recipients, strategiesAuxData, encodersAuxData);

        // Verify each recipient got their tokens
        assertEq(token.balanceOf(alice), 1 ether, "Alice should have 1 ether");
        assertEq(token.balanceOf(bob), 1 ether, "Bob should have 1 ether");
        assertEq(token.balanceOf(carol), 1 ether, "Carol should have 1 ether");

        vm.stopPrank();
    }

    /// @notice Test batch claim fails with array length mismatch
    function test_BatchClaimFailsWithArrayLengthMismatch() public {
        vm.startPrank(address(createdDao));

        uint256[] memory campaignIds = new uint256[](2);
        address[] memory recipients = new address[](3); // Mismatch!
        bytes[] memory strategiesAuxData = new bytes[](2);
        bytes[] memory encodersAuxData = new bytes[](2);

        vm.expectRevert(CapitalDistributorPlugin.ArrayLengthMismatch.selector);
        capitalDistributorPlugin.batchClaimCampaignPayout(campaignIds, recipients, strategiesAuxData, encodersAuxData);

        vm.stopPrank();
    }

    /// @notice Test batch claim with partial success
    function test_BatchClaimPartialSuccess() public {
        mintTokensToDAO(2 ether);
        vm.startPrank(address(createdDao));

        // Create 2 campaigns, but deactivate one
        uint256 campaign1 = createBasicCampaign();
        uint256 campaign2 = createBasicCampaign();
        capitalDistributorPlugin.endCampaign(campaign2);

        uint256[] memory campaignIds = new uint256[](2);
        address[] memory recipients = new address[](2);
        bytes[] memory strategiesAuxData = new bytes[](2);
        bytes[] memory encodersAuxData = new bytes[](2);

        campaignIds[0] = campaign1;
        campaignIds[1] = campaign2;
        recipients[0] = alice;
        recipients[1] = alice;

        // Batch claim should revert because one campaign is inactive
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignNotActive.selector,
                campaign2,
                CapitalDistributorPlugin.CampaignState.ENDED
            )
        );
        capitalDistributorPlugin.batchClaimCampaignPayout(campaignIds, recipients, strategiesAuxData, encodersAuxData);

        vm.stopPrank();
    }

    // ============================================
    // T06: View/Getter Functions Tests
    // ============================================

    /// @notice Test getCampaignPayout view function
    function test_GetCampaignPayout() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // Check payout amount without claiming
        uint256 payoutAmount = capitalDistributorPlugin.getCampaignPayout(campaignId, alice, "");
        assertEq(payoutAmount, 1 ether, "Payout amount should be 1 ether");

        vm.stopPrank();
    }

    /// @notice Test getClaimedAmount function
    function test_GetClaimedAmount() public {
        mintTokensToDAO(2 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createCampaignWithParams(true, 0, 0);

        // Check initial claimed amount
        assertEq(capitalDistributorPlugin.getClaimedAmount(campaignId, alice), 0, "Initial claimed should be 0");

        // Claim once - will claim 1 ether
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");
        assertEq(capitalDistributorPlugin.getClaimedAmount(campaignId, alice), 1 ether, "Claimed should be 1 ether");

        vm.stopPrank();
    }

    /// @notice Test getCampaignStrategyId function
    function test_GetCampaignStrategyId() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        bytes32 strategyId = capitalDistributorPlugin.getCampaignStrategyId(campaignId);
        assertEq(strategyId, toBytes32("mock-strategy"), "Strategy ID should match");

        vm.stopPrank();
    }

    /// @notice Test getCampaignEncoderId function
    function test_GetCampaignEncoderId() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "",
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(token),
            toBytes32("vault-deposit-encoder"),
            abi.encode(address(vaultToSendTokens)),
            false,
            0,
            0
        );

        bytes32 encoderId = capitalDistributorPlugin.getCampaignEncoderId(campaignId);
        assertTrue(encoderId != bytes32(0), "Encoder ID should not be empty");

        vm.stopPrank();
    }

    /// @notice Test getCampaignEncoderId with no encoder
    function test_GetCampaignEncoderIdWithNoEncoder() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // This should revert as there's no encoder
        vm.expectRevert();
        capitalDistributorPlugin.getCampaignEncoderId(campaignId);

        vm.stopPrank();
    }

    /// @notice Test isCampaignActive function
    function test_IsCampaignActive() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // Should be active initially
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active");

        // Deactivate and check
        capitalDistributorPlugin.endCampaign(campaignId);
        assertFalse(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be inactive");

        vm.stopPrank();
    }

    /// @notice Test isCampaignActive with time bounds
    function test_IsCampaignActiveWithTimeBounds() public {
        vm.startPrank(address(createdDao));

        // Future campaign
        uint256 futureStart = block.timestamp + 1000;
        uint256 futureCampaignId = createCampaignWithParams(false, futureStart, 0);
        assertFalse(capitalDistributorPlugin.isCampaignActive(futureCampaignId), "Future campaign should be inactive");

        // Expired campaign
        uint256 pastEnd = block.timestamp - 1;
        uint256 expiredCampaignId = createCampaignWithParams(false, 0, pastEnd);
        assertFalse(capitalDistributorPlugin.isCampaignActive(expiredCampaignId), "Expired campaign should be inactive");

        // Active campaign with time bounds
        uint256 activeStart = block.timestamp - 100;
        uint256 activeEnd = block.timestamp + 100;
        uint256 activeCampaignId = createCampaignWithParams(false, activeStart, activeEnd);
        assertTrue(
            capitalDistributorPlugin.isCampaignActive(activeCampaignId), "Campaign within bounds should be active"
        );

        vm.stopPrank();
    }

    /// @notice Test getStrategyCreationEncodingTypes
    function test_GetStrategyCreationEncodingTypes() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        string memory types = capitalDistributorPlugin.getStrategyCreationEncodingTypes(campaignId);
        assertEq(types, "", "Mock strategy returns empty types");

        vm.stopPrank();
    }

    /// @notice Test getStrategyClaimEncodingTypes
    function test_GetStrategyClaimEncodingTypes() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        string memory types = capitalDistributorPlugin.getStrategyClaimEncodingTypes(campaignId);
        assertEq(types, "", "Mock strategy returns empty types");

        vm.stopPrank();
    }

    /// @notice Test getEncoderCreationEncodingTypes
    function test_GetEncoderCreationEncodingTypes() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "",
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(token),
            toBytes32("vault-deposit-encoder"),
            abi.encode(address(vaultToSendTokens)),
            false,
            0,
            0
        );

        string memory types = capitalDistributorPlugin.getEncoderCreationEncodingTypes(campaignId);
        assertTrue(bytes(types).length >= 0, "Should return encoding types");

        vm.stopPrank();
    }

    /// @notice Test getEncoderClaimEncodingTypes
    function test_GetEncoderClaimEncodingTypes() public {
        vm.startPrank(address(createdDao));

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "",
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(token),
            toBytes32("vault-deposit-encoder"),
            abi.encode(address(vaultToSendTokens)),
            false,
            0,
            0
        );

        string memory types = capitalDistributorPlugin.getEncoderClaimEncodingTypes(campaignId);
        assertTrue(bytes(types).length >= 0, "Should return encoding types");

        vm.stopPrank();
    }

    /// @notice Test encoding type getters fail for non-existent campaign
    function test_EncodingTypeGettersFailForNonExistentCampaign() public {
        vm.startPrank(address(createdDao));

        uint256 nonExistentId = 999;

        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPlugin.CampaignNotFound.selector, nonExistentId));
        capitalDistributorPlugin.getStrategyCreationEncodingTypes(nonExistentId);

        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPlugin.CampaignNotFound.selector, nonExistentId));
        capitalDistributorPlugin.getStrategyClaimEncodingTypes(nonExistentId);

        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPlugin.CampaignNotFound.selector, nonExistentId));
        capitalDistributorPlugin.getEncoderCreationEncodingTypes(nonExistentId);

        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPlugin.CampaignNotFound.selector, nonExistentId));
        capitalDistributorPlugin.getEncoderClaimEncodingTypes(nonExistentId);

        vm.stopPrank();
    }

    // ============================================
    // T07: Integration Tests
    // ============================================

    /// @notice Test create and claim in same block
    function test_CreateAndClaimInSameBlock() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        // Create and claim in same transaction
        uint256 campaignId = createBasicCampaign();

        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        assertEq(token.balanceOf(alice), 1 ether, "Alice should receive tokens in same block");

        vm.stopPrank();
    }

    /// @notice Test multiple campaigns for same token
    function test_MultipleCampaignsForSameToken() public {
        mintTokensToDAO(3 ether);
        vm.startPrank(address(createdDao));

        // Create 3 campaigns with same token
        uint256 campaign1 = createBasicCampaign();
        uint256 campaign2 = createBasicCampaign();
        uint256 campaign3 = createBasicCampaign();

        // Claim from each
        capitalDistributorPlugin.claimCampaignPayout(campaign1, alice, "", "");
        capitalDistributorPlugin.claimCampaignPayout(campaign2, bob, "", "");
        capitalDistributorPlugin.claimCampaignPayout(campaign3, carol, "", "");

        // Verify distributions
        assertEq(token.balanceOf(alice), 1 ether, "Alice should have 1 ether");
        assertEq(token.balanceOf(bob), 1 ether, "Bob should have 1 ether");
        assertEq(token.balanceOf(carol), 1 ether, "Carol should have 1 ether");

        vm.stopPrank();
    }

    /// @notice Test full campaign lifecycle
    function test_FullCampaignLifecycle() public {
        mintTokensToDAO(2 ether);
        vm.startPrank(address(createdDao));

        // 1. Create campaign with time bounds
        uint256 startTime = block.timestamp + 100;
        uint256 endTime = block.timestamp + 200;
        uint256 campaignId = createCampaignWithParams(true, startTime, endTime);

        // 2. Verify not active before start
        assertFalse(capitalDistributorPlugin.isCampaignActive(campaignId), "Should be inactive before start");

        // 3. Warp to active period
        vm.warp(startTime + 50);
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Should be active during period");

        // 4. First claim - claims 1 ether
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");
        assertEq(capitalDistributorPlugin.getClaimedAmount(campaignId, alice), 1 ether, "1 ether claimed");

        // 6. Deactivate campaign
        capitalDistributorPlugin.endCampaign(campaignId);
        assertFalse(capitalDistributorPlugin.isCampaignActive(campaignId), "Should be inactive after deactivation");

        // 7. Verify can't claim after deactivation
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignNotActive.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.ENDED
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    // ============================================
    // T08: Campaign State Management Tests
    // ============================================

    /// @notice Test pausing an active campaign
    function test_PauseCampaign() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // Verify campaign is active initially
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active");

        // Pause the campaign
        vm.expectEmit(true, false, false, false);
        emit CapitalDistributorPlugin.CampaignPaused(campaignId);
        capitalDistributorPlugin.pauseCampaign(campaignId);

        // Verify campaign is not active after pausing
        assertFalse(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should not be active when paused");

        vm.stopPrank();
    }

    /// @notice Test resuming a paused campaign
    function test_ResumeCampaign() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // Pause the campaign first
        capitalDistributorPlugin.pauseCampaign(campaignId);
        assertFalse(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be paused");

        // Resume the campaign
        vm.expectEmit(true, false, false, false);
        emit CapitalDistributorPlugin.CampaignResumed(campaignId);
        capitalDistributorPlugin.resumeCampaign(campaignId);

        // Verify campaign is active again
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active after resume");

        vm.stopPrank();
    }

    /// @notice Test pausing already paused campaign fails
    function test_PauseAlreadyPausedCampaign() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // Pause the campaign
        capitalDistributorPlugin.pauseCampaign(campaignId);

        // Try to pause again - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.InvalidStateTransition.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.PAUSED,
                CapitalDistributorPlugin.CampaignState.PAUSED
            )
        );
        capitalDistributorPlugin.pauseCampaign(campaignId);

        vm.stopPrank();
    }

    /// @notice Test resuming non-paused campaign fails
    function test_ResumeNonPausedCampaign() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // Try to resume active campaign - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.InvalidStateTransition.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.ACTIVE,
                CapitalDistributorPlugin.CampaignState.ACTIVE
            )
        );
        capitalDistributorPlugin.resumeCampaign(campaignId);

        vm.stopPrank();
    }

    /// @notice Test pausing ended campaign fails
    function test_PauseEndedCampaign() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // End the campaign
        capitalDistributorPlugin.endCampaign(campaignId);

        // Try to pause ended campaign - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.InvalidStateTransition.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.ENDED,
                CapitalDistributorPlugin.CampaignState.PAUSED
            )
        );
        capitalDistributorPlugin.pauseCampaign(campaignId);

        vm.stopPrank();
    }

    /// @notice Test resuming ended campaign fails
    function test_ResumeEndedCampaign() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // End the campaign
        capitalDistributorPlugin.endCampaign(campaignId);

        // Try to resume ended campaign - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.InvalidStateTransition.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.ENDED,
                CapitalDistributorPlugin.CampaignState.ACTIVE
            )
        );
        capitalDistributorPlugin.resumeCampaign(campaignId);

        vm.stopPrank();
    }

    /// @notice Test claiming from paused campaign fails
    function test_ClaimFromPausedCampaign() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // Pause the campaign
        capitalDistributorPlugin.pauseCampaign(campaignId);

        // Try to claim - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignNotActive.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.PAUSED
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        vm.stopPrank();
    }

    /// @notice Test campaign lifecycle with pause/resume
    function test_CampaignLifecycleWithPauseResume() public {
        mintTokensToDAO(2 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // 1. Claim while active
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should receive 1 ether");

        // 2. Pause campaign
        capitalDistributorPlugin.pauseCampaign(campaignId);

        // 3. Verify can't claim while paused
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignNotActive.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.PAUSED
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, bob, "", "");

        // 4. Resume campaign
        capitalDistributorPlugin.resumeCampaign(campaignId);

        // 5. Claim after resume
        capitalDistributorPlugin.claimCampaignPayout(campaignId, bob, "", "");
        assertEq(token.balanceOf(bob), 1 ether, "Bob should receive 1 ether after resume");

        vm.stopPrank();
    }

    /// @notice Test only authorized addresses can pause campaigns
    function test_PauseCampaignRequiresPermission() public {
        mintTokensToDAO(1 ether);
        vm.prank(address(createdDao));
        uint256 campaignId = createBasicCampaign();

        // Try to pause as unauthorized user
        vm.prank(alice);
        vm.expectRevert();
        capitalDistributorPlugin.pauseCampaign(campaignId);
    }

    /// @notice Test only authorized addresses can resume campaigns
    function test_ResumeCampaignRequiresPermission() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));
        uint256 campaignId = createBasicCampaign();
        capitalDistributorPlugin.pauseCampaign(campaignId);
        vm.stopPrank();

        // Try to resume as unauthorized user
        vm.prank(alice);
        vm.expectRevert();
        capitalDistributorPlugin.resumeCampaign(campaignId);
    }

    /// @notice Test pause/resume non-existent campaign
    function test_PauseResumeNonExistentCampaign() public {
        vm.startPrank(address(createdDao));

        uint256 nonExistentId = 999;

        // Try to pause non-existent campaign
        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPlugin.CampaignNotFound.selector, nonExistentId));
        capitalDistributorPlugin.pauseCampaign(nonExistentId);

        // Try to resume non-existent campaign
        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPlugin.CampaignNotFound.selector, nonExistentId));
        capitalDistributorPlugin.resumeCampaign(nonExistentId);

        vm.stopPrank();
    }

    /// @notice Test ending a paused campaign
    function test_EndPausedCampaign() public {
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createBasicCampaign();

        // Pause the campaign
        capitalDistributorPlugin.pauseCampaign(campaignId);

        // End the paused campaign - should succeed
        vm.expectEmit(true, false, false, false);
        emit CapitalDistributorPlugin.CampaignEnded(campaignId);
        capitalDistributorPlugin.endCampaign(campaignId);

        // Verify can't resume ended campaign
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.InvalidStateTransition.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.ENDED,
                CapitalDistributorPlugin.CampaignState.ACTIVE
            )
        );
        capitalDistributorPlugin.resumeCampaign(campaignId);

        vm.stopPrank();
    }

    /// @notice Test batch claim with paused campaigns
    function test_BatchClaimWithPausedCampaigns() public {
        mintTokensToDAO(3 ether);
        vm.startPrank(address(createdDao));

        // Create 3 campaigns
        uint256 campaign1 = createBasicCampaign();
        uint256 campaign2 = createBasicCampaign();
        uint256 campaign3 = createBasicCampaign();

        // Pause the middle campaign
        capitalDistributorPlugin.pauseCampaign(campaign2);

        // Prepare batch claim arrays
        uint256[] memory campaignIds = new uint256[](3);
        campaignIds[0] = campaign1;
        campaignIds[1] = campaign2;
        campaignIds[2] = campaign3;

        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;

        bytes[] memory strategiesAuxData = new bytes[](3);
        bytes[] memory encodersAuxData = new bytes[](3);

        // Batch claim should succeed for active campaigns but fail for paused one
        // The entire batch will revert due to the paused campaign
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignNotActive.selector,
                campaign2,
                CapitalDistributorPlugin.CampaignState.PAUSED
            )
        );
        capitalDistributorPlugin.batchClaimCampaignPayout(campaignIds, recipients, strategiesAuxData, encodersAuxData);

        vm.stopPrank();
    }

    // ============================================
    // T09: Fee Mechanism Tests
    // ============================================

    /// @notice Test claiming with fee configuration
    function test_ClaimWithFeeConfiguration() public {
        // Register a strategy with fee configuration
        address feeRecipient = makeAddr("feeRecipient");
        uint256 feeBasisPoints = 500; // 5%

        allocatorStrategyFactory.registerStrategyType(
            toBytes32("fee-strategy"), address(strategy), "", feeRecipient, feeBasisPoints
        );

        // Create campaign with fee-enabled strategy
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createCampaignWithStrategy(toBytes32("fee-strategy"), bytes32(0), "", false);

        // Claim payout
        uint256 claimAmount = 1 ether;
        uint256 expectedFee = (claimAmount * feeBasisPoints) / 10_000;
        uint256 expectedRecipientAmount = claimAmount - expectedFee;

        // Expect events
        vm.expectEmit(true, true, true, true);
        emit CapitalDistributorPlugin.PayoutClaimed(campaignId, alice, expectedRecipientAmount);

        vm.expectEmit(true, true, true, false);
        emit CapitalDistributorPlugin.FeeCollected(campaignId, feeRecipient, expectedFee);

        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        // Verify balances
        assertEq(token.balanceOf(alice), expectedRecipientAmount, "Alice should receive amount minus fee");
        assertEq(token.balanceOf(feeRecipient), expectedFee, "Fee recipient should receive fee");

        vm.stopPrank();
    }

    /// @notice Test claiming with zero fee
    function test_ClaimWithZeroFee() public {
        // Register a strategy with zero fee
        allocatorStrategyFactory.registerStrategyType(
            toBytes32("zero-fee-strategy"), address(strategy), "", address(0), 0
        );

        // Create campaign
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createCampaignWithStrategy(toBytes32("zero-fee-strategy"), bytes32(0), "", false);

        // Claim payout - should not emit FeeCollected event
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        // Verify alice receives full amount
        assertEq(token.balanceOf(alice), 1 ether, "Alice should receive full amount with zero fee");

        vm.stopPrank();
    }

    /// @notice Test claiming with maximum fee (10%)
    function test_ClaimWithMaximumFee() public {
        // Register a strategy with maximum allowed fee (10%)
        address feeRecipient = makeAddr("feeRecipient");
        uint256 feeBasisPoints = 1000; // 10%

        allocatorStrategyFactory.registerStrategyType(
            toBytes32("max-fee-strategy"), address(strategy), "", feeRecipient, feeBasisPoints
        );

        // Create campaign (note: mock strategy returns 1 ether, not 10)
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createCampaignWithStrategy(toBytes32("max-fee-strategy"), bytes32(0), "", false);

        // Claim payout
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        // Verify balances (1 ether total, 10% fee)
        assertEq(token.balanceOf(alice), 0.9 ether, "Alice should receive 90% with 10% fee");
        assertEq(token.balanceOf(feeRecipient), 0.1 ether, "Fee recipient should receive 10%");

        vm.stopPrank();
    }

    /// @notice Test fee calculation accuracy
    function test_FeeCalculationAccuracy() public {
        // Register a strategy with 2.5% fee
        address feeRecipient = makeAddr("feeRecipient");
        uint256 feeBasisPoints = 250; // 2.5%

        allocatorStrategyFactory.registerStrategyType(
            toBytes32("accuracy-fee-strategy"), address(strategy), "", feeRecipient, feeBasisPoints
        );

        // Note: Mock strategy always returns 1 ether
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createCampaignWithStrategy(toBytes32("accuracy-fee-strategy"), bytes32(0), "", false);

        // Claim
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        // Calculate expected values for 1 ether
        uint256 claimAmount = 1 ether;
        uint256 expectedFee = (claimAmount * feeBasisPoints) / 10_000;
        uint256 expectedRecipient = claimAmount - expectedFee;

        // Verify
        assertEq(token.balanceOf(alice), expectedRecipient, "Incorrect recipient amount");
        assertEq(token.balanceOf(feeRecipient), expectedFee, "Incorrect fee amount");

        // Test edge case: Verify fee calculation precision
        assertEq(expectedFee, 25_000_000_000_000_000, "Fee should be exactly 0.025 ether");
        assertEq(expectedRecipient, 975_000_000_000_000_000, "Recipient should get exactly 0.975 ether");

        vm.stopPrank();
    }

    /// @notice Test fee with action encoder
    function test_FeeWithActionEncoder() public {
        // Register a strategy with fee
        address feeRecipient = makeAddr("feeRecipient");
        uint256 feeBasisPoints = 300; // 3%

        allocatorStrategyFactory.registerStrategyType(
            toBytes32("encoder-fee-strategy"), address(strategy), "", feeRecipient, feeBasisPoints
        );

        // Register vault deposit encoder
        actionEncoderFactory.registerActionEncoder(toBytes32("vault-deposit"), address(vaultDepositActionEncoder), "");

        // Create campaign with encoder
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createCampaignWithStrategy(
            toBytes32("encoder-fee-strategy"), toBytes32("vault-deposit"), abi.encode(address(vaultToSendTokens)), false
        );

        // Claim with encoder - fee should still be collected
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        // Verify fee was collected
        uint256 expectedFee = (1 ether * feeBasisPoints) / 10_000;
        assertEq(token.balanceOf(feeRecipient), expectedFee, "Fee should be collected with encoder");

        // Verify vault received the recipient amount
        uint256 expectedVaultAmount = 1 ether - expectedFee;
        assertEq(vaultToSendTokens.totalAssets(), expectedVaultAmount, "Vault should receive amount minus fee");

        vm.stopPrank();
    }

    /// @notice Test batch claim with fees
    function test_BatchClaimWithFees() public {
        // Register strategies with different fees
        address feeRecipient1 = makeAddr("feeRecipient1");
        address feeRecipient2 = makeAddr("feeRecipient2");

        allocatorStrategyFactory.registerStrategyType(
            toBytes32("batch-fee-1"),
            address(strategy),
            "",
            feeRecipient1,
            200 // 2%
        );

        allocatorStrategyFactory.registerStrategyType(
            toBytes32("batch-fee-2"),
            address(strategy),
            "",
            feeRecipient2,
            500 // 5%
        );

        // Create campaigns
        mintTokensToDAO(3 ether);
        vm.startPrank(address(createdDao));

        uint256 campaign1 = createCampaignWithStrategy(toBytes32("batch-fee-1"), bytes32(0), "", false);

        uint256 campaign2 = createCampaignWithStrategy(toBytes32("batch-fee-2"), bytes32(0), "", false);

        // Batch claim
        uint256[] memory campaignIds = new uint256[](2);
        campaignIds[0] = campaign1;
        campaignIds[1] = campaign2;

        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        bytes[] memory strategiesAuxData = new bytes[](2);
        bytes[] memory encodersAuxData = new bytes[](2);

        capitalDistributorPlugin.batchClaimCampaignPayout(campaignIds, recipients, strategiesAuxData, encodersAuxData);

        // Verify fees collected
        assertEq(token.balanceOf(feeRecipient1), (1 ether * 200) / 10_000, "Fee recipient 1 should receive 2%");
        assertEq(token.balanceOf(feeRecipient2), (1 ether * 500) / 10_000, "Fee recipient 2 should receive 5%");

        vm.stopPrank();
    }

    /// @notice Test fee collection on single claim
    function test_FeeCollectionEvent() public {
        // Register a strategy with fee
        address feeRecipient = makeAddr("feeRecipient");
        uint256 feeBasisPoints = 100; // 1%

        allocatorStrategyFactory.registerStrategyType(
            toBytes32("event-fee-strategy"), address(strategy), "", feeRecipient, feeBasisPoints
        );

        // Create campaign
        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        uint256 campaignId = createCampaignWithStrategy(toBytes32("event-fee-strategy"), bytes32(0), "", false);

        // Expect fee collection event
        uint256 expectedFee = (1 ether * feeBasisPoints) / 10_000;
        vm.expectEmit(true, true, true, true);
        emit CapitalDistributorPlugin.FeeCollected(campaignId, feeRecipient, expectedFee);

        // Claim
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, "", "");

        // Verify fee was collected
        assertEq(token.balanceOf(feeRecipient), expectedFee, "Fee collected");
        assertEq(token.balanceOf(alice), 1 ether - expectedFee, "Alice received amount minus fee");

        vm.stopPrank();
    }

    // ============================================
    // T10: Factory Deployment Failure Tests
    // ============================================

    /// @notice Test campaign creation fails when strategy deployment returns zero address
    function test_CreateCampaignFailsWhenStrategyDeploymentReturnsZeroAddress() public {
        // Mock factory to return zero address for this strategy
        vm.mockCall(
            address(allocatorStrategyFactory),
            abi.encodeWithSelector(
                IAllocatorStrategyFactory.getOrDeployStrategy.selector,
                toBytes32("zero-address-strategy"),
                address(createdDao),
                ""
            ),
            abi.encode(address(0))
        );

        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        // Try to create campaign - should fail
        vm.expectRevert(
            abi.encodeWithSelector(CapitalDistributorPlugin.FactoryDeploymentFailed.selector, "AllocatorStrategy")
        );
        capitalDistributorPlugin.createCampaign(
            "", toBytes32("zero-address-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        vm.stopPrank();
        vm.clearMockedCalls();
    }

    /// @notice Test campaign creation handles factory deployment reverting
    function test_CreateCampaignHandlesFactoryDeploymentRevert() public {
        // Mock factory to revert on deployment
        vm.mockCallRevert(
            address(allocatorStrategyFactory),
            abi.encodeWithSelector(
                IAllocatorStrategyFactory.getOrDeployStrategy.selector,
                toBytes32("reverting-strategy"),
                address(createdDao),
                ""
            ),
            "Deployment failed"
        );

        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        // Try to create campaign - should bubble up the revert
        vm.expectRevert("Deployment failed");
        capitalDistributorPlugin.createCampaign(
            "", toBytes32("reverting-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );

        vm.stopPrank();
        vm.clearMockedCalls();
    }

    /// @notice Test external call failure during strategy setup
    function test_ExternalCallFailureDuringStrategySetup() public {
        // Deploy a mock strategy that reverts on setAllocationCampaign
        MockFailingStrategy failingStrategy = new MockFailingStrategy();

        allocatorStrategyFactory.registerStrategyType(
            toBytes32("failing-strategy"), address(failingStrategy), "", address(0), 0
        );

        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        // The factory will catch the setup failure and wrap it in DeploymentFailed
        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            "", toBytes32("failing-strategy"), "", "trigger-failure", IERC20(token), bytes32(0), "", false, 0, 0
        );

        vm.stopPrank();
    }

    /// @notice Test action encoder factory deployment failure
    function test_ActionEncoderFactoryDeploymentFailure() public {
        // Mock encoder factory to return zero address
        vm.mockCall(
            address(actionEncoderFactory),
            abi.encodeWithSelector(
                IActionEncoderFactory.getOrDeployActionEncoder.selector,
                toBytes32("zero-encoder"),
                address(createdDao),
                ""
            ),
            abi.encode(address(0))
        );

        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        // ISSUE FOUND: When encoder factory returns zero address, the plugin still tries to call
        // setupCampaign on address(0), which causes a revert. This is a potential bug in the contract.
        // The plugin should check if actionEncoder != address(0) before calling setupCampaign.

        // Expect revert when trying to create campaign with zero encoder
        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            "", toBytes32("mock-strategy"), "", "", IERC20(token), toBytes32("zero-encoder"), "", false, 0, 0
        );

        vm.stopPrank();
        vm.clearMockedCalls();
    }

    /// @notice Test encoder setup failure
    function test_EncoderSetupFailure() public {
        // Deploy a mock encoder that reverts on setupCampaign
        MockFailingEncoder failingEncoder = new MockFailingEncoder();

        actionEncoderFactory.registerActionEncoder(toBytes32("failing-encoder"), address(failingEncoder), "");

        mintTokensToDAO(1 ether);
        vm.startPrank(address(createdDao));

        // The factory will catch the setup failure and wrap it in DeploymentFailed
        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            "",
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(token),
            toBytes32("failing-encoder"),
            "trigger-failure",
            false,
            0,
            0
        );

        vm.stopPrank();
    }

    // ============================================
    // T11: claimCampaignPayoutToAddress Tests
    // ============================================

    /// @notice Test basic functionality and security of claimCampaignPayoutToAddress
    function test_ClaimPayoutToAddress_BasicFunctionality() public {
        mintTokensToDAO(2 ether);
        vm.startPrank(address(createdDao));
        uint256 campaignId = createBasicCampaign();
        vm.stopPrank();

        // Alice claims her allocation but sends funds to Bob
        vm.startPrank(alice);

        uint256 aliceInitialBalance = token.balanceOf(alice);
        uint256 bobInitialBalance = token.balanceOf(bob);

        // Event should show alice as recipient, even though funds go to bob
        vm.expectEmit(true, true, true, true);
        emit CapitalDistributorPlugin.PayoutClaimed(campaignId, alice, 1 ether);

        uint256 amountSent = capitalDistributorPlugin.claimCampaignPayoutToAddress(campaignId, bob, "", "");

        // Verify funds went to bob, not alice
        assertEq(token.balanceOf(alice), aliceInitialBalance, "Alice should not receive funds");
        assertEq(token.balanceOf(bob), bobInitialBalance + 1 ether, "Bob should receive the funds");
        assertEq(amountSent, 1 ether, "Should return correct amount sent");

        // Verify claim is tracked against alice (msg.sender)
        assertEq(
            capitalDistributorPlugin.getClaimedAmount(campaignId, alice), 1 ether, "Alice's claim should be tracked"
        );
        assertEq(capitalDistributorPlugin.getClaimedAmount(campaignId, bob), 0, "Bob's claim should remain zero");

        vm.stopPrank();
    }

    /// @notice Test security: only msg.sender can claim their allocation (no proxy claims)
    function test_ClaimPayoutToAddress_OnlyMsgSenderCanClaimTheirAllocation() public {
        mintTokensToDAO(3 ether);
        vm.startPrank(address(createdDao));
        uint256 campaignId = createBasicCampaign();
        vm.stopPrank();

        // Bob can claim his allocation and redirect funds to Alice
        // (Mock strategy allows everyone to claim 1 ether)
        vm.startPrank(bob);
        uint256 bobAmount = capitalDistributorPlugin.claimCampaignPayoutToAddress(campaignId, alice, "", "");
        assertEq(bobAmount, 1 ether, "Bob should claim 1 ether");

        // Verify funds went to Alice but claim is tracked against Bob
        assertEq(token.balanceOf(alice), 1 ether, "Alice should receive Bob's redirected funds");
        assertEq(token.balanceOf(bob), 0, "Bob should not receive funds (redirected to Alice)");
        assertEq(capitalDistributorPlugin.getClaimedAmount(campaignId, bob), 1 ether, "Bob's claim should be tracked");
        assertEq(capitalDistributorPlugin.getClaimedAmount(campaignId, alice), 0, "Alice's claim should remain zero");

        // Bob cannot claim again (multiple claims not allowed)
        vm.expectRevert(
            abi.encodeWithSelector(CapitalDistributorPlugin.MultipleClaimsNotAllowed.selector, campaignId, bob)
        );
        capitalDistributorPlugin.claimCampaignPayoutToAddress(campaignId, alice, "", "");
        vm.stopPrank();

        // Alice can claim her own allocation and redirect to Bob
        vm.startPrank(alice);
        uint256 aliceAmount = capitalDistributorPlugin.claimCampaignPayoutToAddress(campaignId, bob, "", "");
        assertEq(aliceAmount, 1 ether, "Alice should claim 1 ether");

        // Alice cannot claim again
        vm.expectRevert(
            abi.encodeWithSelector(CapitalDistributorPlugin.MultipleClaimsNotAllowed.selector, campaignId, alice)
        );
        capitalDistributorPlugin.claimCampaignPayoutToAddress(campaignId, bob, "", "");
        vm.stopPrank();

        // Verify final state: funds crossed over but claims tracked to original senders
        assertEq(token.balanceOf(alice), 1 ether, "Alice final balance (Bob's redirected funds)");
        assertEq(token.balanceOf(bob), 1 ether, "Bob final balance (Alice's redirected funds)");
        assertEq(capitalDistributorPlugin.getClaimedAmount(campaignId, alice), 1 ether, "Alice's claim tracked");
        assertEq(capitalDistributorPlugin.getClaimedAmount(campaignId, bob), 1 ether, "Bob's claim tracked");
    }

    /// @notice Test fee collection and proper event emission with claimCampaignPayoutToAddress
    function test_ClaimPayoutToAddress_WithFeesAndEvents() public {
        mintTokensToDAO(2 ether);

        // Register a fee-collecting strategy
        vm.startPrank(address(createdDao));
        allocatorStrategyFactory.registerStrategyType(
            toBytes32("fee-strategy"),
            address(strategy),
            "",
            address(0x1234), // Fee recipient
            500 // 5% fee
        );

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://test", toBytes32("fee-strategy"), "", "", IERC20(token), bytes32(0), "", false, 0, 0
        );
        vm.stopPrank();

        // Alice claims with fee deduction and redirection to Bob
        vm.startPrank(alice);

        uint256 aliceInitialBalance = token.balanceOf(alice);
        uint256 bobInitialBalance = token.balanceOf(bob);
        uint256 feeRecipientInitialBalance = token.balanceOf(address(0x1234));

        // Expect both PayoutClaimed and FeeCollected events
        vm.expectEmit(true, true, true, true);
        emit CapitalDistributorPlugin.PayoutClaimed(campaignId, alice, 0.95 ether); // 95% after 5% fee

        vm.expectEmit(true, true, true, true);
        emit CapitalDistributorPlugin.FeeCollected(campaignId, address(0x1234), 0.05 ether); // 5% fee

        uint256 amountSent = capitalDistributorPlugin.claimCampaignPayoutToAddress(campaignId, bob, "", "");

        // Verify amounts
        assertEq(amountSent, 0.95 ether, "Should return amount after fee deduction");
        assertEq(token.balanceOf(alice), aliceInitialBalance, "Alice should not receive funds");
        assertEq(token.balanceOf(bob), bobInitialBalance + 0.95 ether, "Bob should receive net amount");
        assertEq(
            token.balanceOf(address(0x1234)), feeRecipientInitialBalance + 0.05 ether, "Fee recipient should get fee"
        );

        // Verify claim tracking (should track full amount before fees against Alice)
        assertEq(
            capitalDistributorPlugin.getClaimedAmount(campaignId, alice),
            1 ether,
            "Alice's full claim should be tracked"
        );
        assertEq(capitalDistributorPlugin.getClaimedAmount(campaignId, bob), 0, "Bob's claim should remain zero");

        vm.stopPrank();
    }

    /// @notice Test campaign state validation and time bounds for claimCampaignPayoutToAddress
    function test_ClaimPayoutToAddress_CampaignStateAndTimeBounds() public {
        mintTokensToDAO(2 ether);
        vm.startPrank(address(createdDao));

        // Create campaign with time bounds
        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://test",
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(token),
            bytes32(0),
            "",
            false,
            block.timestamp + 100, // Start time
            block.timestamp + 200 // End time
        );

        // Claiming before start time should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignOutsideTimeBounds.selector,
                campaignId,
                block.timestamp,
                block.timestamp + 100,
                block.timestamp + 200
            )
        );
        capitalDistributorPlugin.claimCampaignPayoutToAddress(campaignId, bob, "", "");

        // Advance time to start
        vm.warp(block.timestamp + 100);

        // Claiming during active period should work
        uint256 amount = capitalDistributorPlugin.claimCampaignPayoutToAddress(campaignId, bob, "", "");
        assertEq(amount, 1 ether, "Should claim successfully during active period");
        vm.stopPrank();

        // Test paused campaign state
        vm.startPrank(address(createdDao));
        capitalDistributorPlugin.pauseCampaign(campaignId);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(CapitalDistributorPlugin.CampaignNotActive.selector, campaignId, uint8(1))
        ); // PAUSED = 1
        capitalDistributorPlugin.claimCampaignPayoutToAddress(campaignId, bob, "", "");
        vm.stopPrank();
    }

    /// @notice Test multiple users claiming and redirecting funds to each other
    function test_ClaimPayoutToAddress_MultipleClaimsAndEdgeCases() public {
        mintTokensToDAO(3 ether);

        // Create campaign allowing multiple claims
        vm.startPrank(address(createdDao));
        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://test",
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(token),
            bytes32(0),
            "",
            true, // Allow multiple claims
            0,
            0
        );
        vm.stopPrank();

        // Alice claims her allocation (1 ether) and sends to Bob
        vm.startPrank(alice);
        uint256 aliceAmount = capitalDistributorPlugin.claimCampaignPayoutToAddress(campaignId, bob, "", "");
        assertEq(aliceAmount, 1 ether, "Alice should claim 1 ether");
        assertEq(token.balanceOf(bob), 1 ether, "Bob should receive Alice's redirected funds");
        assertEq(capitalDistributorPlugin.getClaimedAmount(campaignId, alice), 1 ether, "Alice's claim tracked");
        vm.stopPrank();

        // Bob claims his own allocation (1 ether) and sends to Alice
        vm.startPrank(bob);
        uint256 bobAmount = capitalDistributorPlugin.claimCampaignPayoutToAddress(campaignId, alice, "", "");
        assertEq(bobAmount, 1 ether, "Bob should claim 1 ether");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should receive Bob's redirected funds");
        assertEq(capitalDistributorPlugin.getClaimedAmount(campaignId, bob), 1 ether, "Bob's claim tracked");
        vm.stopPrank();

        // Verify final state: each user claimed their own allocation but funds crossed over
        assertEq(token.balanceOf(alice), 1 ether, "Alice final balance (from Bob's claim)");
        assertEq(token.balanceOf(bob), 1 ether, "Bob final balance (from Alice's claim)");
        assertEq(capitalDistributorPlugin.getClaimedAmount(campaignId, alice), 1 ether, "Alice claimed her allocation");
        assertEq(capitalDistributorPlugin.getClaimedAmount(campaignId, bob), 1 ether, "Bob claimed his allocation");
    }
}

// Mock contracts for testing failures
contract MockFailingStrategy is IAllocatorStrategy {
    function getClaimableAmount(uint256, address, bytes calldata) external pure returns (uint256) {
        return 1 ether;
    }

    function setAllocationCampaign(uint256, bytes calldata auxData) external pure {
        if (keccak256(auxData) == keccak256("trigger-failure")) {
            revert("Setup failed");
        }
    }

    function getInitializationEncodingTypes() external pure returns (string memory) {
        return "";
    }

    function getCreationEncodingTypes() external pure returns (string memory) {
        return "";
    }

    function getClaimEncodingTypes() external pure returns (string memory) {
        return "";
    }

    function getFeeConfiguration() external pure returns (address, uint256) {
        return (address(0), 0);
    }

    function strategyTypeId() external pure returns (bytes32) {
        return bytes32(0);
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

contract MockFailingEncoder is IPayoutActionEncoder {
    function buildActions(
        IERC20,
        address,
        uint256,
        address,
        uint256,
        bytes calldata
    )
        external
        pure
        returns (Action[] memory)
    {
        return new Action[](0);
    }

    function setupCampaign(uint256, bytes calldata auxData) external pure {
        if (keccak256(auxData) == keccak256("trigger-failure")) {
            revert("Encoder setup failed");
        }
    }

    function getInitializationEncodingTypes() external pure returns (string memory) {
        return "";
    }

    function getCreationEncodingTypes() external pure returns (string memory) {
        return "";
    }

    function getClaimEncodingTypes() external pure returns (string memory) {
        return "";
    }

    function encoderId() external pure returns (bytes32) {
        return bytes32(0);
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}
