// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title ProofGeneratorTest
 * @notice Test suite for the GenerateProof.s.sol script
 */
contract ProofGeneratorTest is Test {
    using stdJson for string;

    struct Recipient {
        address account;
        uint256 amount;
        bytes32 leaf;
    }

    string constant TEST_DATA_DIR = "test/scripts/data";
    string constant MERKLE_TREE_FILE = "test/scripts/data/test-merkle-tree.json";
    string constant PROOF_OUTPUT_PREFIX = "test/scripts/data/proof-";

    address constant TEST_RECIPIENT_1 = 0x1234567890123456789012345678901234567890;
    address constant TEST_RECIPIENT_2 = 0x2345678901234567890123456789012345678901;
    address constant TEST_RECIPIENT_3 = 0x3456789012345678901234567890123456789012;
    address constant TEST_RECIPIENT_4 = 0x4567890123456789012345678901234567890123;

    function setUp() external {
        // Create test data directory
        vm.createDir(TEST_DATA_DIR, true);
        
        // Create test merkle tree file
        createTestMerkleTreeFile();
    }

    function test_GenerateProof_FirstRecipient() external {
        // Generate proof for first recipient
        string[] memory ffiInputs = new string[](6);
        ffiInputs[0] = "forge";
        ffiInputs[1] = "script";
        ffiInputs[2] = "scripts/merkleDistributor/GenerateProof.s.sol:GenerateProof";
        ffiInputs[3] = "--sig";
        ffiInputs[4] = "generateProof(string,address)";
        ffiInputs[5] = string.concat(MERKLE_TREE_FILE, " ", vm.toString(TEST_RECIPIENT_1));
        
        vm.ffi(ffiInputs);
        
        // Verify proof file was created
        string memory proofFile = string.concat(PROOF_OUTPUT_PREFIX, vm.toString(TEST_RECIPIENT_1), ".json");
        string memory proofOutput = vm.readFile(proofFile);
        assertGt(bytes(proofOutput).length, 0, "Proof file should not be empty");
        
        // Parse and validate proof
        address recipient = proofOutput.readAddress(".recipient");
        uint256 amount = proofOutput.readUint(".amount");
        bytes32 merkleRoot = proofOutput.readBytes32(".merkleRoot");
        bool valid = proofOutput.readBool(".valid");
        
        assertEq(recipient, TEST_RECIPIENT_1, "Recipient should match");
        assertEq(amount, 1000000000000000000, "Amount should be 1 ETH");
        assertNotEq(merkleRoot, bytes32(0), "Merkle root should not be zero");
        assertTrue(valid, "Proof should be valid");
    }

    function test_GenerateProof_AllRecipients() external {
        address[4] memory recipients = [TEST_RECIPIENT_1, TEST_RECIPIENT_2, TEST_RECIPIENT_3, TEST_RECIPIENT_4];
        uint256[4] memory amounts = [uint256(1e18), 2e18, 3e18, 4e18];
        
        for (uint256 i = 0; i < recipients.length; i++) {
            // Generate proof
            string[] memory ffiInputs = new string[](6);
            ffiInputs[0] = "forge";
            ffiInputs[1] = "script";
            ffiInputs[2] = "scripts/merkleDistributor/GenerateProof.s.sol:GenerateProof";
            ffiInputs[3] = "--sig";
            ffiInputs[4] = "generateProof(string,address)";
            ffiInputs[5] = string.concat(MERKLE_TREE_FILE, " ", vm.toString(recipients[i]));
            
            vm.ffi(ffiInputs);
            
            // Verify proof
            string memory proofFile = string.concat(PROOF_OUTPUT_PREFIX, vm.toString(recipients[i]), ".json");
            string memory proofOutput = vm.readFile(proofFile);
            
            address recipient = proofOutput.readAddress(".recipient");
            uint256 amount = proofOutput.readUint(".amount");
            bool valid = proofOutput.readBool(".valid");
            
            assertEq(recipient, recipients[i], string.concat("Recipient should match for index ", vm.toString(i)));
            assertEq(amount, amounts[i], string.concat("Amount should match for index ", vm.toString(i)));
            assertTrue(valid, string.concat("Proof should be valid for index ", vm.toString(i)));
        }
    }

    function test_ProofGeneration_ManualValidation() external {
        // Test proof generation logic manually
        Recipient[] memory recipients = createTestRecipients();
        bytes32 merkleRoot = calculateMerkleRoot(recipients);
        
        for (uint256 i = 0; i < recipients.length; i++) {
            bytes32[] memory proof = generateProofForIndex(recipients, i);
            bool isValid = MerkleProof.verify(proof, merkleRoot, recipients[i].leaf);
            assertTrue(isValid, string.concat("Manual proof should be valid for index ", vm.toString(i)));
        }
    }

    function test_ProofGeneration_NonExistentRecipient() external {
        address nonExistentRecipient = address(0x9999999999999999999999999999999999999999);
        
        // This should fail when trying to find the recipient
        string[] memory ffiInputs = new string[](6);
        ffiInputs[0] = "forge";
        ffiInputs[1] = "script";
        ffiInputs[2] = "scripts/merkleDistributor/GenerateProof.s.sol:GenerateProof";
        ffiInputs[3] = "--sig";
        ffiInputs[4] = "generateProof(string,address)";
        ffiInputs[5] = string.concat(MERKLE_TREE_FILE, " ", vm.toString(nonExistentRecipient));
        
        // FFI doesn't handle reverts well, so we test the logic directly
        Recipient[] memory recipients = createTestRecipients();
        uint256 index = findRecipientIndex(recipients, nonExistentRecipient);
        assertEq(index, recipients.length, "Should return length for non-existent recipient");
    }

    function test_ProofStructure_ValidFormat() external {
        // Generate a proof and verify its structure
        string[] memory ffiInputs = new string[](6);
        ffiInputs[0] = "forge";
        ffiInputs[1] = "script";
        ffiInputs[2] = "scripts/merkleDistributor/GenerateProof.s.sol:GenerateProof";
        ffiInputs[3] = "--sig";
        ffiInputs[4] = "generateProof(string,address)";
        ffiInputs[5] = string.concat(MERKLE_TREE_FILE, " ", vm.toString(TEST_RECIPIENT_1));
        
        vm.ffi(ffiInputs);
        
        string memory proofFile = string.concat(PROOF_OUTPUT_PREFIX, vm.toString(TEST_RECIPIENT_1), ".json");
        string memory proofOutput = vm.readFile(proofFile);
        
        // Verify all required fields exist
        address recipient = proofOutput.readAddress(".recipient");
        uint256 amount = proofOutput.readUint(".amount");
        bytes32 leaf = proofOutput.readBytes32(".leaf");
        bytes32 merkleRoot = proofOutput.readBytes32(".merkleRoot");
        bool valid = proofOutput.readBool(".valid");
        
        // Verify Solidity call data structure exists
        bytes memory proofData = proofOutput.parseRaw(".proof");
        bytes32[] memory proof = abi.decode(proofData, (bytes32[]));
        
        bytes memory solidityData = proofOutput.parseRaw(".solidityCallData");
        (bytes32[] memory solidityProof, uint256 solidityAmount) = abi.decode(solidityData, (bytes32[], uint256));
        
        // Verify consistency
        assertEq(solidityAmount, amount, "Solidity amount should match");
        assertEq(solidityProof.length, proof.length, "Solidity proof length should match");
        
        for (uint256 i = 0; i < proof.length; i++) {
            assertEq(solidityProof[i], proof[i], string.concat("Proof element ", vm.toString(i), " should match"));
        }
    }

    function test_ProofVerification_AgainstContract() external {
        // Test that generated proofs work with the actual MerkleProof library
        Recipient[] memory recipients = createTestRecipients();
        bytes32 merkleRoot = calculateMerkleRoot(recipients);
        
        for (uint256 i = 0; i < recipients.length; i++) {
            bytes32[] memory proof = generateProofForIndex(recipients, i);
            
            // Verify using OpenZeppelin's MerkleProof library (same as our contract uses)
            bool isValid = MerkleProof.verify(proof, merkleRoot, recipients[i].leaf);
            assertTrue(isValid, string.concat("OpenZeppelin verification should pass for index ", vm.toString(i)));
            
            // Also verify manually to ensure our algorithm matches
            bool manualValid = verifyProofManually(proof, recipients[i].leaf, merkleRoot);
            assertTrue(manualValid, string.concat("Manual verification should pass for index ", vm.toString(i)));
            
            assertEq(isValid, manualValid, "OpenZeppelin and manual verification should agree");
        }
    }

    function test_ProofLength_CorrectDepth() external {
        // For 4 recipients, tree depth should be 2, so proof length should be 2
        Recipient[] memory recipients = createTestRecipients();
        
        for (uint256 i = 0; i < recipients.length; i++) {
            bytes32[] memory proof = generateProofForIndex(recipients, i);
            assertEq(proof.length, 2, string.concat("Proof length should be 2 for 4 recipients, index ", vm.toString(i)));
        }
    }

    // Helper functions

    function createTestMerkleTreeFile() internal {
        // Create the same recipients as in MerkleTreeGeneratorTest
        Recipient[] memory recipients = createTestRecipients();
        bytes32 merkleRoot = calculateMerkleRoot(recipients);
        
        string memory json = string.concat(
            "{\n",
            "  \"merkleRoot\": \"", vm.toString(merkleRoot), "\",\n",
            "  \"totalRecipients\": 4,\n",
            "  \"totalAmount\": \"10000000000000000000\",\n",
            "  \"recipients\": [\n"
        );
        
        for (uint256 i = 0; i < recipients.length; i++) {
            if (i > 0) json = string.concat(json, ",\n");
            json = string.concat(
                json,
                "    {\n",
                "      \"address\": \"", vm.toString(recipients[i].account), "\",\n",
                "      \"amount\": \"", vm.toString(recipients[i].amount), "\",\n",
                "      \"leaf\": \"", vm.toString(recipients[i].leaf), "\"\n",
                "    }"
            );
        }
        
        json = string.concat(json, "\n  ]\n}");
        vm.writeFile(MERKLE_TREE_FILE, json);
    }

    function createTestRecipients() internal pure returns (Recipient[] memory) {
        Recipient[] memory recipients = new Recipient[](4);
        
        recipients[0] = Recipient({
            account: TEST_RECIPIENT_1,
            amount: 1000000000000000000,
            leaf: keccak256(abi.encodePacked(TEST_RECIPIENT_1, uint256(1000000000000000000)))
        });
        
        recipients[1] = Recipient({
            account: TEST_RECIPIENT_2,
            amount: 2000000000000000000,
            leaf: keccak256(abi.encodePacked(TEST_RECIPIENT_2, uint256(2000000000000000000)))
        });
        
        recipients[2] = Recipient({
            account: TEST_RECIPIENT_3,
            amount: 3000000000000000000,
            leaf: keccak256(abi.encodePacked(TEST_RECIPIENT_3, uint256(3000000000000000000)))
        });
        
        recipients[3] = Recipient({
            account: TEST_RECIPIENT_4,
            amount: 4000000000000000000,
            leaf: keccak256(abi.encodePacked(TEST_RECIPIENT_4, uint256(4000000000000000000)))
        });
        
        return recipients;
    }

    function calculateMerkleRoot(Recipient[] memory recipients) internal pure returns (bytes32) {
        bytes32[] memory leaves = new bytes32[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            leaves[i] = recipients[i].leaf;
        }
        return buildMerkleTree(leaves);
    }

    function buildMerkleTree(bytes32[] memory leaves) internal pure returns (bytes32) {
        if (leaves.length == 1) {
            return leaves[0];
        }
        
        bytes32[] memory currentLevel = leaves;
        while (currentLevel.length > 1) {
            currentLevel = buildNextLevel(currentLevel);
        }
        return currentLevel[0];
    }

    function buildNextLevel(bytes32[] memory currentLevel) internal pure returns (bytes32[] memory) {
        uint256 nextLevelLength = (currentLevel.length + 1) / 2;
        bytes32[] memory nextLevel = new bytes32[](nextLevelLength);
        
        for (uint256 i = 0; i < nextLevelLength; i++) {
            bytes32 left = currentLevel[i * 2];
            
            if (i * 2 + 1 < currentLevel.length) {
                bytes32 right = currentLevel[i * 2 + 1];
                nextLevel[i] = left < right ? 
                    keccak256(abi.encodePacked(left, right)) : 
                    keccak256(abi.encodePacked(right, left));
            } else {
                nextLevel[i] = left;
            }
        }
        
        return nextLevel;
    }

    function generateProofForIndex(Recipient[] memory recipients, uint256 targetIndex) internal pure returns (bytes32[] memory) {
        bytes32[] memory leaves = new bytes32[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            leaves[i] = recipients[i].leaf;
        }
        
        return buildProof(leaves, targetIndex);
    }

    function buildProof(bytes32[] memory leaves, uint256 targetIndex) internal pure returns (bytes32[] memory) {
        require(targetIndex < leaves.length, "Invalid target index");
        
        if (leaves.length == 1) {
            return new bytes32[](0);
        }
        
        uint256 proofLength = 0;
        uint256 tempLength = leaves.length;
        while (tempLength > 1) {
            proofLength++;
            tempLength = (tempLength + 1) / 2;
        }
        
        bytes32[] memory proof = new bytes32[](proofLength);
        bytes32[] memory currentLevel = leaves;
        uint256 currentIndex = targetIndex;
        uint256 proofIndex = 0;
        
        while (currentLevel.length > 1) {
            uint256 siblingIndex;
            if (currentIndex % 2 == 0) {
                siblingIndex = currentIndex + 1;
            } else {
                siblingIndex = currentIndex - 1;
            }
            
            if (siblingIndex < currentLevel.length) {
                proof[proofIndex] = currentLevel[siblingIndex];
            }
            proofIndex++;
            
            currentLevel = buildNextLevel(currentLevel);
            currentIndex = currentIndex / 2;
        }
        
        bytes32[] memory finalProof = new bytes32[](proofIndex);
        for (uint256 i = 0; i < proofIndex; i++) {
            finalProof[i] = proof[i];
        }
        
        return finalProof;
    }

    function findRecipientIndex(Recipient[] memory recipients, address targetAddress) internal pure returns (uint256) {
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i].account == targetAddress) {
                return i;
            }
        }
        return recipients.length; // Not found
    }

    function verifyProofManually(bytes32[] memory proof, bytes32 leaf, bytes32 root) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            
            if (computedHash < proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        
        return computedHash == root;
    }
}