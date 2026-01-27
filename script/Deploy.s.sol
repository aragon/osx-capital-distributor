// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { console2 as console } from "forge-std/console2.sol";

import { BaseScript } from "./Base.s.sol";

import {
    CDPDeployer,
    CDPInfraParams,
    CDPInfraDeployment,
    OSxAddresses,
    ConditionConfig,
    InstallCDPParams,
    PreparedCDPInstallation,
    VEConditionParams
} from "../src/deploy/CDPDeployer.sol";
import { AllocatorStrategyFactory } from "../src/factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../src/factories/ActionEncoderFactory.sol";
import { MerkleDistributorStrategy } from "../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import {
    VotingEscrowLockPayoutActionEncoder
} from "../src/payoutActionEncoders/VotingEscrowLockPayoutActionEncoder.sol";
import { VaultDepositPayoutActionEncoder } from "../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";
import { CapitalDistributorPlugin } from "../src/CapitalDistributorPlugin.sol";
import { CapitalDistributorPluginSetup } from "../src/CapitalDistributorPluginSetup.sol";

import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Action } from "@aragon/commons/executors/IExecutor.sol";

interface IMultisig {
    function createProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint256 _allowFailureMap,
        bool _approveProposal,
        bool _tryExecution,
        uint64 _startDate,
        uint64 _endDate
    )
        external
        returns (uint256 proposalId);
}

