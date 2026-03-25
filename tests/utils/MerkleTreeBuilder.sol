// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

/// @title MerkleTreeBuilder
/// @notice Utility library for building Merkle trees and generating proofs in tests
library MerkleTreeBuilder {
    /// @notice Build merkle root from leaves
    /// @param leaves Array of leaf hashes
    /// @return The merkle root
    function buildMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        require(leaves.length > 0, "No leaves provided");

        if (leaves.length == 1) {
            return leaves[0];
        }

        bytes32[] memory currentLevel = leaves;

        while (currentLevel.length > 1) {
            bytes32[] memory nextLevel = new bytes32[]((currentLevel.length + 1) / 2);

            for (uint256 i = 0; i < nextLevel.length; i++) {
                bytes32 left = currentLevel[i * 2];

                if (i * 2 + 1 < currentLevel.length) {
                    bytes32 right = currentLevel[i * 2 + 1];
                    nextLevel[i] = left < right
                        ? keccak256(abi.encodePacked(left, right))
                        : keccak256(abi.encodePacked(right, left));
                } else {
                    nextLevel[i] = left;
                }
            }

            currentLevel = nextLevel;
        }

        return currentLevel[0];
    }

    /// @notice Generate merkle proof for a leaf at given index
    /// @param leaves Array of leaf hashes
    /// @param index Index of the leaf to generate proof for
    /// @return The merkle proof (array of sibling hashes)
    function generateMerkleProof(bytes32[] memory leaves, uint256 index) internal pure returns (bytes32[] memory) {
        require(index < leaves.length, "Index out of bounds");

        uint256 proofLength = 0;
        uint256 temp = leaves.length;
        while (temp > 1) {
            proofLength++;
            temp = (temp + 1) / 2;
        }

        bytes32[] memory proof = new bytes32[](proofLength);
        bytes32[] memory currentLevel = leaves;
        uint256 currentIndex = index;
        uint256 proofIndex = 0;

        while (currentLevel.length > 1) {
            uint256 pairIndex = currentIndex % 2 == 0 ? currentIndex + 1 : currentIndex - 1;

            if (pairIndex < currentLevel.length) {
                proof[proofIndex] = currentLevel[pairIndex];
                proofIndex++;
            }

            // Build next level
            bytes32[] memory nextLevel = new bytes32[]((currentLevel.length + 1) / 2);
            for (uint256 i = 0; i < nextLevel.length; i++) {
                bytes32 left = currentLevel[i * 2];
                if (i * 2 + 1 < currentLevel.length) {
                    bytes32 right = currentLevel[i * 2 + 1];
                    nextLevel[i] = left < right
                        ? keccak256(abi.encodePacked(left, right))
                        : keccak256(abi.encodePacked(right, left));
                } else {
                    nextLevel[i] = left;
                }
            }

            currentLevel = nextLevel;
            currentIndex = currentIndex / 2;
        }

        // Resize proof array
        bytes32[] memory resizedProof = new bytes32[](proofIndex);
        for (uint256 i = 0; i < proofIndex; i++) {
            resizedProof[i] = proof[i];
        }

        return resizedProof;
    }
}
