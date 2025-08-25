// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {MerkleDistributorStrategy} from "../../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import {CapitalDistributorPlugin} from "../../src/CapitalDistributorPlugin.sol";

/**
 * @title MerkleUtilsIntegrationTest
 * @notice End-to-end integration tests for merkle tree utilities with the actual contracts
 */
contract MerkleUtilsIntegrationTest is Test {
    using stdJson for string;

    MerkleDistributorStrategy public merkleStrategy;
    CapitalDistributorPlugin public plugin;
    
    string constant TEST_DATA_DIR = "test/scripts/data";
    string constant INTEGRATION_RECIPIENTS_FILE = "test/scripts/data/integration-recipients.json";
    string constant INTEGRATION_TREE_FILE = "test/scripts/data/integration-merkle-tree.json";

    address constant ALLOCATOR = address(0x1);
    address constant TEST_RECIPIENT_1 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant TEST_RECIPIENT_2 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant TEST_RECIPIENT_3 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    function setUp() external {
        // Create test data directory
        vm.createDir(TEST_DATA_DIR, true);
        
        // Deploy contracts (minimal setup for testing)
        merkleStrategy = new MerkleDistributorStrategy();
        
        // Create integration test data
        createIntegrationTestData();
    }

    function test_EndToEnd_GenerateTreeAndClaim() external {
        // Step 1: Generate merkle tree using script
        generateMerkleTreeWithScript();
        
        // Step 2: Parse generated tree data
        string memory treeJson = vm.readFile(INTEGRATION_TREE_FILE);
        bytes32 merkleRoot = treeJson.readBytes32(".merkleRoot");
        uint256 totalRecipients = treeJson.readUint(".totalRecipients");
        
        // Step 3: Setup allocation campaign with generated root
        bytes memory allocationStrategyAuxData = abi.encode(merkleRoot);
        
        // Mock the allocation setup (would normally be done by the plugin)
        vm.prank(ALLOCATOR);
        merkleStrategy.setAllocationCampaign(
            1, // campaignId
            allocationStrategyAuxData
        );
        
        // Step 4: Generate proofs for each recipient and test claims
        address[3] memory recipients = [TEST_RECIPIENT_1, TEST_RECIPIENT_2, TEST_RECIPIENT_3];
        uint256[3] memory amounts = [uint256(1e18), 2e18, 3e18];
        
        for (uint256 i = 0; i < recipients.length; i++) {
            // Generate proof using script
            generateProofWithScript(recipients[i]);
            
            // Read generated proof
            string memory proofFile = string.concat(
                "test/scripts/data/proof-", 
                vm.toString(recipients[i]), 
                ".json"
            );
            string memory proofJson = vm.readFile(proofFile);
            
            // Parse proof data
            bytes memory proofData = proofJson.parseRaw(".proof");
            bytes32[] memory proof = abi.decode(proofData, (bytes32[]));
            uint256 amount = proofJson.readUint(".amount");
            
            // Verify proof data matches expectations
            assertEq(amount, amounts[i], string.concat("Amount should match for recipient ", vm.toString(i)));
            
            // Test the claim with MerkleDistributorStrategy
            bytes memory claimData = abi.encode(proof, amount);
            
            uint256 claimableAmount = merkleStrategy.getClaimeableAmount(
                1, // campaignId
                recipients[i],
                claimData
            );
            
            assertEq(claimableAmount, amounts[i], string.concat("Claimable amount should match for recipient ", vm.toString(i)));
            
            // Verify the proof is valid according to the contract
            assertTrue(claimableAmount > 0, string.concat("Should be claimable for recipient ", vm.toString(i)));
        }
    }

    function test_Integration_ProofCompatibilityWithContract() external {
        // Generate merkle tree
        generateMerkleTreeWithScript();
        
        // Read tree data
        string memory treeJson = vm.readFile(INTEGRATION_TREE_FILE);
        bytes32 merkleRoot = treeJson.readBytes32(".merkleRoot");
        
        // Setup campaign
        bytes memory allocationStrategyAuxData = abi.encode(merkleRoot);
        vm.prank(ALLOCATOR);
        merkleStrategy.setAllocationCampaign(1, allocationStrategyAuxData);
        
        // Test each recipient
        address[3] memory recipients = [TEST_RECIPIENT_1, TEST_RECIPIENT_2, TEST_RECIPIENT_3];
        
        for (uint256 i = 0; i < recipients.length; i++) {
            // Generate proof
            generateProofWithScript(recipients[i]);
            
            // Read and parse proof
            string memory proofFile = string.concat(
                "test/scripts/data/proof-", 
                vm.toString(recipients[i]), 
                ".json"
            );
            string memory proofJson = vm.readFile(proofFile);
            
            bytes memory solidityCallData = proofJson.parseRaw(".solidityCallData");
            (bytes32[] memory merkleProof, uint256 amount) = abi.decode(solidityCallData, (bytes32[], uint256));
            
            // Test with contract
            bytes memory claimData = abi.encode(merkleProof, amount);
            uint256 claimableAmount = merkleStrategy.getClaimeableAmount(1, recipients[i], claimData);
            
            assertEq(claimableAmount, amount, string.concat("Contract should return correct amount for recipient ", vm.toString(i)));
        }
    }

    function test_Integration_InvalidProof_ShouldFail() external {
        // Generate valid merkle tree
        generateMerkleTreeWithScript();
        
        string memory treeJson = vm.readFile(INTEGRATION_TREE_FILE);
        bytes32 merkleRoot = treeJson.readBytes32(".merkleRoot");
        
        // Setup campaign
        bytes memory allocationStrategyAuxData = abi.encode(merkleRoot);
        vm.prank(ALLOCATOR);
        merkleStrategy.setAllocationCampaign(1, allocationStrategyAuxData);
        
        // Create invalid proof (empty proof array)
        bytes32[] memory invalidProof = new bytes32[](0);
        uint256 amount = 1e18;
        bytes memory invalidClaimData = abi.encode(invalidProof, amount);
        
        // Should return 0 for invalid proof
        uint256 claimableAmount = merkleStrategy.getClaimeableAmount(1, TEST_RECIPIENT_1, invalidClaimData);
        assertEq(claimableAmount, 0, "Invalid proof should return 0 claimable amount");
    }

    function test_Integration_WrongAmount_ShouldFail() external {
        // Generate merkle tree and proof for recipient 1
        generateMerkleTreeWithScript();
        generateProofWithScript(TEST_RECIPIENT_1);
        
        string memory treeJson = vm.readFile(INTEGRATION_TREE_FILE);
        bytes32 merkleRoot = treeJson.readBytes32(".merkleRoot");
        
        // Setup campaign
        bytes memory allocationStrategyAuxData = abi.encode(merkleRoot);
        vm.prank(ALLOCATOR);
        merkleStrategy.setAllocationCampaign(1, allocationStrategyAuxData);
        
        // Read valid proof but use wrong amount
        string memory proofFile = string.concat("test/scripts/data/proof-", vm.toString(TEST_RECIPIENT_1), ".json");
        string memory proofJson = vm.readFile(proofFile);
        
        bytes memory proofData = proofJson.parseRaw(".proof");
        bytes32[] memory proof = abi.decode(proofData, (bytes32[]));
        
        // Use wrong amount (should be 1e18, using 2e18)
        uint256 wrongAmount = 2e18;
        bytes memory wrongClaimData = abi.encode(proof, wrongAmount);
        
        // Should return 0 for wrong amount
        uint256 claimableAmount = merkleStrategy.getClaimeableAmount(1, TEST_RECIPIENT_1, wrongClaimData);
        assertEq(claimableAmount, 0, "Wrong amount should return 0 claimable amount");
    }

    function test_Integration_BatchVerification() external {
        // Generate merkle tree
        generateMerkleTreeWithScript();
        
        // Read tree data
        string memory treeJson = vm.readFile(INTEGRATION_TREE_FILE);
        bytes32 merkleRoot = treeJson.readBytes32(".merkleRoot");
        
        // Generate proofs for all recipients
        address[3] memory recipients = [TEST_RECIPIENT_1, TEST_RECIPIENT_2, TEST_RECIPIENT_3];
        for (uint256 i = 0; i < recipients.length; i++) {
            generateProofWithScript(recipients[i]);
        }
        
        // Batch verify all proofs using VerifyProof script
        for (uint256 i = 0; i < recipients.length; i++) {
            string memory proofFile = string.concat("test/scripts/data/proof-", vm.toString(recipients[i]), ".json");
            
            string[] memory ffiInputs = new string[](5);
            ffiInputs[0] = "forge";
            ffiInputs[1] = "script";
            ffiInputs[2] = "scripts/merkleDistributor/VerifyProof.s.sol:VerifyProof";
            ffiInputs[3] = "--sig";
            ffiInputs[4] = string.concat("verifyFromFile(string) ", proofFile);
            
            // This should succeed without reverting
            vm.ffi(ffiInputs);
        }
    }

    function test_Integration_LargeRecipientSet() external {
        // Create large recipient set (50 recipients)
        createLargeRecipientSet();
        
        // Generate merkle tree for large set
        string[] memory ffiInputs = new string[](5);
        ffiInputs[0] = "forge";
        ffiInputs[1] = "script";
        ffiInputs[2] = "scripts/merkleDistributor/GenerateMerkleTree.s.sol:GenerateMerkleTree";
        ffiInputs[3] = "--sig";
        ffiInputs[4] = "generate(string) test/scripts/data/large-recipients.json";
        
        vm.ffi(ffiInputs);
        
        // Verify tree was generated
        string memory largeTreeJson = vm.readFile("test/scripts/data/merkle-tree.json");
        uint256 totalRecipients = largeTreeJson.readUint(".totalRecipients");
        assertEq(totalRecipients, 50, "Should have 50 recipients in large set");
        
        // Test a few random proofs from the large set
        address testAddr1 = address(uint160(uint256(keccak256(abi.encodePacked("recipient", uint256(5))))));
        address testAddr2 = address(uint160(uint256(keccak256(abi.encodePacked("recipient", uint256(25))))));
        
        // Generate proofs
        generateProofWithScript(testAddr1);
        generateProofWithScript(testAddr2);
        
        // Verify they exist and are valid
        string memory proof1File = string.concat("test/scripts/data/proof-", vm.toString(testAddr1), ".json");
        string memory proof2File = string.concat("test/scripts/data/proof-", vm.toString(testAddr2), ".json");
        
        string memory proof1Json = vm.readFile(proof1File);
        string memory proof2Json = vm.readFile(proof2File);
        
        bool valid1 = proof1Json.readBool(".valid");
        bool valid2 = proof2Json.readBool(".valid");
        
        assertTrue(valid1, "Proof for recipient 5 should be valid");
        assertTrue(valid2, "Proof for recipient 25 should be valid");
    }

    // Helper functions

    function createIntegrationTestData() internal {
        string memory json = string.concat(
            "[\n",
            "  {\"account\": \"", vm.toString(TEST_RECIPIENT_1), "\", \"amount\": \"1000000000000000000\"},\n",
            "  {\"account\": \"", vm.toString(TEST_RECIPIENT_2), "\", \"amount\": \"2000000000000000000\"},\n",
            "  {\"account\": \"", vm.toString(TEST_RECIPIENT_3), "\", \"amount\": \"3000000000000000000\"}\n",
            "]"
        );
        vm.writeFile(INTEGRATION_RECIPIENTS_FILE, json);
    }

    function createLargeRecipientSet() internal {
        string memory json = "[\n";
        
        for (uint256 i = 0; i < 50; i++) {
            if (i > 0) {
                json = string.concat(json, ",\n");
            }
            
            address addr = address(uint160(uint256(keccak256(abi.encodePacked("recipient", i)))));
            uint256 amount = (i + 1) * 1e18;
            
            json = string.concat(
                json,
                "  {\"account\": \"", vm.toString(addr), "\", \"amount\": \"", vm.toString(amount), "\"}"
            );
        }
        
        json = string.concat(json, "\n]");
        vm.writeFile("test/scripts/data/large-recipients.json", json);
    }

    function generateMerkleTreeWithScript() internal {
        string[] memory ffiInputs = new string[](5);
        ffiInputs[0] = "forge";
        ffiInputs[1] = "script";
        ffiInputs[2] = "scripts/merkleDistributor/GenerateMerkleTree.s.sol:GenerateMerkleTree";
        ffiInputs[3] = "--sig";
        ffiInputs[4] = string.concat("generate(string) ", INTEGRATION_RECIPIENTS_FILE);
        
        vm.ffi(ffiInputs);
    }

    function generateProofWithScript(address recipient) internal {
        string[] memory ffiInputs = new string[](6);
        ffiInputs[0] = "forge";
        ffiInputs[1] = "script";
        ffiInputs[2] = "scripts/merkleDistributor/GenerateProof.s.sol:GenerateProof";
        ffiInputs[3] = "--sig";
        ffiInputs[4] = "generateProof(string,address)";
        ffiInputs[5] = string.concat(INTEGRATION_TREE_FILE, " ", vm.toString(recipient));
        
        vm.ffi(ffiInputs);
    }
}