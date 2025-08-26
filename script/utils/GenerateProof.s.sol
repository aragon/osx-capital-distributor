// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

/**
 * @title GenerateProof
 * @notice Foundry script to generate merkle proofs for specific recipients
 * @dev Usage: forge script scripts/merkleDistributor/GenerateProof.s.sol --sig "generateProof(string,address)"
 * "merkle-tree.json" "0x123..."
 */
contract GenerateProof is Script {
    using stdJson for string;

    struct Recipient {
        address account;
        uint256 amount;
        bytes32 leaf;
    }

    struct MerkleTreeData {
        bytes32 merkleRoot;
        uint256 totalRecipients;
        uint256 totalAmount;
        Recipient[] recipients;
    }

    /**
     * @notice Generate merkle proof for a specific recipient
     * @param merkleTreeFilePath Path to merkle tree JSON file
     * @param recipientAddress Address of the recipient
     */
    function generateProof(string memory merkleTreeFilePath, address recipientAddress) external {
        // Read the merkle tree file
        string memory json = vm.readFile(merkleTreeFilePath);

        // Parse merkle tree data
        MerkleTreeData memory treeData = parseMerkleTreeData(json);

        // Find recipient
        uint256 recipientIndex = findRecipientIndex(treeData.recipients, recipientAddress);
        require(recipientIndex < treeData.recipients.length, "Recipient not found");

        Recipient memory recipient = treeData.recipients[recipientIndex];

        // Generate proof
        bytes32[] memory proof = generateMerkleProof(treeData.recipients, recipientIndex);

        // Verify proof
        bool isValid = verifyProof(proof, recipient.leaf, treeData.merkleRoot);
        require(isValid, "Generated proof is invalid");

        // Create output JSON
        string memory output = createProofJson(recipient, proof, treeData.merkleRoot, isValid);

        // Write output file to test data directory
        string memory outputPath = string.concat("./tests/data/proof-", vm.toString(recipientAddress), ".json");
        vm.writeFile(outputPath, output);

        // Log results
        console.log("Merkle Proof Generated Successfully!");
        console.log("Recipient:", recipientAddress);
        console.log("Amount:", recipient.amount);
        console.log("Proof elements:", proof.length);
        console.log("Valid:", isValid);
        console.log("Output:", outputPath);
    }

    /**
     * @notice Parse merkle tree data from JSON
     * @param json JSON string containing merkle tree data
     * @return treeData Parsed merkle tree data
     */
    function parseMerkleTreeData(string memory json) internal pure returns (MerkleTreeData memory) {
        bytes32 merkleRoot = json.readBytes32(".merkleRoot");
        uint256 totalRecipients = json.readUint(".totalRecipients");
        uint256 totalAmount = json.readUint(".totalAmount");

        // Parse recipients array
        bytes memory recipientsData = json.parseRaw(".recipients");
        Recipient[] memory recipients = new Recipient[](totalRecipients);

        for (uint256 i = 0; i < totalRecipients; i++) {
            string memory recipientPath = string.concat(".recipients[", vm.toString(i), "]");
            recipients[i] = Recipient({
                account: json.readAddress(string.concat(recipientPath, ".address")),
                amount: json.readUint(string.concat(recipientPath, ".amount")),
                leaf: json.readBytes32(string.concat(recipientPath, ".leaf"))
            });
        }

        return MerkleTreeData({
            merkleRoot: merkleRoot,
            totalRecipients: totalRecipients,
            totalAmount: totalAmount,
            recipients: recipients
        });
    }

    /**
     * @notice Find recipient index by address
     * @param recipients Array of recipients
     * @param targetAddress Address to find
     * @return index Index of recipient (or recipients.length if not found)
     */
    function findRecipientIndex(Recipient[] memory recipients, address targetAddress) internal pure returns (uint256) {
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i].account == targetAddress) {
                return i;
            }
        }
        return recipients.length; // Not found
    }

    /**
     * @notice Generate merkle proof for recipient at given index
     * @param recipients Array of all recipients
     * @param targetIndex Index of target recipient
     * @return proof Merkle proof array
     */
    function generateMerkleProof(
        Recipient[] memory recipients,
        uint256 targetIndex
    )
        internal
        pure
        returns (bytes32[] memory)
    {
        // Build leaves array
        bytes32[] memory leaves = new bytes32[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            leaves[i] = recipients[i].leaf;
        }

        // Generate proof by building tree and tracking path
        return buildProof(leaves, targetIndex);
    }

    /**
     * @notice Build merkle proof for leaf at given index
     * @param leaves Array of leaf hashes
     * @param targetIndex Index of target leaf
     * @return proof Merkle proof array
     */
    function buildProof(bytes32[] memory leaves, uint256 targetIndex) internal pure returns (bytes32[] memory) {
        require(targetIndex < leaves.length, "Invalid target index");

        if (leaves.length == 1) {
            return new bytes32[](0);
        }

        // Calculate proof length
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
            // Find sibling
            uint256 siblingIndex;
            if (currentIndex % 2 == 0) {
                // Target is left child, sibling is right
                siblingIndex = currentIndex + 1;
            } else {
                // Target is right child, sibling is left
                siblingIndex = currentIndex - 1;
            }

            // Add sibling to proof if it exists
            if (siblingIndex < currentLevel.length) {
                proof[proofIndex] = currentLevel[siblingIndex];
            }
            proofIndex++;

            // Build next level
            currentLevel = buildNextLevelForProof(currentLevel);
            currentIndex = currentIndex / 2;
        }

        // Resize proof array to actual length
        bytes32[] memory finalProof = new bytes32[](proofIndex);
        for (uint256 i = 0; i < proofIndex; i++) {
            finalProof[i] = proof[i];
        }

        return finalProof;
    }

    /**
     * @notice Build next level of merkle tree for proof generation
     * @param currentLevel Current level of hashes
     * @return nextLevel Next level of hashes
     */
    function buildNextLevelForProof(bytes32[] memory currentLevel) internal pure returns (bytes32[] memory) {
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
     * @notice Verify merkle proof
     * @param proof Merkle proof array
     * @param leaf Target leaf hash
     * @param root Expected merkle root
     * @return valid True if proof is valid
     */
    function verifyProof(bytes32[] memory proof, bytes32 leaf, bytes32 root) internal pure returns (bool) {
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

    /**
     * @notice Create proof output JSON
     * @param recipient Recipient data
     * @param proof Merkle proof array
     * @param merkleRoot Merkle root hash
     * @param isValid Whether proof is valid
     * @return output JSON string
     */
    function createProofJson(
        Recipient memory recipient,
        bytes32[] memory proof,
        bytes32 merkleRoot,
        bool isValid
    )
        internal
        pure
        returns (string memory)
    {
        string memory output = "{";

        // Add recipient data
        output = string.concat(output, '"recipient":"', vm.toString(recipient.account), '",');
        output = string.concat(output, '"amount":"', vm.toString(recipient.amount), '",');
        output = string.concat(output, '"leaf":"', vm.toString(recipient.leaf), '",');
        output = string.concat(output, '"merkleRoot":"', vm.toString(merkleRoot), '",');
        output = string.concat(output, '"valid":', isValid ? "true" : "false", ",");

        // Add proof array
        output = string.concat(output, '"proof":[');
        for (uint256 i = 0; i < proof.length; i++) {
            if (i > 0) output = string.concat(output, ",");
            output = string.concat(output, '"', vm.toString(proof[i]), '"');
        }
        output = string.concat(output, "],");

        // Add Solidity call data
        output = string.concat(output, '"solidityCallData":{');
        output = string.concat(output, '"merkleProof":[');
        for (uint256 i = 0; i < proof.length; i++) {
            if (i > 0) output = string.concat(output, ",");
            output = string.concat(output, '"', vm.toString(proof[i]), '"');
        }
        output = string.concat(output, "],");
        output = string.concat(output, '"amount":"', vm.toString(recipient.amount), '"');
        output = string.concat(output, "}");

        output = string.concat(output, "}");

        return output;
    }

    /**
     * @notice Get base path from file path
     * @param filePath Full file path
     * @return basePath Directory path
     */
    function getBasePath(string memory filePath) internal pure returns (string memory) {
        bytes memory fileBytes = bytes(filePath);

        // Find last slash
        int256 lastSlash = -1;
        for (uint256 i = fileBytes.length; i > 0; i--) {
            if (fileBytes[i - 1] == "/") {
                lastSlash = int256(i - 1);
                break;
            }
        }

        if (lastSlash == -1) {
            return ".";
        }

        bytes memory basePath = new bytes(uint256(lastSlash));
        for (uint256 i = 0; i < uint256(lastSlash); i++) {
            basePath[i] = fileBytes[i];
        }

        return string(basePath);
    }
}
