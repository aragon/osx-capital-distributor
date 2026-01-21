// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { console2 as console } from "forge-std/console2.sol";

import { BaseScript } from "./Base.s.sol";

import {
    CDPDeployer,
    CDPInfraParams,
    CDPInfraDeployment,
    CDPWithDAOParams,
    CDPWithDAODeployment,
    OSxAddresses,
    ConditionConfig,
    EncoderType
} from "../src/deploy/CDPDeployer.sol";
import { AllocatorStrategyFactory } from "../src/factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../src/factories/ActionEncoderFactory.sol";
import { MerkleDistributorStrategy } from "../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import {
    VotingEscrowLockPayoutActionEncoder
} from "../src/payoutActionEncoders/VotingEscrowLockPayoutActionEncoder.sol";
import { VaultDepositPayoutActionEncoder } from "../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";
import { CapitalDistributorPlugin } from "../src/CapitalDistributorPlugin.sol";

import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Deploy
/// @notice Production deploy script for deploying Capital Distributor Plugin
/// @dev Reads configuration from .env file. Copy .env.example to .env and configure.
///
/// Required Environment Variables (in .env):
/// - DAO_FACTORY: OSx DAOFactory address (for your deployment chain)
/// - PLUGIN_REPO_FACTORY: OSx PluginRepoFactory address (for your deployment chain)
/// - ADMIN_PLUGIN_REPO: Admin plugin repo address (for your deployment chain)
/// - DAO_ADMIN: Address that will control the Admin plugin
/// - PLUGIN_MAINTAINER: Address that can maintain the plugin repo
/// - CHAIN_NAME: Chain name for RPC selection (e.g., "katana")
/// - ENCODER_TYPE: Which encoder to deploy: "vault" or "ve" (default: "vault")
///
/// Usage:
/// ```bash
/// # 1. Copy .env.example to .env and configure DAO_ADMIN and PLUGIN_MAINTAINER
/// cp .env.example .env
///
/// # 2. Deploy with vault deposit encoder (default)
/// forge script script/Deploy.s.sol --broadcast
///
/// # 3. Or deploy with voting escrow encoder (set ENCODER_TYPE=ve in .env)
/// forge script script/Deploy.s.sol --broadcast
/// ```
contract Deploy is BaseScript {
    // Deployer helper
    CDPDeployer public deployer;

    // Deployed contracts
    AllocatorStrategyFactory public strategyFactory;
    ActionEncoderFactory public encoderFactory;
    MerkleDistributorStrategy public merkleStrategy;
    VotingEscrowLockPayoutActionEncoder public veEncoder;
    VaultDepositPayoutActionEncoder public vaultEncoder;
    PluginRepo public pluginRepo;
    DAO public dao;
    CapitalDistributorPlugin public cdpPlugin;
    ExecuteSelectorCondition public condition;
    address public adminPlugin;

    function run() public broadcast {
        console.log("\n=== CDP Deployment Script ===");
        console.log("Chain ID:", block.chainid);

        deployer = new CDPDeployer();

        _deployInfrastructure();
        _createDAOWithPlugins(); // Also creates plugin repo via deployer.deployDAOWithCDP()
        // needs to be called by the DAO
        // _configureConditionIfNeeded();

        _logResults();
        _saveDeployment();
    }

    function _deployInfrastructure() internal {
        console.log("\nDeploying infrastructure...");

        CDPInfraDeployment memory infra = deployer.deployInfrastructure(
            CDPInfraParams({
                feeRecipient: vm.envOr("FEE_RECIPIENT", address(0)),
                feeBasisPoints: uint32(vm.envOr("FEE_BASIS_POINTS", uint256(0))),
                encoderType: _parseEncoderType()
            })
        );

        // Store deployed contracts
        strategyFactory = infra.strategyFactory;
        encoderFactory = infra.encoderFactory;
        merkleStrategy = infra.merkleStrategy;
        veEncoder = infra.votingEscrowEncoder;
        vaultEncoder = infra.vaultDepositEncoder;

        console.log("  StrategyFactory:", address(strategyFactory));
        console.log("  EncoderFactory:", address(encoderFactory));
        console.log("  MerkleStrategy:", address(merkleStrategy));
        if (address(veEncoder) != address(0)) {
            console.log("  VotingEscrowEncoder:", address(veEncoder));
        }
        if (address(vaultEncoder) != address(0)) {
            console.log("  VaultDepositEncoder:", address(vaultEncoder));
        }
    }

    function _createDAOWithPlugins() internal {
        console.log("\nCreating DAO with plugins...");

        CDPWithDAODeployment memory deployment = deployer.deployDAOWithCDP(
            CDPWithDAOParams({
                osx: OSxAddresses({
                    daoFactory: vm.envAddress("DAO_FACTORY"),
                    pluginRepoFactory: vm.envAddress("PLUGIN_REPO_FACTORY"),
                    pluginSetupProcessor: vm.envOr("PLUGIN_SETUP_PROCESSOR", address(0)),
                    adminPluginRepo: vm.envAddress("ADMIN_PLUGIN_REPO"),
                    multisigPluginRepo: address(0) // Not used for CDP-only deployment
                }),
                infra: CDPInfraDeployment({
                    strategyFactory: strategyFactory,
                    encoderFactory: encoderFactory,
                    merkleStrategy: merkleStrategy,
                    votingEscrowEncoder: veEncoder,
                    vaultDepositEncoder: vaultEncoder
                }),
                daoAdmin: vm.envAddress("DAO_ADMIN"),
                daoUri: vm.envOr("DAO_URI", string("ipfs://cdp")),
                daoName: vm.envOr("DAO_NAME", string.concat("cdp-", vm.toString(block.timestamp))),
                pluginRepoSubdomain: vm.envOr(
                    "PLUGIN_NAME", string.concat("cdp-plugin-", vm.toString(block.timestamp))
                ),
                pluginMaintainer: vm.envAddress("PLUGIN_MAINTAINER")
            })
        );

        // Store deployed contracts
        dao = deployment.dao;
        cdpPlugin = deployment.capitalDistributorPlugin;
        condition = deployment.executeCondition;
        adminPlugin = deployment.adminPlugin;
        pluginRepo = deployment.pluginRepo;

        console.log("  DAO:", address(dao));
        console.log("  CDP Plugin:", address(cdpPlugin));
        console.log("  Condition:", address(condition));
        console.log("  Admin Plugin:", adminPlugin);
    }

    function _configureConditionIfNeeded() internal {
        address votingEscrow = vm.envOr("VOTING_ESCROW", address(0));
        if (votingEscrow == address(0)) {
            console.log("\nNo VOTING_ESCROW provided, skipping condition configuration");
            return;
        }

        address token = vm.envAddress("TOKEN");
        console.log("\nConfiguring condition for VotingEscrow...");
        console.log("  Token:", token);
        console.log("  VotingEscrow:", votingEscrow);

        deployer.configureCondition(
            condition,
            ConditionConfig({
                targetOne: token,
                selectorOne: IERC20.approve.selector,
                targetTwo: votingEscrow,
                selectorTwo: bytes4(keccak256("createLockFor(uint256,address)"))
            })
        );

        console.log("  Condition configured successfully");
    }

    function _parseEncoderType() internal view returns (EncoderType) {
        string memory encoderStr = vm.envOr("ENCODER_TYPE", string("vault"));
        bytes32 encoderHash = keccak256(bytes(encoderStr));

        if (encoderHash == keccak256("vault")) {
            return EncoderType.VaultDeposit;
        } else if (encoderHash == keccak256("ve") || encoderHash == keccak256("voting-escrow")) {
            return EncoderType.VotingEscrow;
        } else {
            revert(string.concat("Invalid ENCODER_TYPE: ", encoderStr, ". Use 'vault' or 've'"));
        }
    }

    function _logResults() internal view {
        console.log("\n===========================================");
        console.log("Deployment Complete!");
        console.log("===========================================");
        console.log("DAO:", address(dao));
        console.log("Capital Distributor Plugin:", address(cdpPlugin));
        console.log("Execute Condition:", address(condition));
        console.log("Admin Plugin:", adminPlugin);
        console.log("Plugin Repo:", address(pluginRepo));
        console.log("Strategy Factory:", address(strategyFactory));
        console.log("Encoder Factory:", address(encoderFactory));
        console.log("Merkle Strategy:", address(merkleStrategy));
        if (address(veEncoder) != address(0)) {
            console.log("VotingEscrow Encoder:", address(veEncoder));
        }
        if (address(vaultEncoder) != address(0)) {
            console.log("VaultDeposit Encoder:", address(vaultEncoder));
        }
    }

    // =========================================================================
    // Deployment File Saving
    // =========================================================================

    function _saveDeployment() internal {
        string memory filename = string.concat(
            "deployments/deployment-", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".json"
        );

        string memory json = string.concat(_jsonHeader(), _jsonAddresses(), _jsonEncoders(), _jsonClose());

        vm.writeFile(filename, json);
        console.log("\nDeployment saved to:", filename);
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
            '  "encoderType": "',
            _getEncoderTypeString(),
            '",\n'
        );
    }

    function _jsonAddresses() internal view returns (string memory) {
        return string.concat(
            '  "dao": "',
            vm.toString(address(dao)),
            '",\n',
            '  "capitalDistributorPlugin": "',
            vm.toString(address(cdpPlugin)),
            '",\n',
            '  "executeCondition": "',
            vm.toString(address(condition)),
            '",\n',
            '  "adminPlugin": "',
            vm.toString(adminPlugin),
            '",\n',
            _jsonAddressesContinued()
        );
    }

    function _jsonAddressesContinued() internal view returns (string memory) {
        return string.concat(
            '  "pluginRepo": "',
            vm.toString(address(pluginRepo)),
            '",\n',
            '  "strategyFactory": "',
            vm.toString(address(strategyFactory)),
            '",\n',
            '  "encoderFactory": "',
            vm.toString(address(encoderFactory)),
            '",\n',
            '  "merkleStrategy": "',
            vm.toString(address(merkleStrategy)),
            '",\n'
        );
    }

    function _jsonEncoders() internal view returns (string memory) {
        return string.concat(
            '  "votingEscrowEncoder": "',
            vm.toString(address(veEncoder)),
            '",\n',
            '  "vaultDepositEncoder": "',
            vm.toString(address(vaultEncoder)),
            '"\n'
        );
    }

    function _jsonClose() internal pure returns (string memory) {
        return "}";
    }

    function _getEncoderTypeString() internal view returns (string memory) {
        if (address(veEncoder) != address(0)) return "ve";
        if (address(vaultEncoder) != address(0)) return "vault";
        return "none";
    }
}
