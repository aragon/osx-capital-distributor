// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { CapitalDistributorPlugin } from "../../src/CapitalDistributorPlugin.sol";

/**
 * @title ClaimMerkleCampaign
 * @notice Script to claim tokens from a Merkle distribution campaign
 * @dev Reads configuration from .env file:
 *      - CAPITAL_DISTRIBUTOR_ADDRESS: Address of the CapitalDistributorPlugin
 *      - CAMPAIGN_ID: ID of the campaign to claim from
 *      - MERKLE_PROOF: Comma-separated list of proof hashes (e.g., "0x123...,0x456...")
 *      - CLAIM_AMOUNT: Amount to claim in wei
 *      - RECIPIENT_ADDRESS: (Optional) Address to claim for, defaults to msg.sender
 */
contract ClaimMerkleCampaign is Script {
    /**
     * @notice Claim tokens from a Merkle campaign using environment variables
     */
    function run() external {
        vm.createSelectFork("sepolia");

        // Load configuration from environment variables
        address pluginAddress = vm.envAddress("CAPITAL_DISTRIBUTOR_ADDRESS");
        uint256 campaignId = vm.envUint("CAMPAIGN_ID");
        uint256 claimAmount = vm.envUint("CLAIM_AMOUNT");
        bytes32[] memory merkleProof = vm.envBytes32("MERKLE_PROOF", ",");
        address recipient = vm.envOr("RECIPIENT_ADDRESS", msg.sender);

        console.log("Claiming from Merkle Campaign...");
        console.log("Plugin:", pluginAddress);
        console.log("Campaign ID:", campaignId);
        console.log("Recipient:", recipient);
        console.log("Claim Amount:", claimAmount);
        console.log("Proof Length:", merkleProof.length);

        // Load the plugin
        CapitalDistributorPlugin plugin = CapitalDistributorPlugin(pluginAddress);

        // Encode the merkle proof and amount for the strategy
        bytes memory strategyAuxData = abi.encode(merkleProof, claimAmount);

        // Start broadcasting transaction
        vm.startBroadcast();

        // Claim the payout
        console.log("Claiming payout...");
        uint256 amountClaimed = plugin.claimCampaignPayout(
            campaignId,
            recipient,
            strategyAuxData,
            "" // No encoder aux data for basic ERC20 transfers
        );

        vm.stopBroadcast();

        console.log("\n--- Claim Successful ---");
        console.log("Amount Claimed:", amountClaimed);
        console.log("Tokens sent to:", recipient);
    }

    /**
     * @notice Show example .env configuration and usage
     */
    function showExample() external view {
        console.log("\n=== Required .env Configuration ===\n");
        console.log("# Plugin Address");
        console.log("CAPITAL_DISTRIBUTOR_ADDRESS=0x3456789012345678901234567890123456789012");
        console.log("");
        console.log("# Claim Parameters");
        console.log("CAMPAIGN_ID=1");
        console.log("CLAIM_AMOUNT=1000000000000000000000  # 1000 tokens with 18 decimals");
        console.log("");
        console.log("# Merkle Proof (comma-separated hex strings)");
        console.log(
            "MERKLE_PROOF=0x1234567890123456789012345678901234567890123456789012345678901234,0xabcdef1234567890123456789012345678901234567890123456789012345678"
        );
        console.log("");
        console.log("# Optional: Claim for a different address");
        console.log("RECIPIENT_ADDRESS=0x1234567890123456789012345678901234567890");
        console.log("");
        console.log("# Private key for transaction signing");
        console.log("PRIVATE_KEY=0xYourPrivateKey");
        console.log("");
        console.log("\n=== Usage Examples ===\n");
        console.log("1. Claim for yourself:");
        console.log("forge script script/utils/ClaimMerkleCampaign.s.sol:ClaimMerkleCampaign \\");
        console.log("  --rpc-url $RPC_URL \\");
        console.log("  --private-key $PRIVATE_KEY \\");
        console.log("  --broadcast \\");
        console.log("  --sig \"run()\"");
        console.log("");
        console.log("2. Claim to a specific address:");
        console.log("forge script script/utils/ClaimMerkleCampaign.s.sol:ClaimMerkleCampaign \\");
        console.log("  --rpc-url $RPC_URL \\");
        console.log("  --private-key $PRIVATE_KEY \\");
        console.log("  --broadcast \\");
        console.log("  --sig \"claimTo()\"");
        console.log("");
        console.log("3. Show this help:");
        console.log("forge script script/utils/ClaimMerkleCampaign.s.sol:ClaimMerkleCampaign \\");
        console.log("  --sig \"showExample()\"");
    }
}
