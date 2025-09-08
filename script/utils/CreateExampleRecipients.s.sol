// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";

/**
 * @title CreateExampleRecipients
 * @notice Foundry script to create example recipients JSON files
 * @dev Usage: forge script scripts/merkleDistributor/CreateExampleRecipients.s.sol --sig "createExample(string)"
 * "path/to/recipients.json"
 */
contract CreateExampleRecipients is Script {
    /**
     * @notice Create an example recipients JSON file
     * @param outputPath Path where to save the example file
     */
    function createExample(string memory outputPath) external {
        string memory json = createExampleJson();
        vm.writeFile(outputPath, json);

        console.log("Example recipients file created!");
        console.log("Path:", outputPath);
        console.log("Recipients: 4");
        console.log("Format: {\"address\": \"0x...\", \"amount\": \"wei_amount\"}");
    }

    /**
     * @notice Create small example for testing (3 recipients)
     * @param outputPath Path where to save the example file
     */
    function createSmallExample(string memory outputPath) external {
        string memory json = createSmallExampleJson();
        vm.writeFile(outputPath, json);

        console.log("Small example recipients file created!");
        console.log("Path:", outputPath);
        console.log("Recipients: 3");
    }

    /**
     * @notice Create large example for stress testing (100 recipients)
     * @param outputPath Path where to save the example file
     */
    function createLargeExample(string memory outputPath) external {
        string memory json = createLargeExampleJson();
        vm.writeFile(outputPath, json);

        console.log("Large example recipients file created!");
        console.log("Path:", outputPath);
        console.log("Recipients: 100");
    }

    /**
     * @notice Create example JSON with 4 recipients
     * @return json JSON string
     */
    function createExampleJson() internal pure returns (string memory) {
        return string.concat(
            "[\n",
            "  {\n",
            "    \"account\": \"0x1234567890123456789012345678901234567890\",\n",
            "    \"amount\": \"1000000000000000000\"\n",
            "  },\n",
            "  {\n",
            "    \"account\": \"0x2345678901234567890123456789012345678901\",\n",
            "    \"amount\": \"2500000000000000000\"\n",
            "  },\n",
            "  {\n",
            "    \"account\": \"0x3456789012345678901234567890123456789012\",\n",
            "    \"amount\": \"750000000000000000\"\n",
            "  },\n",
            "  {\n",
            "    \"account\": \"0x4567890123456789012345678901234567890123\",\n",
            "    \"amount\": \"5000000000000000000\"\n",
            "  }\n",
            "]"
        );
    }

    /**
     * @notice Create small example JSON with 3 recipients
     * @return json JSON string
     */
    function createSmallExampleJson() internal pure returns (string memory) {
        return string.concat(
            "[\n",
            "  {\n",
            "    \"account\": \"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266\",\n",
            "    \"amount\": \"1000000000000000000\"\n",
            "  },\n",
            "  {\n",
            "    \"account\": \"0x70997970C51812dc3A010C7d01b50e0d17dc79C8\",\n",
            "    \"amount\": \"2000000000000000000\"\n",
            "  },\n",
            "  {\n",
            "    \"account\": \"0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC\",\n",
            "    \"amount\": \"3000000000000000000\"\n",
            "  }\n",
            "]"
        );
    }

    /**
     * @notice Create large example JSON with 100 recipients
     * @return json JSON string
     */
    function createLargeExampleJson() internal pure returns (string memory) {
        string memory json = "[\n";

        for (uint256 i = 0; i < 100; i++) {
            if (i > 0) {
                json = string.concat(json, ",\n");
            }

            // Generate pseudo-random address and amount
            address addr = address(uint160(uint256(keccak256(abi.encodePacked("recipient", i)))));
            uint256 amount = (i + 1) * 1e18; // 1 ETH, 2 ETH, 3 ETH, etc.

            json = string.concat(
                json,
                "  {\n",
                "    \"account\": \"",
                vm.toString(addr),
                "\",\n",
                "    \"amount\": \"",
                vm.toString(amount),
                "\"\n",
                "  }"
            );
        }

        json = string.concat(json, "\n]");
        return json;
    }

    /**
     * @notice Create example with known test addresses (Anvil/Hardhat)
     * @param outputPath Path where to save the example file
     */
    function createTestnetExample(string memory outputPath) external {
        string memory json = createTestnetExampleJson();
        vm.writeFile(outputPath, json);

        console.log("Testnet example recipients file created!");
        console.log("Path:", outputPath);
        console.log("Recipients: 10");
        console.log("Note: Uses well-known test addresses from Anvil/Hardhat");
    }

    /**
     * @notice Create example JSON with well-known test addresses
     * @return json JSON string
     */
    function createTestnetExampleJson() internal pure returns (string memory) {
        return string.concat(
            "[\n",
            "  {\"account\": \"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266\", \"amount\": \"1000000000000000000\"},\n",
            "  {\"account\": \"0x70997970C51812dc3A010C7d01b50e0d17dc79C8\", \"amount\": \"2000000000000000000\"},\n",
            "  {\"account\": \"0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC\", \"amount\": \"3000000000000000000\"},\n",
            "  {\"account\": \"0x90F79bf6EB2c4f870365E785982E1f101E93b906\", \"amount\": \"4000000000000000000\"},\n",
            "  {\"account\": \"0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65\", \"amount\": \"5000000000000000000\"},\n",
            "  {\"account\": \"0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc\", \"amount\": \"6000000000000000000\"},\n",
            "  {\"account\": \"0x976EA74026E726554dB657fA54763abd0C3a0aa9\", \"amount\": \"7000000000000000000\"},\n",
            "  {\"account\": \"0x14dC79964da2C08b23698B3D3cc7Ca32193d9955\", \"amount\": \"8000000000000000000\"},\n",
            "  {\"account\": \"0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f\", \"amount\": \"9000000000000000000\"},\n",
            "  {\"account\": \"0xa0Ee7A142d267C1f36714E4a8F75612F20a79720\", \"amount\": \"10000000000000000000\"}\n",
            "]"
        );
    }

    /**
     * @notice Validate recipients JSON file format
     * @param filePath Path to recipients JSON file
     */
    function validateFile(string memory filePath) external view {
        console.log("Validating recipients file:", filePath);

        // This would require parsing the JSON and validating structure
        // For now, just check if file exists
        string memory content;
        try vm.readFile(filePath) returns (string memory fileContent) {
            content = fileContent;
            console.log("File exists and readable");
            console.log("File size:", bytes(content).length, "bytes");
        } catch {
            console.log("File not found or not readable");
            return;
        }

        // Basic format checks
        bytes memory contentBytes = bytes(content);
        bool startsWithBracket = contentBytes.length > 0 && contentBytes[0] == "[";
        bool endsWithBracket = contentBytes.length > 0 && contentBytes[contentBytes.length - 1] == "]";

        if (startsWithBracket && endsWithBracket) {
            console.log("Basic JSON array format looks correct");
        } else {
            console.log("File doesn't appear to be a JSON array");
        }

        console.log("Use GenerateMerkleTree script to fully validate and process the file");
    }
}
