// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Script, console2 as console } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";
import { CapitalDistributorPlugin } from "../../src/CapitalDistributorPlugin.sol";

/**
 * @title ClaimMerkleCampaignWithProofs
 * @notice Script to claim tokens from a Merkle campaign using proof files from script/fixtures/proofs
 * @dev Reads configuration from .env file:
 *      - CAPITAL_DISTRIBUTOR_ADDRESS: Address of the CapitalDistributorPlugin
 *      - CAMPAIGN_ID: ID of the campaign to claim from
 */
contract ClaimMerkleCampaignWithProofs is Script {
    struct ProofData {
        address account;
        uint256 amount;
        bytes32[] proof;
    }

    /**
     * @notice Check if a string ends with a suffix
     */
    function endsWith(string memory str, string memory suffix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory suffixBytes = bytes(suffix);

        if (strBytes.length < suffixBytes.length) {
            return false;
        }

        uint256 startIndex = strBytes.length - suffixBytes.length;

        for (uint256 i = 0; i < suffixBytes.length; i++) {
            if (strBytes[startIndex + i] != suffixBytes[i]) {
                return false;
            }
        }

        return true;
    }
    /**
     * @notice Claim tokens for all proof files in the fixtures/proofs directory
     */

    function run() external {
        vm.createSelectFork("sepolia");

        // Load configuration from environment variables
        address pluginAddress = vm.envAddress("CAPITAL_DISTRIBUTOR_ADDRESS");
        uint256 campaignId = vm.envUint("CAMPAIGN_ID");

        console.log("Claiming from Merkle Campaign using proof files...");
        console.log("Plugin:", pluginAddress);
        console.log("Campaign ID:", campaignId);
        console.log("");

        // Load the plugin
        CapitalDistributorPlugin plugin = CapitalDistributorPlugin(pluginAddress);

        // Read all proof files from the directory
        string memory proofsPath = "script/fixtures/proofs";

        // Get all files in the proofs directory
        Vm.DirEntry[] memory entries = vm.readDir(proofsPath);

        console.log("Found entries in proofs directory:", entries.length);

        // Start broadcasting transaction
        vm.startBroadcast();

        uint256 successCount = 0;
        uint256 totalClaimed = 0;

        // Process each file
        for (uint256 i = 0; i < entries.length; i++) {
            // Skip directories
            if (entries[i].isDir) {
                continue;
            }

            string memory path = entries[i].path;

            // Skip non-JSON files
            if (!endsWith(path, ".json")) {
                continue;
            }

            console.log("\n--- Processing proof file:", path, "---");

            try vm.readFile(path) returns (string memory json) {
                // Parse the proof data
                ProofData memory data = parseProofFile(json);

                console.log("Account:", data.account);
                console.log("Amount:", data.amount);
                console.log("Proof length:", data.proof.length);

                // Encode the merkle proof and amount for the strategy
                bytes memory strategyAuxData = abi.encode(data.proof, data.amount);

                try plugin.claimCampaignPayout(
                    campaignId,
                    data.account,
                    strategyAuxData,
                    "" // No encoder aux data for basic ERC20 transfers
                ) returns (uint256 amountClaimed) {
                    console.log("[SUCCESS] Claim successful! Amount:", amountClaimed);
                    successCount++;
                    totalClaimed += amountClaimed;
                } catch Error(string memory reason) {
                    console.log("[FAILED] Claim failed:", reason);
                } catch (bytes memory) {
                    console.log("[FAILED] Claim failed with unknown error");
                }
            } catch Error(string memory reason) {
                console.log("[ERROR] Failed to process file:", path);
                console.log("Reason:", reason);
            } catch (bytes memory) {
                console.log("[ERROR] Failed to process file:", path);
                console.log("Unknown error occurred");
            }
        }

        vm.stopBroadcast();

        console.log("\n=== Summary ===");
        console.log("Successful claims:", successCount);
        console.log("Total amount claimed:", totalClaimed);
    }

    /**
     * @notice Parse a proof file and extract the data
     */
    function parseProofFile(string memory json) internal pure returns (ProofData memory) {
        ProofData memory data;

        // Parse account (recipient in the JSON file)
        data.account = vm.parseJsonAddress(json, ".recipient");

        // Parse amount - first get as string then parse
        data.amount = vm.parseJsonUint(json, ".amount");

        // Parse proof array
        data.proof = vm.parseJsonBytes32Array(json, ".proof");

        return data;
    }

    /**
     * @notice Claim for a specific proof file
     */
    function claimForFile(string memory filename) external {
        vm.createSelectFork("sepolia");

        address pluginAddress = vm.envAddress("CAPITAL_DISTRIBUTOR_ADDRESS");
        uint256 campaignId = vm.envUint("CAMPAIGN_ID");

        console.log("Claiming from proof file:", filename);
        console.log("Plugin:", pluginAddress);
        console.log("Campaign ID:", campaignId);

        string memory fullPath = string.concat("script/fixtures/proofs/", filename);
        string memory json = vm.readFile(fullPath);
        ProofData memory data = parseProofFile(json);

        CapitalDistributorPlugin plugin = CapitalDistributorPlugin(pluginAddress);
        bytes memory strategyAuxData = abi.encode(data.proof, data.amount);

        vm.startBroadcast();

        uint256 amountClaimed = plugin.claimCampaignPayout(campaignId, data.account, strategyAuxData, "");

        vm.stopBroadcast();

        console.log("\n--- Claim Successful ---");
        console.log("Amount Claimed:", amountClaimed);
        console.log("Tokens sent to:", data.account);
    }
}
