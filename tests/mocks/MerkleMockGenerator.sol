// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

/**
 * @title MerkleMockGenerator
 * @notice Generates merkle tree data in-memory for testing without file dependencies
 * @dev Provides the same merkle root and proof generation as the scripts but without file I/O
 */
contract MerkleMockGenerator {
    struct Recipient {
        address account;
        uint256 amount;
    }

    struct MerkleData {
        bytes32 root;
        bytes32[] leaves;
        uint256 totalAmount;
        Recipient[] recipients;
    }

    /**
     * @notice Generate merkle data for standard test set (10 recipients)
     * @return data The complete merkle tree data
     */
    function generateStandardTestData() external pure returns (MerkleData memory data) {
        data.recipients = new Recipient[](10);
        data.recipients[0] = Recipient(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 1 ether);
        data.recipients[1] = Recipient(0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 2 ether);
        data.recipients[2] = Recipient(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC, 3 ether);
        data.recipients[3] = Recipient(0x90F79bf6EB2c4f870365E785982E1f101E93b906, 4 ether);
        data.recipients[4] = Recipient(0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65, 5 ether);
        data.recipients[5] = Recipient(0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc, 6 ether);
        data.recipients[6] = Recipient(0x976EA74026E726554dB657fA54763abd0C3a0aa9, 7 ether);
        data.recipients[7] = Recipient(0x14dC79964da2C08b23698B3D3cc7Ca32193d9955, 8 ether);
        data.recipients[8] = Recipient(0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f, 9 ether);
        data.recipients[9] = Recipient(0xa0Ee7A142d267C1f36714E4a8F75612F20a79720, 10 ether);

        data = _generateMerkleData(data.recipients);
    }

    /**
     * @notice Generate merkle data for large test set (100 recipients)
     * @return data The complete merkle tree data
     */
    function generateLargeTestData() external pure returns (MerkleData memory data) {
        data.recipients = new Recipient[](100);

        for (uint256 i = 0; i < 100; i++) {
            address addr = address(uint160(uint256(keccak256(abi.encodePacked("recipient", i)))));
            uint256 amount = (i + 1) * 1 ether;
            data.recipients[i] = Recipient(addr, amount);
        }

        data = _generateMerkleData(data.recipients);
    }

    /**
     * @notice Generate merkle proof for a specific recipient
     * @param merkleData The complete merkle tree data
     * @param recipientIndex Index of the recipient in the array
     * @return proof The merkle proof for the recipient
     */
    function generateProof(
        MerkleData memory merkleData,
        uint256 recipientIndex
    )
        external
        pure
        returns (bytes32[] memory proof)
    {
        require(recipientIndex < merkleData.recipients.length, "Invalid recipient index");

        uint256 leavesLen = merkleData.leaves.length;
        uint256 pathLength = _log2(leavesLen) + 1;
        proof = new bytes32[](pathLength);
        uint256 proofIndex = 0;

        // Build the merkle proof
        bytes32[] memory currentLevel = merkleData.leaves;
        uint256 index = recipientIndex;

        while (currentLevel.length > 1) {
            uint256 pairIndex = index % 2 == 0 ? index + 1 : index - 1;

            if (pairIndex < currentLevel.length) {
                proof[proofIndex] = currentLevel[pairIndex];
                proofIndex++;
            }

            // Move to next level
            currentLevel = _buildNextLevel(currentLevel);
            index = index / 2;
        }

        // Resize proof array
        bytes32[] memory resizedProof = new bytes32[](proofIndex);
        for (uint256 i = 0; i < proofIndex; i++) {
            resizedProof[i] = proof[i];
        }

        return resizedProof;
    }

    /**
     * @notice Internal function to generate merkle data from recipients
     * @param recipients Array of recipients
     * @return data The complete merkle tree data
     */
    function _generateMerkleData(Recipient[] memory recipients) private pure returns (MerkleData memory data) {
        data.recipients = new Recipient[](recipients.length);
        data.leaves = new bytes32[](recipients.length);

        // Copy recipients and generate leaves
        for (uint256 i = 0; i < recipients.length; i++) {
            data.recipients[i] = recipients[i];
            data.leaves[i] = keccak256(abi.encodePacked(recipients[i].account, recipients[i].amount));
            data.totalAmount += recipients[i].amount;
        }

        // Build merkle tree
        data.root = _buildMerkleTree(data.leaves);

        return data;
    }

    /**
     * @notice Build merkle tree from leaves
     * @param leaves Array of leaf hashes
     * @return root Merkle root hash
     */
    function _buildMerkleTree(bytes32[] memory leaves) private pure returns (bytes32) {
        require(leaves.length > 0, "No leaves provided");

        if (leaves.length == 1) {
            return leaves[0];
        }

        bytes32[] memory currentLevel = leaves;

        while (currentLevel.length > 1) {
            currentLevel = _buildNextLevel(currentLevel);
        }

        return currentLevel[0];
    }

    /**
     * @notice Build next level of merkle tree
     * @param currentLevel Current level of hashes
     * @return nextLevel Next level of hashes
     */
    function _buildNextLevel(bytes32[] memory currentLevel) private pure returns (bytes32[] memory) {
        uint256 nextLevelLength = (currentLevel.length + 1) / 2;
        bytes32[] memory nextLevel = new bytes32[](nextLevelLength);

        for (uint256 i = 0; i < nextLevelLength; i++) {
            bytes32 left = currentLevel[i * 2];

            if (i * 2 + 1 < currentLevel.length) {
                bytes32 right = currentLevel[i * 2 + 1];
                nextLevel[i] =
                    left < right ? keccak256(abi.encodePacked(left, right)) : keccak256(abi.encodePacked(right, left));
            } else {
                nextLevel[i] = left;
            }
        }

        return nextLevel;
    }

    /**
     * @notice Calculate log2 of a number
     * @param x The number
     * @return The log2 of x
     */
    function _log2(uint256 x) private pure returns (uint256) {
        uint256 result = 0;
        while (x > 1) {
            x >>= 1;
            result++;
        }
        return result;
    }
}
