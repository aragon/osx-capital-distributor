// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { CapitalDistributorPlugin } from "../../src/CapitalDistributorPlugin.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";

interface IAdmin {
    function createProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint64,
        uint64,
        bytes memory _data
    )
        external
        returns (uint256 proposalId);

    function executeProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint256 _allowFailureMap
    )
        external
        returns (uint256 proposalId);
}

/**
 * @title CreateMerkleCampaign
 * @notice Script to create a Merkle distribution campaign in the CapitalDistributorPlugin
 * @dev Usage:
 *      forge script scripts/utils/CreateMerkleCampaign.s.sol:CreateMerkleCampaign \
 *      --rpc-url $RPC_URL \
 *      --private-key $PRIVATE_KEY \
 *      --sig "run(address,bytes32,address,uint256,string,uint64,uint64)" \
 *      $PLUGIN_ADDRESS \
 *      $MERKLE_ROOT \
 *      $TOKEN_ADDRESS \
 *      $BUDGET \
 *      $METADATA_URI \
 *      $START_DATE \
 *      $END_DATE
 */
contract CreateMerkleCampaign is Script {
    // Strategy type identifier for merkle-strategy
    bytes32 MERKLE_STRATEGY_TYPE = toBytes32("merkle-distributor-strategy");

    function toBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        require(temp.length <= 32, "String too long");

        assembly ("memory-safe") {
            result := mload(add(temp, 32))
        }
    }

    /**
     * @notice Create a Merkle campaign using environment variables
     * @dev Reads configuration from .env file:
     *      - DAO_ADDRESS: Address of the DAO
     *      - ADMIN_PLUGIN_ADDRESS: Address of the Admin plugin
     *      - CAPITAL_DISTRIBUTOR_ADDRESS: Address of the CapitalDistributorPlugin
     *      - CONDITION_ADDRESS: Address of the ExecuteSelectorCondition contract
     *      - MERKLE_ROOT: The Merkle root for the distribution (as bytes32)
     *      - TOKEN_ADDRESS: Address of the ERC20 token to distribute
     *      - CAMPAIGN_BUDGET: Total budget for the campaign (in wei)
     */
    function run() external {
        vm.createSelectFork("sepolia");

        // Load configuration from environment variables
        address daoAddress = vm.envAddress("DAO_ADDRESS");
        address adminPluginAddress = vm.envAddress("ADMIN_PLUGIN_ADDRESS");
        address pluginAddress = vm.envAddress("CAPITAL_DISTRIBUTOR_ADDRESS");
        address conditionAddress = vm.envAddress("CONDITION_ADDRESS");
        bytes32 merkleRoot = vm.envBytes32("MERKLE_ROOT");
        address token = vm.envAddress("TOKEN_ADDRESS");
        uint256 budget = vm.envUint("CAMPAIGN_BUDGET");

        console.log("Creating Merkle Campaign Proposal through Admin Plugin...");
        console.log("DAO:", daoAddress);
        console.log("Admin Plugin:", adminPluginAddress);
        console.log("Capital Distributor Plugin:", pluginAddress);
        console.log("ExecuteSelectorCondition:", conditionAddress);
        console.log("Merkle Root:");
        console.logBytes32(merkleRoot);
        console.log("Token:", token);
        console.log("Budget:", budget);

        // Load optional metadata URI or use default
        string memory metadataURI = vm.envOr("CAMPAIGN_METADATA_URI", string("ipfs://QmYourCampaignMetadata"));

        // Encode the merkle root for the strategy auxData
        bytes memory strategyAuxData = abi.encode(merkleRoot);

        // Create time bounds
        CapitalDistributorPlugin.CampaignSettings memory settings = CapitalDistributorPlugin.CampaignSettings(0, 0);

        // Prepare actions array (now 3 actions)
        Action[] memory actions = new Action[](3);

        // Action 1: Allow plugin to transfer tokens (for claims)
        console.log("Preparing ExecuteSelectorCondition action...");
        ExecuteSelectorCondition.SelectorTarget memory selectorToAllow =
            ExecuteSelectorCondition.SelectorTarget({ where: address(token), selectors: new bytes4[](1) });
        selectorToAllow.selectors[0] = IERC20.transfer.selector;

        actions[0] = Action({
            to: conditionAddress,
            value: 0,
            data: abi.encodeWithSelector(ExecuteSelectorCondition.allowSelectors.selector, selectorToAllow)
        });

        // Action 2: Transfer tokens from sender to DAO treasury
        console.log("Preparing token transfer action...");
        actions[1] = Action({
            to: token,
            value: 0,
            data: abi.encodeWithSelector(IERC20.transferFrom.selector, msg.sender, daoAddress, budget)
        });

        // Action 3: Create the campaign
        console.log("Preparing campaign creation action...");
        actions[2] = Action({
            to: pluginAddress,
            value: 0,
            data: abi.encodeWithSelector(
                CapitalDistributorPlugin.createCampaign.selector,
                metadataURI,
                CapitalDistributorPlugin.StrategyConfig({
                    strategyId: MERKLE_STRATEGY_TYPE,
                    strategyParams: "", // Merkle strategy doesn't need strategyParams
                    initData: strategyAuxData
                }),
                CapitalDistributorPlugin.PayoutConfig({
                    actionEncoderId: bytes32(0), // No special encoder
                    actionEncoderInitData: "",
                    token: IERC20(token)
                }),
                settings
            )
        });

        // Start broadcasting transaction
        vm.startBroadcast();

        IERC20 tokenContract = IERC20(token);

        // Check token balance
        {
            uint256 balance = tokenContract.balanceOf(msg.sender);
            console.log("Sender token balance:", balance);
            if (balance < budget) {
                revert("Insufficient token balance");
            }
        }

        // Approve DAO to spend tokens
        console.log("Approving DAO to spend tokens...");
        tokenContract.approve(daoAddress, budget);

        // Create proposal through Admin plugin
        console.log("Creating proposal through Admin plugin...");

        // Metadata for the proposal
        bytes memory proposalMetadata = abi.encode(
            "Create Merkle Campaign", "Creating a new Merkle distribution campaign with the provided merkle root"
        );

        // Create the proposal (not execute it)
        uint256 proposalId = IAdmin(adminPluginAddress).createProposal(
            proposalMetadata,
            actions,
            0, // startDate (0 for immediate)
            0, // endDate (0 for no end)
            abi.encode(uint256(0)) // allowFailureMap = 0 (no failures allowed)
        );

        vm.stopBroadcast();

        console.log("Proposal created successfully!");
        console.log("Proposal ID:", proposalId);
    }
}
