// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { MerkleDistributorStrategy } from "../../src/allocatorStrategies/MerkleDistributorStrategy.sol";

/// @title AllocatorStrategyEncoderDecoderTest
/// @notice Comprehensive tests for encoder/decoder functions in allocator strategies
contract AllocatorStrategyEncoderDecoderTest is Test {
    MerkleDistributorStrategy merkleStrategy;

    function setUp() public {
        merkleStrategy = new MerkleDistributorStrategy();
    }

    // ============================================
    // MerkleDistributorStrategy Tests
    // ============================================

    /// @notice Test encoding/decoding of initialization params for MerkleDistributorStrategy
    function test_MerkleStrategy_InitializationParams() public {
        // No params needed for merkle initialization
        bytes memory encoded = merkleStrategy.encodeInitializationParams();
        assertEq(encoded.length, 0, "Merkle init params should be empty");
    }

    /// @notice Test encoding/decoding of campaign creation params for MerkleDistributorStrategy
    function test_MerkleStrategy_SetAllocationCampaignParams() public {
        bytes32 merkleRoot = keccak256("test-merkle-root");

        // Encode
        bytes memory encoded = merkleStrategy.encodeSetAllocationCampaignParams(merkleRoot);

        // Decode
        bytes32 decodedRoot = merkleStrategy.decodeSetAllocationCampaignParams(encoded);

        assertEq(decodedRoot, merkleRoot, "Decoded merkle root should match original");
    }

    /// @notice Test encoding/decoding of claim params for MerkleDistributorStrategy
    function test_MerkleStrategy_ClaimParams() public {
        // Create test data
        bytes32[] memory proof = new bytes32[](3);
        proof[0] = keccak256("proof1");
        proof[1] = keccak256("proof2");
        proof[2] = keccak256("proof3");
        uint256 amount = 1000 ether;

        // Encode
        bytes memory encoded = merkleStrategy.encodeClaimParams(proof, amount);

        // Decode
        (bytes32[] memory decodedProof, uint256 decodedAmount) = merkleStrategy.decodeClaimParams(encoded);

        // Verify
        assertEq(decodedProof.length, proof.length, "Proof array length should match");
        for (uint256 i = 0; i < proof.length; i++) {
            assertEq(decodedProof[i], proof[i], "Proof element should match");
        }
        assertEq(decodedAmount, amount, "Decoded amount should match");
    }

    /// @notice Fuzz test for MerkleDistributorStrategy campaign params
    function testFuzz_MerkleStrategy_SetAllocationCampaignParams(bytes32 merkleRoot) public {
        bytes memory encoded = merkleStrategy.encodeSetAllocationCampaignParams(merkleRoot);
        bytes32 decoded = merkleStrategy.decodeSetAllocationCampaignParams(encoded);
        assertEq(decoded, merkleRoot, "Fuzz: decoded value should match original");
    }

    /// @notice Fuzz test for MerkleDistributorStrategy claim params
    function testFuzz_MerkleStrategy_ClaimParams(bytes32[] memory proof, uint256 amount) public {
        vm.assume(proof.length < 100); // Reasonable limit

        bytes memory encoded = merkleStrategy.encodeClaimParams(proof, amount);
        (bytes32[] memory decodedProof, uint256 decodedAmount) = merkleStrategy.decodeClaimParams(encoded);

        assertEq(decodedProof.length, proof.length, "Fuzz: proof length should match");
        for (uint256 i = 0; i < proof.length; i++) {
            assertEq(decodedProof[i], proof[i], "Fuzz: proof element should match");
        }
        assertEq(decodedAmount, amount, "Fuzz: amount should match");
    }

    // ============================================
    // Cross-compatibility Tests
    // ============================================

    /// @notice Test edge cases
    function test_EdgeCases() public {
        // Empty proof array
        bytes32[] memory emptyProof = new bytes32[](0);
        uint256 amount = 100;
        bytes memory encoded = merkleStrategy.encodeClaimParams(emptyProof, amount);
        (bytes32[] memory decodedProof, uint256 decodedAmount) = merkleStrategy.decodeClaimParams(encoded);
        assertEq(decodedProof.length, 0, "Empty proof should decode correctly");
        assertEq(decodedAmount, amount, "Amount should still decode correctly");

        // Zero amounts
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0);
        encoded = merkleStrategy.encodeClaimParams(proof, 0);
        (decodedProof, decodedAmount) = merkleStrategy.decodeClaimParams(encoded);
        assertEq(decodedAmount, 0, "Zero amount should decode correctly");

        // Zero merkle root
        encoded = merkleStrategy.encodeSetAllocationCampaignParams(bytes32(0));
        bytes32 decodedRoot = merkleStrategy.decodeSetAllocationCampaignParams(encoded);
        assertEq(decodedRoot, bytes32(0), "Zero merkle root should decode correctly");
    }
}
