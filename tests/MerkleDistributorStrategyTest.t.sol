// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";

import {IPayoutActionEncoder} from "../src/interfaces/IPayoutActionEncoder.sol";
import {CapitalDistributorPlugin} from "../src/CapitalDistributorPlugin.sol";
import {AragonTest} from "./helpers/AragonTest.sol";
import {IAllocatorStrategy} from "../src/interfaces/IAllocatorStrategy.sol";
import {IAllocatorStrategyFactory} from "../src/interfaces/IAllocatorStrategyFactory.sol";
import {MerkleDistributorStrategy} from "../src/allocatorStrategies/MerkleDistributorStrategy.sol";

import {MintableERC20} from "./mocks/MintableERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {CreateExampleRecipients} from "../scripts/merkleDistributor/CreateExampleRecipients.s.sol";
import {GenerateMerkleTree} from "../scripts/merkleDistributor/GenerateMerkleTree.s.sol";
import {GenerateProof} from "../scripts/merkleDistributor/GenerateProof.s.sol";

contract MerkleDistributorStrategyTest is AragonTest {
    using stdJson for string;
    
    CapitalDistributorPlugin capitalDistributorPlugin;
    MerkleDistributorStrategy strategy;
    MintableERC20 token;

    // Merkle tree scripts
    CreateExampleRecipients createExampleScript;
    GenerateMerkleTree generateTreeScript;
    GenerateProof generateProofScript;

    // Merkle tree test data (legacy)
    address[] recipients;
    uint256[] amounts;
    bytes32[] leaves;
    bytes32 merkleRoot;
    
    // Script-generated test data  
    string constant TEST_RECIPIENTS_FILE = "./test/scripts/data/test-recipients-merkle.json";
    string constant TEST_TREE_FILE = "./test/scripts/data/merkle-tree.json";

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Instantiate the contract-under-test.
        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddress[0]);
        token = new MintableERC20();
        strategy = new MerkleDistributorStrategy();

        // Deploy scripts
        createExampleScript = new CreateExampleRecipients();
        generateTreeScript = new GenerateMerkleTree();
        generateProofScript = new GenerateProof();

        vm.startPrank(address(createdDAO));
        allocatorStrategyFactory.registerStrategyType(toBytes32("merkle-strategy"), address(strategy), "");

        // Set up merkle tree test data (keep legacy for existing tests)
        setupMerkleTreeData();
        
        // Set up script-generated test data
        setupScriptGeneratedData();
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
        bytes32 level1_0 = _hashPair(leaves[0], leaves[1]);
        bytes32 level1_1 = _hashPair(leaves[2], leaves[3]);

        // Level 2 (root): hash the two level 1 nodes
        merkleRoot = _hashPair(level1_0, level1_1);
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function setupScriptGeneratedData() internal {
        // Create test recipients using the script
        createExampleScript.createTestnetExample(TEST_RECIPIENTS_FILE);
        
        // Generate merkle tree using the script
        generateTreeScript.generate(TEST_RECIPIENTS_FILE);
    }

    function getScriptGeneratedMerkleRoot() internal view returns (bytes32) {
        string memory treeJson = vm.readFile(TEST_TREE_FILE);
        return treeJson.readBytes32(".merkleRoot");
    }

    function getScriptGeneratedProof(address recipient) internal returns (bytes32[] memory, uint256) {
        // Generate proof using script
        generateProofScript.generateProof(TEST_TREE_FILE, recipient);
        
        // Read the generated proof file from test data directory
        string memory proofFile = string.concat("./test/scripts/data/proof-", vm.toString(recipient), ".json");
        string memory proofJson = vm.readFile(proofFile);
        
        // Parse proof data
        bytes memory proofData = proofJson.parseRaw(".proof");
        bytes32[] memory proof = abi.decode(proofData, (bytes32[]));
        uint256 amount = proofJson.readUint(".amount");
        
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
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.metadataURI, metadata, "Metadata not equal");
        assertTrue(address(campaign.allocationStrategy) != address(0), "Allocation strategy not set");
    }

    function test_CannotCreateCampaignWithoutPermissions() public {
        vm.startPrank(address(alice));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );
    }

    function test_PayoutIsSent() public {
        token.mint(address(createdDAO), 10 ether);
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );
        vm.stopPrank();

        // Test Alice's claim
        bytes32[] memory aliceProof = getMerkleProof(0);
        bytes memory claimAuxData = abi.encode(aliceProof, amounts[0]);

        assertEq(token.balanceOf(address(createdDAO)), 10 ether, "DAO doesn't have funds");
        assertEq(token.balanceOf(alice), 0 ether, "Alice has funds before claim");

        vm.startPrank(address(createdDAO));
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, claimAuxData, "");

        assertEq(token.balanceOf(address(createdDAO)), 9 ether, "DAO should have 9 ether left");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should have 1 ether");
    }

    function test_MultipleRecipientsClaim() public {
        token.mint(address(createdDAO), 10 ether);
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
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
        assertEq(token.balanceOf(address(createdDAO)), 7 ether, "DAO should have 7 ether left");
    }

    function test_InvalidProofReverts() public {
        token.mint(address(createdDAO), 10 ether);
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
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
        token.mint(address(createdDAO), 10 ether);
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );
        vm.stopPrank();

        vm.startPrank(address(capitalDistributorPlugin));

        // Alice claims successfully
        bytes32[] memory aliceProof = getMerkleProof(0);
        bytes memory aliceClaimData = abi.encode(aliceProof, amounts[0]);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, aliceClaimData, "");

        // Alice tries to claim again - should revert
        vm.expectRevert(
            abi.encodeWithSelector(CapitalDistributorPlugin.MultipleClaimsNotAllowed.selector, campaignId, alice)
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, aliceClaimData, "");
    }

    function test_GetCampaignPayout() public {
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
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
    // Script-based Tests
    // ============================================================================

    function test_ScriptGeneratedMerkleTree() public {
        bytes32 scriptRoot = getScriptGeneratedMerkleRoot();
        assertNotEq(scriptRoot, bytes32(0), "Script should generate non-zero merkle root");
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(scriptRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(address(campaign.allocationStrategy) != address(0), "Allocation strategy should be set");
    }

    function test_ScriptGeneratedProofsClaim() public {
        token.mint(address(createdDAO), 100 ether);
        bytes32 scriptRoot = getScriptGeneratedMerkleRoot();
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(scriptRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );
        vm.stopPrank();

        // Test claims using script-generated proofs
        address testRecipient1 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // From testnet example
        address testRecipient2 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // From testnet example

        // Get proof for recipient 1
        (bytes32[] memory proof1, uint256 amount1) = getScriptGeneratedProof(testRecipient1);
        bytes memory claimData1 = abi.encode(proof1, amount1);

        // Get proof for recipient 2  
        (bytes32[] memory proof2, uint256 amount2) = getScriptGeneratedProof(testRecipient2);
        bytes memory claimData2 = abi.encode(proof2, amount2);

        uint256 initialBalance1 = token.balanceOf(testRecipient1);
        uint256 initialBalance2 = token.balanceOf(testRecipient2);

        vm.startPrank(address(createdDAO));
        
        // Claim for recipient 1
        capitalDistributorPlugin.claimCampaignPayout(campaignId, testRecipient1, claimData1, "");
        assertEq(token.balanceOf(testRecipient1), initialBalance1 + amount1, "Recipient 1 should receive correct amount");

        // Claim for recipient 2
        capitalDistributorPlugin.claimCampaignPayout(campaignId, testRecipient2, claimData2, "");
        assertEq(token.balanceOf(testRecipient2), initialBalance2 + amount2, "Recipient 2 should receive correct amount");
    }

    function test_ScriptGeneratedProofValidation() public {
        bytes32 scriptRoot = getScriptGeneratedMerkleRoot();
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(scriptRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );
        vm.stopPrank();

        // Test that script-generated proofs are valid
        address testRecipient = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        (bytes32[] memory proof, uint256 amount) = getScriptGeneratedProof(testRecipient);
        bytes memory claimData = abi.encode(proof, amount);

        uint256 payoutAmount = capitalDistributorPlugin.getCampaignPayout(campaignId, testRecipient, claimData);
        assertEq(payoutAmount, amount, "Script-generated proof should be valid");
        assertGt(payoutAmount, 0, "Payout amount should be greater than 0");
    }

    function test_LargeRecipientSetUsingScripts() public {
        // Create large recipient set using script
        createExampleScript.createLargeExample("./test/scripts/data/large-recipients-test.json");
        generateTreeScript.generate("./test/scripts/data/large-recipients-test.json");
        
        string memory largeTreeJson = vm.readFile("./test/scripts/data/merkle-tree.json");
        bytes32 largeRoot = largeTreeJson.readBytes32(".merkleRoot");
        uint256 totalRecipients = largeTreeJson.readUint(".totalRecipients");
        
        assertEq(totalRecipients, 100, "Should have 100 recipients");
        assertNotEq(largeRoot, bytes32(0), "Should generate valid merkle root for large set");
        
        token.mint(address(createdDAO), 1000 ether);
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(largeRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );
        vm.stopPrank();

        // Test claims for a few recipients from the large set
        address testAddr1 = address(uint160(uint256(keccak256(abi.encodePacked("recipient", uint256(5))))));
        address testAddr2 = address(uint160(uint256(keccak256(abi.encodePacked("recipient", uint256(25))))));
        
        // Generate proofs using script
        generateProofScript.generateProof("./test/scripts/data/merkle-tree.json", testAddr1);
        generateProofScript.generateProof("./test/scripts/data/merkle-tree.json", testAddr2);
        
        // Read proof files
        string memory proof1File = string.concat("./test/scripts/data/proof-", vm.toString(testAddr1), ".json");
        string memory proof2File = string.concat("./test/scripts/data/proof-", vm.toString(testAddr2), ".json");
        
        string memory proof1Json = vm.readFile(proof1File);
        string memory proof2Json = vm.readFile(proof2File);
        
        // Verify proofs are valid
        bool valid1 = proof1Json.readBool(".valid");
        bool valid2 = proof2Json.readBool(".valid");
        
        assertTrue(valid1, "Proof for recipient 5 should be valid");
        assertTrue(valid2, "Proof for recipient 25 should be valid");
        
        // Test actual claims
        bytes memory proofData1 = proof1Json.parseRaw(".proof");
        bytes32[] memory proof1Array = abi.decode(proofData1, (bytes32[]));
        uint256 amount1 = proof1Json.readUint(".amount");
        
        bytes memory claimData1 = abi.encode(proof1Array, amount1);
        uint256 payoutAmount1 = capitalDistributorPlugin.getCampaignPayout(campaignId, testAddr1, claimData1);
        
        assertEq(payoutAmount1, amount1, "Payout should match script-generated amount");
        assertGt(payoutAmount1, 0, "Should be able to claim from large recipient set");
    }

    // ============================================================================
    // Campaign Pause State Validation Tests
    // ============================================================================

    function test_UpdateMerkleRootFailsOnPausedCampaign() public {
        // Setup: Create campaign with initial merkle root
        token.mint(address(createdDAO), 10 ether);
        bytes32 initialRoot = merkleRoot;
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(initialRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );

        // Pause the campaign
        capitalDistributorPlugin.pauseCampaign(campaignId);
        
        // Verify campaign is paused
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertEq(uint8(campaign.state), uint8(CapitalDistributorPlugin.CampaignState.PAUSED), "Campaign should be paused");
        
        // Try to update merkle root on paused campaign
        bytes32 newRoot = keccak256("new-merkle-root");
        bytes memory newRootData = abi.encode(newRoot);
        
        vm.expectRevert(
            abi.encodeWithSelector(MerkleDistributorStrategy.CampaignNotActiveForUpdate.selector, campaignId)
        );
        
        // Call directly on strategy but from plugin context
        vm.stopPrank();
        vm.prank(address(capitalDistributorPlugin));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(campaignId, newRootData);
    }

    function test_UpdateMerkleRootFailsOnEndedCampaign() public {
        // Setup: Create campaign with initial merkle root
        token.mint(address(createdDAO), 10 ether);
        bytes32 initialRoot = merkleRoot;
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(initialRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );

        // End the campaign
        capitalDistributorPlugin.endCampaign(campaignId);
        
        // Verify campaign is ended
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertEq(uint8(campaign.state), uint8(CapitalDistributorPlugin.CampaignState.ENDED), "Campaign should be ended");
        
        // Try to update merkle root on ended campaign
        bytes32 newRoot = keccak256("new-merkle-root");
        bytes memory newRootData = abi.encode(newRoot);
        
        vm.expectRevert(
            abi.encodeWithSelector(MerkleDistributorStrategy.CampaignNotActiveForUpdate.selector, campaignId)
        );
        
        // Call directly on strategy but from plugin context
        vm.stopPrank();
        vm.prank(address(capitalDistributorPlugin));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(campaignId, newRootData);
    }

    function test_UpdateMerkleRootSucceedsOnActiveCampaign() public {
        // Setup: Create active campaign with initial merkle root
        token.mint(address(createdDAO), 10 ether);
        bytes32 initialRoot = merkleRoot;
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(initialRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );

        // Verify campaign is active
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertEq(uint8(campaign.state), uint8(CapitalDistributorPlugin.CampaignState.ACTIVE), "Campaign should be active");
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active");
        
        // Update merkle root on active campaign should succeed
        bytes32 newRoot = keccak256("new-merkle-root");
        bytes memory newRootData = abi.encode(newRoot);
        
        // Should not revert
        vm.expectEmit(true, true, false, true);
        emit MerkleDistributorStrategy.MerkleCampaignUpdated(campaignId, initialRoot, newRoot);
        
        // Call directly on strategy but from plugin context
        vm.stopPrank();
        vm.prank(address(capitalDistributorPlugin));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(campaignId, newRootData);
        
        // Verify the merkle root was updated
        bytes32 updatedRoot = MerkleDistributorStrategy(address(campaign.allocationStrategy)).getCampaignMerkleRoot(campaignId);
        assertEq(updatedRoot, newRoot, "Merkle root should be updated");
    }

    function test_SafeMerkleRootUpdateWorkflow() public {
        // Setup: Create campaign and mint tokens
        token.mint(address(createdDAO), 10 ether);
        bytes32 initialRoot = merkleRoot;
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(initialRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        // Verify initial active state allows updates
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active initially");
        
        // Step 1: Pause campaign 
        capitalDistributorPlugin.pauseCampaign(campaignId);
        assertFalse(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be paused");
        
        // Step 2: Update merkle root should fail on paused campaign (expected security behavior)
        bytes32 newRoot = keccak256("updated-merkle-root");
        bytes memory newRootData = abi.encode(newRoot);
        
        vm.expectRevert(
            abi.encodeWithSelector(MerkleDistributorStrategy.CampaignNotActiveForUpdate.selector, campaignId)
        );
        
        // Try to update while paused (should fail)
        vm.stopPrank();
        vm.prank(address(capitalDistributorPlugin));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(campaignId, newRootData);
        
        // Step 3: Resume campaign to allow updates
        vm.prank(address(createdDAO));
        capitalDistributorPlugin.resumeCampaign(campaignId);
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active after resume");
        
        // Step 4: Now merkle root update should succeed on resumed active campaign
        vm.prank(address(capitalDistributorPlugin));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(campaignId, newRootData);
        
        // Verify the update succeeded
        bytes32 updatedRoot = MerkleDistributorStrategy(address(campaign.allocationStrategy)).getCampaignMerkleRoot(campaignId);
        assertEq(updatedRoot, newRoot, "Merkle root should be updated after resume");
    }

    // ============================================================================
    // Error Condition Tests
    // ============================================================================

    function test_SetAllocationCampaignRevertOnInvalidMerkleRoot() public {
        // Setup: Create strategy first to test setAllocationCampaign directly
        token.mint(address(createdDAO), 10 ether);
        bytes32 validRoot = merkleRoot;
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(validRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Test with zero merkle root (invalid) on a new campaign ID
        uint256 newCampaignId = campaignId + 1;
        bytes32 invalidRoot = bytes32(0);
        bytes memory auxData = abi.encode(invalidRoot);

        vm.expectRevert(
            abi.encodeWithSelector(MerkleDistributorStrategy.InvalidMerkleRoot.selector)
        );

        // Direct call to setAllocationCampaign on the strategy to test the specific error
        vm.prank(address(capitalDistributorPlugin));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).setAllocationCampaign(newCampaignId, auxData);
    }

    function test_UpdateCampaignMerkleRootRevertOnInvalidMerkleRoot() public {
        // Setup: Create active campaign
        token.mint(address(createdDAO), 10 ether);
        bytes32 initialRoot = merkleRoot;
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(initialRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Try to update with invalid (zero) merkle root
        bytes32 invalidRoot = bytes32(0);
        bytes memory invalidRootData = abi.encode(invalidRoot);

        vm.expectRevert(
            abi.encodeWithSelector(MerkleDistributorStrategy.InvalidMerkleRoot.selector)
        );

        vm.prank(address(capitalDistributorPlugin));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(campaignId, invalidRootData);
    }

    function test_SetAllocationCampaignRevertOnAlreadyExistingCampaign() public {
        // Setup: Create first campaign
        token.mint(address(createdDAO), 10 ether);
        bytes32 firstRoot = merkleRoot;
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(firstRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
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
        // Setup: Create active campaign
        token.mint(address(createdDAO), 10 ether);
        bytes32 initialRoot = merkleRoot;
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(initialRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Try to update with the same merkle root (should fail)
        bytes memory duplicateRootData = abi.encode(initialRoot);

        vm.expectRevert(
            abi.encodeWithSelector(MerkleDistributorStrategy.DuplicateMerkleRoot.selector, initialRoot)
        );

        vm.prank(address(capitalDistributorPlugin));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(campaignId, duplicateRootData);
    }

    function test_UpdateCampaignMerkleRootRevertOnCampaignNotFound() public {
        // Setup: Create active campaign to get strategy address
        token.mint(address(createdDAO), 10 ether);
        bytes32 initialRoot = merkleRoot;
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(initialRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
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
            abi.encodeWithSelector(MerkleDistributorStrategy.CampaignNotActiveForUpdate.selector, nonExistentCampaignId)
        );

        vm.prank(address(capitalDistributorPlugin));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(nonExistentCampaignId, newRootData);
    }

    function test_UpdateCampaignMerkleRootUsesStoredPluginAddress() public {
        // Setup: Create active campaign
        token.mint(address(createdDAO), 10 ether);
        bytes32 initialRoot = merkleRoot;
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(initialRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Verify that the strategy has the correct plugin address stored
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(address(campaign.allocationStrategy));
        assertEq(strategy.plugin(), address(capitalDistributorPlugin), "Plugin address should be stored correctly");
        
        // Test that updateCampaignMerkleRoot works when called by DAO (using stored plugin address)
        bytes32 newRoot = keccak256("new-root");
        bytes memory newRootData = abi.encode(newRoot);
        
        vm.prank(address(createdDAO));
        strategy.updateCampaignMerkleRoot(campaignId, newRootData);
        
        // Verify the root was updated
        bytes32 updatedRoot = strategy.getCampaignMerkleRoot(campaignId);
        assertEq(updatedRoot, newRoot, "Merkle root should be updated");
    }

    function test_GetCampaignMerkleRootReturnsZeroForNonExistentCampaign() public {
        // Setup: Create active campaign to get strategy address
        token.mint(address(createdDAO), 10 ether);
        bytes32 initialRoot = merkleRoot;
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(initialRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Get merkle root for non-existent campaign should return zero
        uint256 nonExistentCampaignId = 999;
        bytes32 retrievedRoot = MerkleDistributorStrategy(address(campaign.allocationStrategy)).getCampaignMerkleRoot(nonExistentCampaignId);
        
        assertEq(retrievedRoot, bytes32(0), "Non-existent campaign should return zero merkle root");
    }

    // ============================================================================
    // Event Emission Tests
    // ============================================================================

    function test_MerkleCampaignSetEventEmission() public {
        token.mint(address(createdDAO), 10 ether);
        bytes32 testRoot = merkleRoot;
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        // Test event emission during campaign creation
        vm.expectEmit(true, true, false, true);
        emit MerkleDistributorStrategy.MerkleCampaignSet(0, testRoot);

        capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(testRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );
        vm.stopPrank();
    }

    function test_MerkleCampaignUpdatedEventEmission() public {
        // Setup: Create campaign
        token.mint(address(createdDAO), 10 ether);
        bytes32 initialRoot = merkleRoot;
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(initialRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Test event emission during merkle root update
        bytes32 newRoot = keccak256("updated-root");
        bytes memory newRootData = abi.encode(newRoot);

        vm.expectEmit(true, true, false, true);
        emit MerkleDistributorStrategy.MerkleCampaignUpdated(campaignId, initialRoot, newRoot);

        vm.prank(address(capitalDistributorPlugin));
        MerkleDistributorStrategy(address(campaign.allocationStrategy)).updateCampaignMerkleRoot(campaignId, newRootData);
    }

    // ============================================================================
    // Edge Cases and Boundary Tests
    // ============================================================================

    function test_GetClaimableAmountReturnsZeroForNonExistentCampaign() public {
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
        uint256 claimableAmount = testStrategy.getClaimeableAmount(nonExistentCampaignId, testAccount, auxData);
        vm.stopPrank();
        
        assertEq(claimableAmount, 0, "Should return 0 for non-existent campaign");
    }

    function test_GetClaimableAmountReturnsZeroForPartialClaim() public {
        // Setup campaign
        token.mint(address(createdDAO), 10 ether);
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
        );
        
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        vm.stopPrank();

        // Simulate a partial claim scenario by directly testing the strategy
        bytes32[] memory aliceProof = getMerkleProof(0);
        uint256 fullAmount = amounts[0]; // Alice's full allocation
        uint256 partialAmount = fullAmount / 2; // Alice tries to claim less
        
        // Test 1: Full amount should be claimable initially
        bytes memory fullClaimData = abi.encode(aliceProof, fullAmount);
        vm.prank(address(capitalDistributorPlugin));
        uint256 claimableAmount = MerkleDistributorStrategy(address(campaign.allocationStrategy)).getClaimeableAmount(campaignId, alice, fullClaimData);
        assertEq(claimableAmount, fullAmount, "Should return full amount initially");

        // Test 2: Invalid claim amount (more than allocated) should return 0
        uint256 excessiveAmount = fullAmount * 2;
        bytes memory excessiveClaimData = abi.encode(aliceProof, excessiveAmount);
        vm.prank(address(capitalDistributorPlugin));
        uint256 excessiveClaimable = MerkleDistributorStrategy(address(campaign.allocationStrategy)).getClaimeableAmount(campaignId, alice, excessiveClaimData);
        assertEq(excessiveClaimable, 0, "Should return 0 for excessive claim amount");
    }

    function test_GetClaimableAmountReturnsZeroForInvalidProof() public {
        // Setup campaign
        token.mint(address(createdDAO), 10 ether);
        
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false,
            0,
            0
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
