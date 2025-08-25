// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title VerifyProof
 * @notice Foundry script to verify merkle proofs
 * @dev Usage: forge script scripts/merkleDistributor/VerifyProof.s.sol --sig "verifyProof(bytes32,address,uint256,bytes32[])" "0xroot..." "0xrecipient..." "1000000000000000000" "[0xproof1,0xproof2]"
 */
contract VerifyProof is Script {
    /**
     * @notice Verify a merkle proof using OpenZeppelin's MerkleProof library
     * @param merkleRoot The merkle root to verify against
     * @param recipient The recipient address
     * @param amount The claim amount
     * @param proof The merkle proof array
     */
    function verifyProof(
        bytes32 merkleRoot,
        address recipient,
        uint256 amount,
        bytes32[] memory proof
    ) external view {
        // Generate leaf hash (same as contract implementation)
        bytes32 leaf = keccak256(abi.encodePacked(recipient, amount));
        
        // Verify using OpenZeppelin's library
        bool isValid = MerkleProof.verify(proof, merkleRoot, leaf);
        
        // Log verification result
        console.log("=== Merkle Proof Verification ===");
        console.log("Root:", vm.toString(merkleRoot));
        console.log("Recipient:", recipient);
        console.log("Amount:", amount);
        console.log("Leaf:", vm.toString(leaf));
        console.log("Proof elements:", proof.length);
        
        console.log("Proof:");
        for (uint256 i = 0; i < proof.length; i++) {
            console.log("  [%d]:", i, vm.toString(proof[i]));
        }
        
        console.log("Result:", isValid ? "VALID" : "INVALID");
        
        if (!isValid) {
            console.log("WARNING: Proof verification failed!");
        }
    }

    /**
     * @notice Verify proof from JSON file
     * @param proofFilePath Path to proof JSON file
     */
    function verifyFromFile(string memory proofFilePath) external {
        // Read the proof file
        string memory json = vm.readFile(proofFilePath);
        
        // Parse proof data
        address recipient = abi.decode(vm.parseJson(json, ".recipient"), (address));
        uint256 amount = abi.decode(vm.parseJson(json, ".amount"), (uint256));
        bytes32 merkleRoot = abi.decode(vm.parseJson(json, ".merkleRoot"), (bytes32));
        
        // Parse proof array
        bytes memory proofData = vm.parseJson(json, ".proof");
        bytes32[] memory proof = abi.decode(proofData, (bytes32[]));
        
        // Verify the proof
        this.verifyProof(merkleRoot, recipient, amount, proof);
        
        console.log("Proof file:", proofFilePath);
    }

    /**
     * @notice Batch verify multiple proofs from a directory
     * @param merkleTreeFilePath Path to merkle tree JSON file
     * @param proofsDirectory Directory containing proof files
     */
    function batchVerify(string memory merkleTreeFilePath, string memory proofsDirectory) external {
        // Read merkle tree file to get root
        string memory treeJson = vm.readFile(merkleTreeFilePath);
        bytes32 merkleRoot = abi.decode(vm.parseJson(treeJson, ".merkleRoot"), (bytes32));
        uint256 totalRecipients = abi.decode(vm.parseJson(treeJson, ".totalRecipients"), (uint256));
        
        console.log("=== Batch Proof Verification ===");
        console.log("Merkle Root:", vm.toString(merkleRoot));
        console.log("Expected Recipients:", totalRecipients);
        
        uint256 validProofs = 0;
        uint256 totalProofs = 0;
        
        // Note: In a real implementation, you'd need to iterate through files in the directory
        // For now, this serves as a template for batch verification
        console.log("WARNING: Batch verification requires manual file iteration");
        console.log("Use individual verifyFromFile() calls for each proof file");
        
        console.log("Valid proofs:", validProofs, "/", totalProofs);
    }

    /**
     * @notice Manual verification using internal implementation
     * @param merkleRoot The merkle root to verify against
     * @param recipient The recipient address
     * @param amount The claim amount
     * @param proof The merkle proof array
     */
    function verifyManual(
        bytes32 merkleRoot,
        address recipient,
        uint256 amount,
        bytes32[] memory proof
    ) external view {
        // Generate leaf hash
        bytes32 leaf = keccak256(abi.encodePacked(recipient, amount));
        
        // Manual verification (same algorithm as OpenZeppelin)
        bytes32 computedHash = leaf;
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            
            if (computedHash < proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        
        bool isValid = computedHash == merkleRoot;
        
        // Log detailed verification steps
        console.log("=== Manual Merkle Proof Verification ===");
        console.log("Root:", vm.toString(merkleRoot));
        console.log("Recipient:", recipient);
        console.log("Amount:", amount);
        console.log("Leaf:", vm.toString(leaf));
        
        console.log("Verification steps:");
        bytes32 currentHash = leaf;
        console.log("  Start:", vm.toString(currentHash));
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            bool isLeft = currentHash < proofElement;
            
            if (isLeft) {
                currentHash = keccak256(abi.encodePacked(currentHash, proofElement));
                console.log("  Step", i + 1, ": left hash");
            } else {
                currentHash = keccak256(abi.encodePacked(proofElement, currentHash));
                console.log("  Step", i + 1, ": right hash");
            }
        }
        
        console.log("Final computed:", vm.toString(currentHash));
        console.log("Expected root:", vm.toString(merkleRoot));
        console.log("Result:", isValid ? "VALID" : "INVALID");
    }
}