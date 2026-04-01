// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { DirectAllocationStrategy } from "../../src/allocatorStrategies/DirectAllocationStrategy.sol";

/// @title SetDirectAllocationsFromCsv
/// @notice Uses an FFI-backed CSV converter to batch set allocations on DirectAllocationStrategy.
/// @dev Example:
///      forge script script/utils/SetDirectAllocationsFromCsv.s.sol:SetDirectAllocationsFromCsv \
///        --rpc-url $RPC_URL \
///        --broadcast \
///        --ffi \
///        --sig "run()" \
///        --env CHAIN_NAME=sepolia \
///        --env DIRECT_STRATEGY_ADDRESS=0xYourStrategy \
///        --env CAMPAIGN_ID=1 \
///        --env CSV_PATH=data/allocations.csv \
///        --env CSV_BATCH_SIZE=200 \
///        --env CSV_SKIP_HEADER=true \
///        --env CSV_DRY_RUN=false
///      Requires Bun to be installed, since the script calls `bun run script/utils/convertDirectAllocations.ts`.
///      Run with `CSV_DRY_RUN=true` to preview parsing without broadcasting transactions.
/// @dev Requires running with `forge script ... --ffi` so the TSV/CSV helper can be invoked.
contract SetDirectAllocationsFromCsv is Script {
    error MismatchedAllocationArrays();
    error InvalidAmountEncoding(uint256 index);

    /// @notice Reads allocations from a CSV (address,amount) and writes them on-chain.
    function run() external {
        vm.createSelectFork(vm.envString("CHAIN_NAME"));

        address strategyAddress = vm.envAddress("DIRECT_STRATEGY_ADDRESS");
        uint256 campaignId = vm.envUint("CAMPAIGN_ID");
        string memory csvPath = vm.envString("CSV_PATH");
        uint256 batchSize = vm.envOr("CSV_BATCH_SIZE", uint256(100));
        bool skipHeader = vm.envOr("CSV_SKIP_HEADER", true);
        bool dryRun = vm.envOr("CSV_DRY_RUN", false);

        (address[] memory recipients, uint256[] memory amounts) = _loadAllocations(csvPath, skipHeader);
        uint256 normalizedBatchSize = batchSize == 0 ? type(uint256).max : batchSize;

        console.log("DirectAllocationStrategy:", strategyAddress);
        console.log("Campaign ID:", campaignId);
        console.log("CSV path:", csvPath);
        console.log("Records parsed:", recipients.length);
        console.log("Batch size:", normalizedBatchSize == type(uint256).max ? 0 : normalizedBatchSize);
        console.log("Dry run:", dryRun);

        if (recipients.length == 0) {
            console.log("No allocations to process. Exiting.");
            return;
        }

        if (dryRun) {
            console.log("Dry run complete. No transactions broadcast.");
            return;
        }

        vm.startBroadcast();

        _execute(
            DirectAllocationStrategy(strategyAddress),
            campaignId,
            recipients,
            amounts,
            normalizedBatchSize,
            true,
            address(0)
        );

        vm.stopBroadcast();

        console.log("Allocation batches submitted successfully.");
    }

    /// @notice Helper exposed for tests or manual invocation with pre-parsed data.
    /// @param strategyAddress DirectAllocationStrategy instance to update.
    /// @param campaignId Campaign identifier.
    /// @param recipients Accounts to allocate to.
    /// @param amounts Corresponding allocation amounts.
    /// @param batchSize Number of entries per `setAllocations` call (0 = unlimited).
    function execute(
        address strategyAddress,
        uint256 campaignId,
        address[] memory recipients,
        uint256[] memory amounts,
        uint256 batchSize
    )
        external
    {
        uint256 normalizedBatchSize = batchSize == 0 ? type(uint256).max : batchSize;
        _execute(
            DirectAllocationStrategy(strategyAddress),
            campaignId,
            recipients,
            amounts,
            normalizedBatchSize,
            false,
            msg.sender
        );
    }

    function _loadAllocations(string memory csvPath, bool skipHeader)
        internal
        returns (address[] memory recipients, uint256[] memory amounts)
    {
        string[] memory cmd = new string[](5);
        cmd[0] = "bun";
        cmd[1] = "run";
        cmd[2] = "script/utils/convertDirectAllocations.ts";
        cmd[3] = csvPath;
        cmd[4] = skipHeader ? "true" : "false";

        bytes memory output = vm.ffi(cmd);
        string memory json = string(output);

        recipients = abi.decode(vm.parseJson(json, ".recipients"), (address[]));
        string[] memory amountStrings = abi.decode(vm.parseJson(json, ".amounts"), (string[]));

        amounts = new uint256[](amountStrings.length);
        for (uint256 i = 0; i < amountStrings.length; ++i) {
            amounts[i] = _parseUint(amountStrings[i], i);
        }
    }

    function _execute(
        DirectAllocationStrategy strategy,
        uint256 campaignId,
        address[] memory recipients,
        uint256[] memory amounts,
        uint256 batchSize,
        bool useBroadcast,
        address caller
    )
        internal
    {
        if (recipients.length != amounts.length) {
            revert MismatchedAllocationArrays();
        }

        uint256 total = recipients.length;
        uint256 cursor = 0;
        while (cursor < total) {
            uint256 end = cursor + batchSize;
            if (end > total) {
                end = total;
            }

            uint256 span = end - cursor;
            address[] memory batchRecipients = new address[](span);
            uint256[] memory batchAmounts = new uint256[](span);

            for (uint256 i = 0; i < span; ++i) {
                batchRecipients[i] = recipients[cursor + i];
                batchAmounts[i] = amounts[cursor + i];
            }

            if (useBroadcast) {
                console.log("Setting allocations batch:", cursor, "->", end - 1);
            }

            if (useBroadcast) {
                strategy.setAllocations(campaignId, batchRecipients, batchAmounts);
            } else {
                vm.prank(caller);
                strategy.setAllocations(campaignId, batchRecipients, batchAmounts);
            }
            cursor = end;
        }
    }

    function _parseUint(string memory value, uint256 index) internal pure returns (uint256 result) {
        bytes memory raw = bytes(value);
        if (raw.length == 0) {
            revert InvalidAmountEncoding(index);
        }

        for (uint256 i = 0; i < raw.length; ++i) {
            uint8 char = uint8(raw[i]);
            if (char < 48 || char > 57) {
                revert InvalidAmountEncoding(index);
            }
            result = result * 10 + (char - 48);
        }
    }
}