/// @title Deploy
/// @notice Production deploy script for deploying Capital Distributor Plugin into existing DAO (e.g., Katana DAO)
/// @dev Reads configuration from .env file. Copy .env.example to .env and configure.
///
/// Required Environment Variables (in .env):
/// - DAO: The existing DAO address to install CDP into (e.g., Katana DAO)
/// - PLUGIN_REPO_FACTORY: OSx PluginRepoFactory address
/// - PSP: OSx PluginSetupProcessor address
/// - PLUGIN_MAINTAINER: Address that can maintain the plugin repo
/// - TOKEN: The token address (for approve selector in condition)
/// - VOTING_ESCROW: The VotingEscrow address (for createLockFor selector in condition)
/// - MULTISIG_ADDRESS: The Multisig address to create the proposal on
///
/// Optional Environment Variables:
/// - FEE_RECIPIENT: Protocol fee recipient (default: address(0))
/// - FEE_BASIS_POINTS: Protocol fee in basis points (default: 0)
/// - PLUGIN_NAME: Plugin repo subdomain (default: auto-generated with timestamp)
///
/// Usage:
/// ```bash
/// # 1. Copy .env.example to .env and configure
/// cp .env.example .env
///
/// # 2. Run the deployment script
/// forge script script/Deploy.s.sol --broadcast
///
/// # The script will:
/// # - Deploy CDP infrastructure (factories, strategies, encoders)
/// # - Call prepareInstallation() on PSP
/// # - Generate and log calldata for applyInstallation() that Katana team can execute
/// ```
contract Deploy is BaseScript {
    // Deployer helper
    CDPDeployer public deployer;

    // Infrastructure contracts
    AllocatorStrategyFactory public strategyFactory;
    ActionEncoderFactory public encoderFactory;
    MerkleDistributorStrategy public merkleStrategy;
    VotingEscrowLockPayoutActionEncoder public veEncoder;
    VaultDepositPayoutActionEncoder public vaultEncoder;
    CapitalDistributorPluginSetup public pluginSetup;

    // Installation addresses (stored separately to avoid storage issues with nested arrays)
    PluginRepo public pluginRepo;
    DAO public dao;
    CapitalDistributorPlugin public cdpPlugin;
    ExecuteSelectorCondition public condition;
    PluginSetupProcessor public psp;

    // Store calldata/actions for logging (generated during prepareInstallation)
    bytes public applyInstallationCalldata;
    string public actionsJson;

    function run() public broadcast {
        console.log("\n=== CDP Deployment Script (Katana Mainnet) ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", msg.sender);

        deployer = new CDPDeployer();

        // Step 1: Deploy infrastructure
        _deployInfrastructure();

        // Step 2: Prepare installation into existing DAO
        _prepareInstallation();

        // Step 3: Log all addresses and calldata for Katana team
        _logAllAddresses();
        _logApplyInstallationCalldata();

        // Step 4: Save deployment to file
        _saveDeployment();
    }

    function _deployInfrastructure() internal {
        console.log("\n[Step 1] Deploying CDP Infrastructure...");

        // Deploy all infrastructure contracts
        strategyFactory = new AllocatorStrategyFactory();
        encoderFactory = new ActionEncoderFactory();
        merkleStrategy = new MerkleDistributorStrategy();
        veEncoder = new VotingEscrowLockPayoutActionEncoder();
        vaultEncoder = new VaultDepositPayoutActionEncoder();
        pluginSetup = new CapitalDistributorPluginSetup();

        console.log("  StrategyFactory:", address(strategyFactory));
        console.log("  EncoderFactory:", address(encoderFactory));
        console.log("  MerkleStrategy:", address(merkleStrategy));
        console.log("  VotingEscrowEncoder:", address(veEncoder));
        console.log("  VaultDepositEncoder:", address(vaultEncoder));
        console.log("  PluginSetup:", address(pluginSetup));

        // Setup infrastructure (register strategies and encoders)
        deployer.setupInfrastructure(
            CDPInfraParams({
                strategyFactory: address(strategyFactory),
                encoderFactory: address(encoderFactory),
                merkleStrategy: address(merkleStrategy),
                votingEscrowEncoder: address(veEncoder),
                vaultDepositEncoder: address(vaultEncoder),
                feeRecipient: vm.envOr("FEE_RECIPIENT", address(0)),
                feeBasisPoints: uint32(vm.envOr("FEE_BASIS_POINTS", uint256(0)))
            })
        );

        console.log("  Note: Both encoders registered. Use VOTING_ESCROW_ENCODER_ID for VE campaigns.");
    }

    function _prepareInstallation() internal {
        console.log("\n[Step 2] Preparing CDP Installation...");

        // Read existing DAO address from environment
        dao = DAO(payable(vm.envAddress("DAO")));
        psp = PluginSetupProcessor(vm.envAddress("PSP"));

        console.log("  Target DAO:", address(dao));
        console.log("  PSP:", address(psp));

        // Prepare installation params
        InstallCDPParams memory installParams = InstallCDPParams({
            dao: dao,
            osx: OSxAddresses({
                daoFactory: address(0), // Not needed for prepareInstallation
                pluginRepoFactory: vm.envAddress("PLUGIN_REPO_FACTORY"),
                pluginSetupProcessor: address(psp),
                adminPluginRepo: address(0), // Not needed for prepareInstallation
                multisigPluginRepo: address(0) // Not needed for prepareInstallation
            }),
            infra: CDPInfraDeployment({
                strategyFactory: strategyFactory,
                encoderFactory: encoderFactory,
                merkleStrategy: merkleStrategy,
                votingEscrowEncoder: veEncoder,
                vaultDepositEncoder: vaultEncoder
            }),
            pluginSetup: address(pluginSetup),
            pluginMaintainer: vm.envAddress("PLUGIN_MAINTAINER"),
            pluginRepoSubdomain: vm.envOr(
                "PLUGIN_NAME", string.concat("test-cdp-plugin-", vm.toString(block.timestamp))
            )
        });

        // Call prepareInstallation (this is permissionless)
        // Use memory variable to avoid storage issues with nested arrays
        PreparedCDPInstallation memory prepared = deployer.prepareInstallation(installParams);

        // Store only the addresses we need
        pluginRepo = prepared.pluginRepo;
        cdpPlugin = prepared.plugin;
        condition = prepared.condition;

        // Generate and store the applyInstallation calldata immediately
        applyInstallationCalldata = deployer.buildApplyInstallationCalldata(prepared);

        // Read VE params for condition configuration
        VEConditionParams memory veParams =
            VEConditionParams({ token: vm.envAddress("TOKEN"), votingEscrow: vm.envAddress("VOTING_ESCROW") });

        console.log("  Token (for condition):", veParams.token);
        console.log("  VotingEscrow (for condition):", veParams.votingEscrow);

        // Generate and store actions JSON for UI upload
        // Now includes condition configuration for token.approve() and votingEscrow.createLockFor()
        Action[] memory actions = deployer.buildInstallationActions(address(dao), address(psp), prepared, veParams);

        // Encode createProposal call with all the actions
        bytes memory createProposalData = abi.encodeWithSelector(
            IMultisig.createProposal.selector,
            bytes("Bootstrap Katana Vault Ecosystem - Complete Initialization"),
            actions,
            0, // allowFailureMap - all actions must succeed
            true, // approveProposal - approve with caller's signature
            false, // tryExecution - don't try to execute immediately
            uint64(0), // startDate - 0 means now
            block.timestamp + 20_000 // endDate - 0 means use default from settings
        );

        // Create single wrapper action that calls createProposal on multisig
        Action[] memory wrapperAction = new Action[](1);
        wrapperAction[0] = Action({ to: vm.envAddress("MULTISIG_ADDRESS"), value: 0, data: createProposalData });

        actionsJson = _serializeActions(wrapperAction);

        console.log("  Plugin Repo:", address(pluginRepo));
        console.log("  CDP Plugin (prepared):", address(cdpPlugin));
        console.log("  Condition (prepared):", address(condition));
    }

    function _logAllAddresses() internal view {
        console.log("\n===========================================");
        console.log("CDP DEPLOYMENT ADDRESSES");
        console.log("===========================================");

        console.log("\n--- Infrastructure ---");
        console.log("CDPDeployer:", address(deployer));
        console.log("StrategyFactory:", address(strategyFactory));
        console.log("EncoderFactory:", address(encoderFactory));
        console.log("MerkleStrategy:", address(merkleStrategy));
        console.log("VotingEscrowEncoder:", address(veEncoder));
        console.log("VaultDepositEncoder:", address(vaultEncoder));
        console.log("PluginSetup:", address(pluginSetup));

        console.log("\n--- Encoder IDs (for createCampaign PayoutConfig.actionEncoderId) ---");
        console.log("VOTING_ESCROW_ENCODER_ID:", vm.toString(deployer.VOTING_ESCROW_ENCODER_ID()));
        console.log("VAULT_DEPOSIT_ENCODER_ID:", vm.toString(deployer.VAULT_DEPOSIT_ENCODER_ID()));

        console.log("\n--- Prepared Installation ---");
        console.log("Target DAO:", address(dao));
        console.log("PSP:", address(psp));
        console.log("Plugin Repo:", address(pluginRepo));
        console.log("CDP Plugin:", address(cdpPlugin));
        console.log("Execute Condition:", address(condition));
    }

    function _logApplyInstallationCalldata() internal view {
        console.log("\n===========================================");
        console.log("INSTALLATION INSTRUCTIONS FOR KATANA TEAM");
        console.log("===========================================");
        console.log("\nThe DAO needs to execute 5 actions to complete the installation:");
        console.log("  1. dao.grant(dao, psp, ROOT_PERMISSION_ID)");
        console.log("  2. psp.applyInstallation(dao, params)");
        console.log("  3. dao.revoke(dao, psp, ROOT_PERMISSION_ID)");
        console.log("  4. condition.allowSelectors(token, approve)");
        console.log("  5. condition.allowSelectors(votingEscrow, createLockFor)");

        console.log("\n--- RECOMMENDED: Use the actions JSON file ---");
        console.log("Upload the actions-*.json file to the DAO UI.");
        console.log("It contains all 5 actions ready for DAO.execute().");

        console.log("\n--- Individual Calldata (for reference) ---");

        console.log("\n1. Grant ROOT to PSP (target: DAO):");
        console.logBytes(deployer.buildGrantRootToPSPCalldata(address(dao), address(psp)));

        console.log("\n2. Apply Installation (target: PSP):");
        console.logBytes(applyInstallationCalldata);

        console.log("\n3. Revoke ROOT from PSP (target: DAO):");
        console.logBytes(deployer.buildRevokeRootFromPSPCalldata(address(dao), address(psp)));

        console.log("\n4-5. Condition configuration (target: Condition):");
        console.log("  See actions JSON file for full calldata");
    }

    // =========================================================================
    // Deployment File Saving
    // =========================================================================

    function _saveDeployment() internal {
        string memory timestamp = vm.toString(block.timestamp);
        string memory chainId = vm.toString(block.chainid);

        // Save deployment info JSON
        string memory deploymentFilename = string.concat("deployments/deployment-", chainId, "-", timestamp, ".json");
        string memory deploymentJson =
            string.concat(_jsonHeader(), _jsonInfrastructure(), _jsonPreparedInstallation(), _jsonClose());
        vm.writeFile(deploymentFilename, deploymentJson);

        // Save actions JSON (for UI upload)
        string memory actionsFilename = string.concat("deployments/actions-", chainId, "-", timestamp, ".json");
        vm.writeFile(actionsFilename, actionsJson);

        console.log("\n===========================================");
        console.log("FILES SAVED");
        console.log("===========================================");
        console.log("Deployment info:", deploymentFilename);
        console.log("Actions (for UI):", actionsFilename);
    }

    /// @notice Serialize Action array to JSON format expected by the DAO UI
    /// @param _actions Array of actions to serialize
    /// @return serialized JSON string representation of actions
    function _serializeActions(Action[] memory _actions) internal returns (string memory serialized) {
        string memory json = "[";

        for (uint256 i = 0; i < _actions.length; i++) {
            Action memory a = _actions[i];

            // Build individual action JSON
            json = string.concat(
                json,
                '{"to":"',
                vm.toString(a.to),
                '","value":',
                vm.toString(a.value),
                ',"data":"',
                vm.toString(a.data),
                '"}'
            );

            // Add comma if not last element
            if (i < _actions.length - 1) {
                json = string.concat(json, ",");
            }
        }

        json = string.concat(json, "]");
        return json;
    }

    function _jsonHeader() internal view returns (string memory) {
        return string.concat(
            "{\n",
            '  "chainId": ',
            vm.toString(block.chainid),
            ",\n",
            '  "timestamp": ',
            vm.toString(block.timestamp),
            ",\n",
            '  "deployer": "',
            vm.toString(msg.sender),
            '",\n'
        );
    }

    function _jsonInfrastructure() internal view returns (string memory) {
        return string.concat(
            '  "infrastructure": {\n',
            '    "cdpDeployer": "',
            vm.toString(address(deployer)),
            '",\n',
            '    "strategyFactory": "',
            vm.toString(address(strategyFactory)),
            '",\n',
            '    "encoderFactory": "',
            vm.toString(address(encoderFactory)),
            '",\n',
            '    "merkleStrategy": "',
            vm.toString(address(merkleStrategy)),
            '",\n',
            '    "votingEscrowEncoder": "',
            vm.toString(address(veEncoder)),
            '",\n',
            '    "vaultDepositEncoder": "',
            vm.toString(address(vaultEncoder)),
            '",\n',
            '    "pluginSetup": "',
            vm.toString(address(pluginSetup)),
            '"\n',
            "  },\n",
            '  "encoderIds": {\n',
            '    "votingEscrow": "',
            vm.toString(deployer.VOTING_ESCROW_ENCODER_ID()),
            '",\n',
            '    "vaultDeposit": "',
            vm.toString(deployer.VAULT_DEPOSIT_ENCODER_ID()),
            '"\n',
            "  },\n"
        );
    }

    function _jsonPreparedInstallation() internal view returns (string memory) {
        return string.concat(
            '  "preparedInstallation": {\n',
            '    "targetDao": "',
            vm.toString(address(dao)),
            '",\n',
            '    "psp": "',
            vm.toString(address(psp)),
            '",\n',
            '    "pluginRepo": "',
            vm.toString(address(pluginRepo)),
            '",\n',
            '    "cdpPlugin": "',
            vm.toString(address(cdpPlugin)),
            '",\n',
            '    "executeCondition": "',
            vm.toString(address(condition)),
            '"\n',
            "  },\n"
        );
    }

    function _jsonClose() internal pure returns (string memory) {
        return "}";
    }
}
