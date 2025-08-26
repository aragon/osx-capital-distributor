// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

/**
 * @title GenerateMerkleTree
 * @notice Foundry script to generate merkle trees from JSON recipient files
 * @dev Usage: forge script scripts/merkleDistributor/GenerateMerkleTree.s.sol --sig "generate(string)"
 * "path/to/recipients.json"
 */
contract GenerateMerkleTree is Script {
    using stdJson for string;

    struct Recipient {
        address account;
        uint256 amount;
    }

    /**
     * @notice Generate merkle tree from recipients JSON file
     * @param recipientsFilePath Path to JSON file containing recipients
     */
    function generate(string memory recipientsFilePath) external {
        // Read the recipients file
        string memory json = vm.readFile(recipientsFilePath);

        // Parse recipients from JSON
        Recipient[] memory recipients = parseRecipients(json);

        // Generate merkle tree
        bytes32[] memory leaves = generateLeaves(recipients);
        bytes32 merkleRoot = buildMerkleTree(leaves);

        // Calculate total amount
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            totalAmount += recipients[i].amount;
        }

        // Create output JSON
        string memory output = createOutputJson(merkleRoot, recipients, leaves, totalAmount);

        // Write output file to test data directory
        string memory outputPath = "./tests/data/merkle-tree.json";
        vm.writeFile(outputPath, output);

        // Log results
        console.log("Merkle Tree Generated Successfully!");
        console.log("Root:", vm.toString(merkleRoot));
        console.log("Recipients:", recipients.length);
        console.log("Total Amount:", totalAmount);
        console.log("Output:", outputPath);
    }

    /**
     * @notice Parse recipients from JSON string
     * @param json JSON string containing recipients array
     * @return recipients Array of recipient structs
     */
    function parseRecipients(string memory json) internal view returns (Recipient[] memory) {
        // Try to parse elements up to a reasonable limit
        Recipient[] memory tempRecipients = new Recipient[](1000); // Max 1000 recipients
        uint256 count = 0;

        // Parse each recipient individually until we hit an error
        for (uint256 i = 0; i < 1000; i++) {
            try this.parseRecipientAtIndex(json, i) returns (Recipient memory recipient) {
                tempRecipients[count] = recipient;
                count++;
            } catch {
                break; // No more recipients
            }
        }

        require(count > 0, "No recipients found");

        // Create properly sized array
        Recipient[] memory recipients = new Recipient[](count);
        for (uint256 i = 0; i < count; i++) {
            recipients[i] = tempRecipients[i];
        }

        // Check for duplicates
        for (uint256 i = 0; i < recipients.length; i++) {
            for (uint256 j = i + 1; j < recipients.length; j++) {
                require(recipients[i].account != recipients[j].account, "Duplicate address found");
            }
        }

        return recipients;
    }

    /**
     * @notice Parse a single recipient at a specific index
     * @param json JSON string
     * @param index Array index
     * @return recipient Parsed recipient
     */
    function parseRecipientAtIndex(string memory json, uint256 index) external view returns (Recipient memory) {
        string memory accountPath = string.concat("$[", vm.toString(index), "].account");
        string memory amountPath = string.concat("$[", vm.toString(index), "].amount");

        address account = json.readAddress(accountPath);
        uint256 amount = json.readUint(amountPath);

        require(account != address(0), "Invalid address");
        require(amount > 0, "Amount must be greater than 0");

        return Recipient({ account: account, amount: amount });
    }

    /**
     * @notice Generate merkle leaves from recipients
     * @param recipients Array of recipients
     * @return leaves Array of leaf hashes
     */
    function generateLeaves(Recipient[] memory recipients) internal pure returns (bytes32[] memory) {
        bytes32[] memory leaves = new bytes32[](recipients.length);

        for (uint256 i = 0; i < recipients.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(recipients[i].account, recipients[i].amount));
        }

        return leaves;
    }

    /**
     * @notice Build merkle tree from leaves
     * @param leaves Array of leaf hashes
     * @return root Merkle root hash
     */
    function buildMerkleTree(bytes32[] memory leaves) internal pure returns (bytes32) {
        require(leaves.length > 0, "No leaves provided");

        if (leaves.length == 1) {
            return leaves[0];
        }

        bytes32[] memory currentLevel = leaves;

        while (currentLevel.length > 1) {
            currentLevel = buildNextLevel(currentLevel);
        }

        return currentLevel[0];
    }

    /**
     * @notice Build next level of merkle tree
     * @param currentLevel Current level of hashes
     * @return nextLevel Next level of hashes
     */
    function buildNextLevel(bytes32[] memory currentLevel) internal pure returns (bytes32[] memory) {
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
     * @notice Create output JSON string
     * @param merkleRoot The merkle root hash
     * @param recipients Array of recipients
     * @param leaves Array of leaf hashes
     * @param totalAmount Total amount of all recipients
     * @return output JSON string
     */
    function createOutputJson(
        bytes32 merkleRoot,
        Recipient[] memory recipients,
        bytes32[] memory leaves,
        uint256 totalAmount
    )
        internal
        pure
        returns (string memory)
    {
        string memory output = "{";

        // Add merkle root
        output = string.concat(output, '"merkleRoot":"', vm.toString(merkleRoot), '",');

        // Add metadata
        output = string.concat(output, '"totalRecipients":', vm.toString(recipients.length), ",");
        output = string.concat(output, '"totalAmount":"', vm.toString(totalAmount), '",');

        // Add recipients array
        output = string.concat(output, '"recipients":[');
        for (uint256 i = 0; i < recipients.length; i++) {
            if (i > 0) output = string.concat(output, ",");
            output = string.concat(output, "{");
            output = string.concat(output, '"address":"', vm.toString(recipients[i].account), '",');
            output = string.concat(output, '"amount":"', vm.toString(recipients[i].amount), '",');
            output = string.concat(output, '"leaf":"', vm.toString(leaves[i]), '"');
            output = string.concat(output, "}");
        }
        output = string.concat(output, "]");

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
