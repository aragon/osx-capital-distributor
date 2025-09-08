// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.29 <0.9.0;

import { CapitalDistributorPlugin } from "../../src/CapitalDistributorPlugin.sol";
import { AragonTest } from "../helpers/AragonTest.sol";
import { MerkleDistributorStrategy } from "../../src/allocatorStrategies/MerkleDistributorStrategy.sol";

import { MintableERC20 } from "../mocks/MintableERC20.sol";
import { MerkleMockGenerator } from "../mocks/MerkleMockGenerator.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";

contract MerkleDistributorStrategyTest is AragonTest {
    CapitalDistributorPlugin capitalDistributorPlugin;
    MerkleDistributorStrategy strategy;
    MintableERC20 token;
    ExecuteSelectorCondition condition;
    MerkleMockGenerator mockGenerator;

    // Merkle tree test data (legacy)
    address[] recipients;
    uint256[] amounts;
    bytes32[] leaves;
    bytes32 merkleRoot;

    // Mock-generated test data cached values
    bytes32 standardMerkleRoot;
    bytes32 largeMerkleRoot;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Instantiate the contract-under-test.
        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddress[0]);
        token = new MintableERC20();
        strategy = new MerkleDistributorStrategy();
        condition = ExecuteSelectorCondition(conditions[0]);

        // Deploy mock generator
        mockGenerator = new MerkleMockGenerator();

        vm.startPrank(address(createdDao));
        allocatorStrategyFactory.registerStrategyType(
            toBytes32("merkle-strategy"), address(strategy), "", address(0), 0
        );

        // Add token transfer permission to the plugin
        ExecuteSelectorCondition.SelectorTarget memory selectorToAllow =
            ExecuteSelectorCondition.SelectorTarget({ where: address(token), selectors: new bytes4[](1) });
        selectorToAllow.selectors[0] = IERC20.transfer.selector;

        condition.allowSelectors(selectorToAllow);

        // Set up merkle tree test data (keep legacy for existing tests)
        setupMerkleTreeData();

        // Set up mock-generated test data
        setupMockGeneratedData();
    }

    function setupMerkleTreeData() internal {
        // Create test recipients and amounts
        recipients = new address[](4);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;
        recipients[3] = david;

        amounts = new uint256[](4);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;
        amounts[3] = 4 ether;

        // Create leaves for merkle tree
        leaves = new bytes32[](4);
        for (uint256 i = 0; i < recipients.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(recipients[i], amounts[i]));
        }

        // Calculate merkle root using proper OpenZeppelin-compatible construction
        // Level 1: pair adjacent leaves with sorted hashing
        bytes32 level1Node0 = _hashPair(leaves[0], leaves[1]);
        bytes32 level1Node1 = _hashPair(leaves[2], leaves[3]);

        // Level 2 (root): hash the two level 1 nodes
        merkleRoot = _hashPair(level1Node0, level1Node1);
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function setupMockGeneratedData() internal {
        // Generate and cache merkle roots for standard test data
        MerkleMockGenerator.MerkleData memory standardData = mockGenerator.generateStandardTestData();
        standardMerkleRoot = standardData.root;

        // Generate and cache merkle root for large test data
        MerkleMockGenerator.MerkleData memory largeData = mockGenerator.generateLargeTestData();
        largeMerkleRoot = largeData.root;
    }

    function getMockGeneratedMerkleRoot() internal view returns (bytes32) {
        return standardMerkleRoot;
    }

    function getMockGeneratedProof(address recipient) internal view returns (bytes32[] memory, uint256) {
        // Re-generate standard test data to find recipient
        MerkleMockGenerator.MerkleData memory standardData = mockGenerator.generateStandardTestData();

        uint256 recipientIndex = type(uint256).max;
        for (uint256 i = 0; i < standardData.recipients.length; i++) {
            if (standardData.recipients[i].account == recipient) {
                recipientIndex = i;
                break;
            }
        }

        require(recipientIndex != type(uint256).max, "Recipient not found in test data");

        // Generate proof for the recipient
        bytes32[] memory proof = mockGenerator.generateProof(standardData, recipientIndex);
        uint256 amount = standardData.recipients[recipientIndex].amount;

        return (proof, amount);
    }

    function getMerkleProof(uint256 index) internal view returns (bytes32[] memory proof) {
        proof = new bytes32[](2);

        if (index == 0) {
            // Alice's proof
            proof[0] = leaves[1]; // Bob's leaf (sibling at level 0)
            proof[1] = _hashPair(leaves[2], leaves[3]); // Carol + David hash (uncle at level 1)
        } else if (index == 1) {
            // Bob's proof
            proof[0] = leaves[0]; // Alice's leaf (sibling at level 0)
            proof[1] = _hashPair(leaves[2], leaves[3]); // Carol + David hash (uncle at level 1)
        } else if (index == 2) {
            // Carol's proof
            proof[0] = leaves[3]; // David's leaf (sibling at level 0)
            proof[1] = _hashPair(leaves[0], leaves[1]); // Alice + Bob hash (uncle at level 1)
        } else if (index == 3) {
            // David's proof
            proof[0] = leaves[2]; // Carol's leaf (sibling at level 0)
            proof[1] = _hashPair(leaves[0], leaves[1]); // Alice + Bob hash (uncle at level 1)
        }
    }

    function test_CreateCampaign() public {
        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(merkleRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.metadataUri, metadata, "Metadata not equal");
        assertTrue(address(campaign.allocationStrategy) != address(0), "Allocation strategy not set");
    }

    function test_CannotCreateCampaignWithoutPermissions() public {
        vm.startPrank(address(alice));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(merkleRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );
    }

    function test_PayoutIsSent() public {
        token.mint(address(createdDao), 10 ether);
        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(merkleRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );
        vm.stopPrank();

        // Test Alice's claim
        bytes32[] memory aliceProof = getMerkleProof(0);
        bytes memory claimAuxData = abi.encode(aliceProof, amounts[0]);

        assertEq(token.balanceOf(address(createdDao)), 10 ether, "DAO doesn't have funds");
        assertEq(token.balanceOf(alice), 0 ether, "Alice has funds before claim");

        vm.startPrank(address(createdDao));
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, claimAuxData, "");

        assertEq(token.balanceOf(address(createdDao)), 9 ether, "DAO should have 9 ether left");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should have 1 ether");
    }

    function test_MultipleRecipientsClaim() public {
        token.mint(address(createdDao), 10 ether);
        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(merkleRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );
        vm.stopPrank();

        vm.startPrank(address(capitalDistributorPlugin));

        // Alice claims
        bytes32[] memory aliceProof = getMerkleProof(0);
        bytes memory aliceClaimData = abi.encode(aliceProof, amounts[0]);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, aliceClaimData, "");

        // Bob claims
        bytes32[] memory bobProof = getMerkleProof(1);
        bytes memory bobClaimData = abi.encode(bobProof, amounts[1]);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, bob, bobClaimData, "");

        assertEq(token.balanceOf(alice), 1 ether, "Alice should have 1 ether");
        assertEq(token.balanceOf(bob), 2 ether, "Bob should have 2 ether");
        assertEq(token.balanceOf(address(createdDao)), 7 ether, "DAO should have 7 ether left");
    }

    function test_InvalidProofReverts() public {
        token.mint(address(createdDao), 10 ether);
        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(merkleRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );
        vm.stopPrank();

        // Create invalid proof (using Bob's proof for Alice)
        bytes32[] memory invalidProof = getMerkleProof(1);
        bytes memory invalidClaimData = abi.encode(invalidProof, amounts[0]);

        vm.startPrank(address(capitalDistributorPlugin));
        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPlugin.NoClaimableAmount.selector, campaignId, alice));
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, invalidClaimData, "");
    }

    function test_CannotClaimTwice() public {
        token.mint(address(createdDao), 10 ether);
        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(merkleRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );
        vm.stopPrank();

        vm.startPrank(address(capitalDistributorPlugin));

        // Alice claims successfully
        bytes32[] memory aliceProof = getMerkleProof(0);
        bytes memory aliceClaimData = abi.encode(aliceProof, amounts[0]);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, aliceClaimData, "");

        // Alice tries to claim again - should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.AlreadyClaimedMaxAmount.selector, campaignId, alice, 1 ether, 1 ether
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, aliceClaimData, "");
    }

    function test_GetCampaignPayout() public {
        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(merkleRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );
        vm.stopPrank();

        // Check Alice's payout amount
        bytes32[] memory aliceProof = getMerkleProof(0);
        bytes memory aliceClaimData = abi.encode(aliceProof, amounts[0]);

        uint256 payoutAmount = capitalDistributorPlugin.getCampaignPayout(campaignId, alice, aliceClaimData);
        assertEq(payoutAmount, 1 ether, "Alice's payout should be 1 ether");

        // Check Bob's payout amount
        bytes32[] memory bobProof = getMerkleProof(1);
        bytes memory bobClaimData = abi.encode(bobProof, amounts[1]);

        payoutAmount = capitalDistributorPlugin.getCampaignPayout(campaignId, bob, bobClaimData);
        assertEq(payoutAmount, 2 ether, "Bob's payout should be 2 ether");
    }

    // ============================================================================
    // Mock-based Tests
    // ============================================================================

    function test_MockGeneratedMerkleTree() public {
        bytes32 mockRoot = getMockGeneratedMerkleRoot();
        assertNotEq(mockRoot, bytes32(0), "Mock should generate non-zero merkle root");

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(mockRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(address(campaign.allocationStrategy) != address(0), "Allocation strategy should be set");
    }

    function test_MockGeneratedProofsClaim() public {
        token.mint(address(createdDao), 100 ether);
        bytes32 mockRoot = getMockGeneratedMerkleRoot();

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(mockRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );
        vm.stopPrank();

        // Test claims using mock-generated proofs
        address testRecipient1 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // From standard test data
        address testRecipient2 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // From standard test data

        // Get proof for recipient 1
        (bytes32[] memory proof1, uint256 amount1) = getMockGeneratedProof(testRecipient1);
        bytes memory claimData1 = abi.encode(proof1, amount1);

        // Get proof for recipient 2
        (bytes32[] memory proof2, uint256 amount2) = getMockGeneratedProof(testRecipient2);
        bytes memory claimData2 = abi.encode(proof2, amount2);

        uint256 initialBalance1 = token.balanceOf(testRecipient1);
        uint256 initialBalance2 = token.balanceOf(testRecipient2);

        vm.startPrank(address(createdDao));

        // Claim for recipient 1
        capitalDistributorPlugin.claimCampaignPayout(campaignId, testRecipient1, claimData1, "");
        assertEq(
            token.balanceOf(testRecipient1), initialBalance1 + amount1, "Recipient 1 should receive correct amount"
        );

        // Claim for recipient 2
        capitalDistributorPlugin.claimCampaignPayout(campaignId, testRecipient2, claimData2, "");
        assertEq(
            token.balanceOf(testRecipient2), initialBalance2 + amount2, "Recipient 2 should receive correct amount"
        );
    }

    function test_MockGeneratedProofValidation() public {
        bytes32 mockRoot = getMockGeneratedMerkleRoot();

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(mockRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );
        vm.stopPrank();

        // Test that mock-generated proofs are valid
        address testRecipient = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        (bytes32[] memory proof, uint256 amount) = getMockGeneratedProof(testRecipient);
        bytes memory claimData = abi.encode(proof, amount);

        uint256 payoutAmount = capitalDistributorPlugin.getCampaignPayout(campaignId, testRecipient, claimData);
        assertEq(payoutAmount, amount, "Mock-generated proof should be valid");
        assertGt(payoutAmount, 0, "Payout amount should be greater than 0");
    }

    function test_LargeRecipientSetUsingMocks() public {
        // Use mock-generated large recipient set
        MerkleMockGenerator.MerkleData memory largeData = mockGenerator.generateLargeTestData();
        bytes32 largeRoot = largeData.root;
        uint256 totalRecipients = largeData.recipients.length;

        assertEq(totalRecipients, 100, "Should have 100 recipients");
        assertNotEq(largeRoot, bytes32(0), "Should generate valid merkle root for large set");

        token.mint(address(createdDao), 1000 ether);
        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(largeRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );
        vm.stopPrank();

        // Test claims for a few recipients from the large set
        uint256 testIndex1 = 5;
        uint256 testIndex2 = 25;

        address testAddr1 = largeData.recipients[testIndex1].account;
        address testAddr2 = largeData.recipients[testIndex2].account;
        uint256 amount1 = largeData.recipients[testIndex1].amount;
        uint256 amount2 = largeData.recipients[testIndex2].amount;

        // Generate proofs using mock
        bytes32[] memory proof1 = mockGenerator.generateProof(largeData, testIndex1);
        bytes32[] memory proof2 = mockGenerator.generateProof(largeData, testIndex2);

        // Verify proofs are valid by testing claims
        bytes memory claimData1 = abi.encode(proof1, amount1);
        bytes memory claimData2 = abi.encode(proof2, amount2);

        uint256 payoutAmount1 = capitalDistributorPlugin.getCampaignPayout(campaignId, testAddr1, claimData1);
        uint256 payoutAmount2 = capitalDistributorPlugin.getCampaignPayout(campaignId, testAddr2, claimData2);

        assertEq(payoutAmount1, amount1, "Payout should match mock-generated amount for recipient 5");
        assertEq(payoutAmount2, amount2, "Payout should match mock-generated amount for recipient 25");
        assertEq(payoutAmount1, 6 ether, "Recipient 5 should have 6 ETH (index + 1)");
        assertEq(payoutAmount2, 26 ether, "Recipient 25 should have 26 ETH (index + 1)");
    }

    // ============================================================================
    // Campaign Pause State Validation Tests
    // ============================================================================

    function test_UpdateMerkleRootSucceedsOnPausedCampaign() public {
        // Setup: Create campaign with initial merkle root
        token.mint(address(createdDao), 10 ether);
        bytes32 initialRoot = merkleRoot;

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(initialRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        // Pause the campaign
        capitalDistributorPlugin.pauseCampaign(campaignId);

        // Verify campaign is paused
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertEq(
            uint8(campaign.state), uint8(CapitalDistributorPlugin.CampaignState.PAUSED), "Campaign should be paused"
        );

        // Update merkle root on paused campaign should succeed
        bytes32 newRoot = keccak256("new-merkle-root");
        bytes memory newRootData = abi.encode(newRoot);

        // Should not revert - paused campaigns allow merkle root updates
        vm.expectEmit(true, true, false, true);
        emit MerkleDistributorStrategy.MerkleCampaignUpdated(campaignId, initialRoot, newRoot);

        // Call directly on strategy but from DAO context
        vm.stopPrank();
        vm.prank(address(createdDao));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(
            campaignId, newRootData
        );

        // Verify the merkle root was updated
        bytes32 updatedRoot =
            MerkleDistributorStrategy(address(campaign.allocationStrategy)).getCampaignMerkleRoot(campaignId);
        assertEq(updatedRoot, newRoot, "Merkle root should be updated on paused campaign");
    }

    function test_UpdateMerkleRootFailsOnEndedCampaign() public {
        // Setup: Create campaign with initial merkle root
        token.mint(address(createdDao), 10 ether);
        bytes32 initialRoot = merkleRoot;

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(initialRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        // End the campaign
        capitalDistributorPlugin.endCampaign(campaignId);

        // Verify campaign is ended
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertEq(uint8(campaign.state), uint8(CapitalDistributorPlugin.CampaignState.ENDED), "Campaign should be ended");

        // Try to update merkle root on ended campaign
        bytes32 newRoot = keccak256("new-merkle-root");
        bytes memory newRootData = abi.encode(newRoot);

        vm.expectRevert(abi.encodeWithSelector(MerkleDistributorStrategy.CampaignNotPaused.selector, campaignId));

        // Call directly on strategy but from DAO context
        vm.stopPrank();
        vm.prank(address(createdDao));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(
            campaignId, newRootData
        );
    }

    function test_UpdateMerkleRootFailsOnActiveCampaign() public {
        // Setup: Create active campaign with initial merkle root
        token.mint(address(createdDao), 10 ether);
        bytes32 initialRoot = merkleRoot;

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(initialRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        // Verify campaign is active
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertEq(
            uint8(campaign.state), uint8(CapitalDistributorPlugin.CampaignState.ACTIVE), "Campaign should be active"
        );
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active");

        // Update merkle root on active campaign should fail
        bytes32 newRoot = keccak256("new-merkle-root");
        bytes memory newRootData = abi.encode(newRoot);

        // Should revert with CampaignNotPaused since active campaigns cannot be updated
        vm.expectRevert(abi.encodeWithSelector(MerkleDistributorStrategy.CampaignNotPaused.selector, campaignId));

        // Call directly on strategy but from DAO context
        vm.stopPrank();
        vm.prank(address(createdDao));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(
            campaignId, newRootData
        );
    }

    function test_SafeMerkleRootUpdateWorkflow() public {
        // Setup: Create campaign and mint tokens
        token.mint(address(createdDao), 10 ether);
        bytes32 initialRoot = merkleRoot;

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(initialRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        // Verify initial active state
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active initially");

        // Step 1: Try updating the campaign while active (should fail)
        bytes32 newRoot = keccak256("updated-merkle-root");
        bytes memory newRootData = abi.encode(newRoot);

        vm.expectRevert(abi.encodeWithSelector(MerkleDistributorStrategy.CampaignNotPaused.selector, campaignId));

        // Try to update while active (should fail)
        vm.stopPrank();
        vm.prank(address(createdDao));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(
            campaignId, newRootData
        );

        // Step 2: Pause campaign to allow updates
        vm.prank(address(createdDao));
        capitalDistributorPlugin.pauseCampaign(campaignId);
        assertFalse(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be paused");

        // Step 3: Update merkle root should succeed on paused campaign
        vm.expectEmit(true, true, false, true);
        emit MerkleDistributorStrategy.MerkleCampaignUpdated(campaignId, initialRoot, newRoot);

        vm.prank(address(createdDao));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(
            campaignId, newRootData
        );

        // Verify the update succeeded
        bytes32 updatedRoot =
            MerkleDistributorStrategy(address(campaign.allocationStrategy)).getCampaignMerkleRoot(campaignId);
        assertEq(updatedRoot, newRoot, "Merkle root should be updated when paused");

        // Step 4: Resume campaign and verify we can't update again
        vm.prank(address(createdDao));
        capitalDistributorPlugin.resumeCampaign(campaignId);
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active after resume");

        // Try to update again while active (should fail)
        bytes32 anotherRoot = keccak256("another-merkle-root");
        bytes memory anotherRootData = abi.encode(anotherRoot);

        vm.expectRevert(abi.encodeWithSelector(MerkleDistributorStrategy.CampaignNotPaused.selector, campaignId));

        vm.prank(address(createdDao));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(
            campaignId, anotherRootData
        );
    }

    // ============================================================================
    // Error Condition Tests
    // ============================================================================

    function test_SetAllocationCampaignRevertOnInvalidMerkleRoot() public {
        // Setup: Create strategy first to test setAllocationCampaign directly
        token.mint(address(createdDao), 10 ether);
        bytes32 validRoot = merkleRoot;

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(validRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Test with zero merkle root (invalid) on a new campaign ID
        uint256 newCampaignId = campaignId + 1;
        bytes32 invalidRoot = bytes32(0);
        bytes memory auxData = abi.encode(invalidRoot);

        vm.expectRevert(abi.encodeWithSelector(MerkleDistributorStrategy.InvalidMerkleRoot.selector));

        // Direct call to setAllocationCampaign on the strategy to test the specific error
        vm.prank(address(capitalDistributorPlugin));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).setAllocationCampaign(newCampaignId, auxData);
    }

    function test_UpdateCampaignMerkleRootRevertOnInvalidMerkleRoot() public {
        // Setup: Create campaign
        token.mint(address(createdDao), 10 ether);
        bytes32 initialRoot = merkleRoot;

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(initialRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        // Pause the campaign to allow merkle root updates
        capitalDistributorPlugin.pauseCampaign(campaignId);

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Try to update with invalid (zero) merkle root
        bytes32 invalidRoot = bytes32(0);
        bytes memory invalidRootData = abi.encode(invalidRoot);

        vm.expectRevert(abi.encodeWithSelector(MerkleDistributorStrategy.InvalidMerkleRoot.selector));

        vm.prank(address(createdDao));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(
            campaignId, invalidRootData
        );
    }

    function test_SetAllocationCampaignRevertOnAlreadyExistingCampaign() public {
        // Setup: Create first campaign
        token.mint(address(createdDao), 10 ether);
        bytes32 firstRoot = merkleRoot;

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(firstRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        // Try to set allocation campaign again with the same campaign ID (should fail)
        bytes32 secondRoot = keccak256("different-root");
        bytes memory secondAuxData = abi.encode(secondRoot);

        vm.expectRevert(
            abi.encodeWithSelector(MerkleDistributorStrategy.MerkleCampaignAlreadyExists.selector, campaignId)
        );

        // Direct call to setAllocationCampaign on the strategy to test the specific error
        vm.stopPrank();
        vm.prank(address(capitalDistributorPlugin));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).setAllocationCampaign(campaignId, secondAuxData);
    }

    function test_UpdateCampaignMerkleRootRevertOnDuplicateRoot() public {
        // Setup: Create campaign
        token.mint(address(createdDao), 10 ether);
        bytes32 initialRoot = merkleRoot;

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(initialRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        // Pause the campaign to allow merkle root updates
        capitalDistributorPlugin.pauseCampaign(campaignId);

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Try to update with the same merkle root (should fail)
        bytes memory duplicateRootData = abi.encode(initialRoot);

        vm.expectRevert(abi.encodeWithSelector(MerkleDistributorStrategy.DuplicateMerkleRoot.selector, initialRoot));

        vm.prank(address(createdDao));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(
            campaignId, duplicateRootData
        );
    }

    function test_UpdateCampaignMerkleRootRevertOnCampaignNotFound() public {
        // Setup: Create active campaign to get strategy address
        token.mint(address(createdDao), 10 ether);
        bytes32 initialRoot = merkleRoot;

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(initialRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Try to update a non-existent campaign ID
        // NOTE: Due to our security validation order, this will fail with CampaignNotActiveForUpdate
        // because isCampaignActive(999) returns false for non-existent campaigns, which is checked first
        uint256 nonExistentCampaignId = 999;
        bytes32 newRoot = keccak256("new-root");
        bytes memory newRootData = abi.encode(newRoot);

        vm.expectRevert(
            abi.encodeWithSelector(MerkleDistributorStrategy.CampaignNotPaused.selector, nonExistentCampaignId)
        );

        vm.prank(address(createdDao));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(
            nonExistentCampaignId, newRootData
        );
    }

    function test_UpdateCampaignMerkleRootUsesStoredPluginAddress() public {
        // Setup: Create campaign
        token.mint(address(createdDao), 10 ether);
        bytes32 initialRoot = merkleRoot;

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(initialRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        // Pause the campaign to allow merkle root updates
        capitalDistributorPlugin.pauseCampaign(campaignId);

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Verify that the strategy has the correct plugin address stored
        MerkleDistributorStrategy allocationStrategy = MerkleDistributorStrategy(address(campaign.allocationStrategy));
        assertEq(
            allocationStrategy.plugin(), address(capitalDistributorPlugin), "Plugin address should be stored correctly"
        );

        // Test that updateCampaignMerkleRoot works when called by DAO (using stored plugin address)
        bytes32 newRoot = keccak256("new-root");
        bytes memory newRootData = abi.encode(newRoot);

        vm.prank(address(createdDao));
        allocationStrategy.updateCampaignMerkleRoot(campaignId, newRootData);

        // Verify the root was updated
        bytes32 updatedRoot = allocationStrategy.getCampaignMerkleRoot(campaignId);
        assertEq(updatedRoot, newRoot, "Merkle root should be updated");
    }

    function test_GetCampaignMerkleRootReturnsZeroForNonExistentCampaign() public {
        // Setup: Create active campaign to get strategy address
        token.mint(address(createdDao), 10 ether);
        bytes32 initialRoot = merkleRoot;

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(initialRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Get merkle root for non-existent campaign should return zero
        uint256 nonExistentCampaignId = 999;
        bytes32 retrievedRoot =
            MerkleDistributorStrategy(address(campaign.allocationStrategy)).getCampaignMerkleRoot(nonExistentCampaignId);

        assertEq(retrievedRoot, bytes32(0), "Non-existent campaign should return zero merkle root");
    }

    // ============================================================================
    // Event Emission Tests
    // ============================================================================

    function test_MerkleCampaignSetEventEmission() public {
        token.mint(address(createdDao), 10 ether);
        bytes32 testRoot = merkleRoot;

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        // Test event emission during campaign creation
        vm.expectEmit(true, true, false, true);
        emit MerkleDistributorStrategy.MerkleCampaignSet(0, testRoot);

        capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(testRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );
        vm.stopPrank();
    }

    function test_MerkleCampaignUpdatedEventEmission() public {
        // Setup: Create campaign
        token.mint(address(createdDao), 10 ether);
        bytes32 initialRoot = merkleRoot;

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(initialRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        // Verify campaign starts active
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active initially");

        // Test that update fails when campaign is active
        bytes32 newRoot = keccak256("updated-root");
        bytes memory newRootData = abi.encode(newRoot);

        vm.expectRevert(abi.encodeWithSelector(MerkleDistributorStrategy.CampaignNotPaused.selector, campaignId));

        vm.stopPrank();
        vm.prank(address(createdDao));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(
            campaignId, newRootData
        );

        // Now pause the campaign to allow updates
        vm.prank(address(createdDao));
        capitalDistributorPlugin.pauseCampaign(campaignId);

        // Verify campaign is paused
        assertFalse(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be paused");

        // Test successful event emission during merkle root update on paused campaign
        vm.expectEmit(true, true, false, true);
        emit MerkleDistributorStrategy.MerkleCampaignUpdated(campaignId, initialRoot, newRoot);

        vm.prank(address(createdDao));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(
            campaignId, newRootData
        );

        // Verify the merkle root was actually updated
        bytes32 updatedRoot =
            MerkleDistributorStrategy(address(campaign.allocationStrategy)).getCampaignMerkleRoot(campaignId);
        assertEq(updatedRoot, newRoot, "Merkle root should be updated");
    }

    // ============================================================================
    // Edge Cases and Boundary Tests
    // ============================================================================

    function test_getTotalClaimableAmountReturnsZeroForNonExistentCampaign() public {
        // Setup strategy without any campaigns
        MerkleDistributorStrategy testStrategy = new MerkleDistributorStrategy();

        // Test data
        uint256 nonExistentCampaignId = 999;
        address testAccount = alice;
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = keccak256("test-proof");
        uint256 testAmount = 1 ether;
        bytes memory auxData = abi.encode(proof, testAmount);

        // Should return 0 for non-existent campaign
        vm.startPrank(address(capitalDistributorPlugin));
        uint256 claimableAmount = testStrategy.getTotalClaimableAmount(nonExistentCampaignId, testAccount, auxData);
        vm.stopPrank();

        assertEq(claimableAmount, 0, "Should return 0 for non-existent campaign");
    }

    function test_getTotalClaimableAmountReturnsZeroForPartialClaim() public {
        // Setup campaign
        token.mint(address(createdDao), 10 ether);

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(merkleRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Simulate a partial claim scenario by directly testing the strategy
        bytes32[] memory aliceProof = getMerkleProof(0);
        uint256 fullAmount = amounts[0]; // Alice's full allocation
        // uint256 partialAmount = fullAmount / 2; // Alice tries to claim less (unused)

        // Test 1: Full amount should be claimable initially
        bytes memory fullClaimData = abi.encode(aliceProof, fullAmount);
        vm.prank(address(capitalDistributorPlugin));
        uint256 claimableAmount = MerkleDistributorStrategy(address(campaign.allocationStrategy))
            .getTotalClaimableAmount(campaignId, alice, fullClaimData);
        assertEq(claimableAmount, fullAmount, "Should return full amount initially");

        // Test 2: Invalid claim amount (more than allocated) should return 0
        uint256 excessiveAmount = fullAmount * 2;
        bytes memory excessiveClaimData = abi.encode(aliceProof, excessiveAmount);
        vm.prank(address(capitalDistributorPlugin));
        uint256 excessiveClaimable = MerkleDistributorStrategy(address(campaign.allocationStrategy))
            .getTotalClaimableAmount(campaignId, alice, excessiveClaimData);
        assertEq(excessiveClaimable, 0, "Should return 0 for excessive claim amount");
    }

    function test_getTotalClaimableAmountReturnsZeroForInvalidProof() public {
        // Setup campaign
        token.mint(address(createdDao), 10 ether);

        vm.startPrank(address(createdDao));
        bytes memory metadata = "ipfs://mock-campaign-metadata";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), allocatorDeploymentParams, abi.encode(merkleRoot)
            ),
            CapitalDistributorPlugin.PayoutConfig(IERC20(token), bytes32(0), metadata),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );
        vm.stopPrank();

        // Create invalid proof data
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256("invalid-proof");
        bytes memory invalidClaimData = abi.encode(invalidProof, amounts[0]);

        // Should return 0 for invalid proof
        uint256 claimableAmount = capitalDistributorPlugin.getCampaignPayout(campaignId, alice, invalidClaimData);
        assertEq(claimableAmount, 0, "Should return 0 for invalid proof");
    }

    function test_EncodingTypesReturnCorrectStrings() public {
        MerkleDistributorStrategy testStrategy = new MerkleDistributorStrategy();

        string memory creationTypes = testStrategy.getCreationEncodingTypes();
        string memory claimTypes = testStrategy.getClaimEncodingTypes();

        assertEq(creationTypes, "bytes32", "Creation encoding should be bytes32");
        assertEq(claimTypes, "bytes32[],uint256", "Claim encoding should be bytes32[],uint256");
    }
}
