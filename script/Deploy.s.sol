// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.29 <0.9.0;

// import { Foo } from "../src/Foo.sol";
import { console2 as console } from "forge-std/console2.sol";

import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { DAOFactory } from "@aragon/osx/framework/dao/DAOFactory.sol";

import { IPlugin } from "@aragon/commons/plugin/IPlugin.sol";
import { PluginSetupRef } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import { CapitalDistributorPluginSetup } from "../src/CapitalDistributorPluginSetup.sol";
import { AllocatorStrategyFactory } from "../src/factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../src/factories/ActionEncoderFactory.sol";

// Allocator Strategies
import { MerkleDistributorStrategy } from "../src/allocatorStrategies/MerkleDistributorStrategy.sol";

// Action Encoders
import { VaultDepositPayoutActionEncoder } from "../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";

import { BaseScript } from "./Base.s.sol";

contract Deploy is BaseScript {
    struct DeploymentAddresses {
        uint256 chainId;
        uint256 timestamp;
        string chainName;
        address dao;
        address capitalDistributorPlugin;
        address executeCondition;
        address adminPlugin;
        address pluginSetup;
        address pluginRepo;
        address pluginMaintainer;
        address allocatorStrategyFactory;
        address actionEncoderFactory;
        address merkleDistributorStrategy;
        address vaultDepositPayoutActionEncoder;
        // Metadata
        string daoName;
        string daoUri;
        string pluginName;
        address adminOwner;
        address feeRecipient;
        uint32 feeBasisPoints;
    }

    PluginRepoFactory pluginRepoFactory;
    DAOFactory daoFactory;
    PluginRepo adminRepo;
    string nameWithEntropy;
    string daoName;
    string daoUri;
    address[] pluginAddress;
    address pluginMaintainer;
    address adminOwner;
    uint32 feeBasisPoints;
    address feeRecipient;

    AllocatorStrategyFactory public allocatorStrategyFactory;
    ActionEncoderFactory public actionEncoderFactory;

    DAO createdDAO;
    DeploymentAddresses deployment;

    function setUp() public {
        console.log("\n=== Deploy Script Environment Variables ===");

        string memory chainName = vm.envString("CHAIN_NAME");
        console.log("CHAIN_NAME:", chainName);
        vm.createSelectFork(chainName);

        uint256 timestamp = block.timestamp;
        console.log("Current timestamp:", timestamp);

        pluginRepoFactory = PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY"));
        console.log("PLUGIN_REPO_FACTORY:", address(pluginRepoFactory));

        daoFactory = DAOFactory(vm.envAddress("DAO_FACTORY"));
        console.log("DAO_FACTORY:", address(daoFactory));

        adminRepo = PluginRepo(vm.envAddress("ADMIN_REPO"));
        console.log("ADMIN_REPO:", address(adminRepo));

        adminOwner = vm.envAddress("ADMIN_OWNER");
        console.log("ADMIN_OWNER:", adminOwner);

        nameWithEntropy = vm.envOr("PLUGIN_NAME", string.concat("osx-capital-distributor-", vm.toString(timestamp)));
        console.log("PLUGIN_NAME:", nameWithEntropy);

        pluginMaintainer = vm.envAddress("PLUGIN_MAINTAINER");
        console.log("PLUGIN_MAINTAINER:", pluginMaintainer);

        daoName = vm.envOr("DAO_NAME", string.concat("osx-capital-distributor-", vm.toString(timestamp)));
        console.log("DAO_NAME:", daoName);

        daoUri = vm.envOr("DAO_URI", string.concat("https://dao-uri-", vm.toString(timestamp)));
        console.log("DAO_URI:", daoUri);

        feeRecipient = vm.envOr("FEE_RECIPIENT", address(0));
        console.log("FEE_RECIPIENT:", feeRecipient);

        feeBasisPoints = uint32(vm.envOr("FEE_BASIS_POINTS", uint256(0)));
        console.log("FEE_BASIS_POINTS:", feeBasisPoints);

        console.log("=== End Environment Variables ===\n");
    }

    function run() public broadcast {
        // Initialize deployment struct with metadata
        deployment.chainId = block.chainid;
        deployment.timestamp = block.timestamp;
        deployment.chainName = vm.envString("CHAIN_NAME");
        deployment.daoName = daoName;
        deployment.daoUri = daoUri;
        deployment.pluginName = nameWithEntropy;
        deployment.adminOwner = adminOwner;
        deployment.feeRecipient = feeRecipient;
        deployment.feeBasisPoints = feeBasisPoints;

        // 1. Deploy the Factories
        allocatorStrategyFactory = new AllocatorStrategyFactory();
        actionEncoderFactory = new ActionEncoderFactory();
        deployment.allocatorStrategyFactory = address(allocatorStrategyFactory);
        deployment.actionEncoderFactory = address(actionEncoderFactory);

        // 2. Add the AllocationStrategies to the Factory registry
        MerkleDistributorStrategy merkleDistributorStrategy = new MerkleDistributorStrategy();
        deployment.merkleDistributorStrategy = address(merkleDistributorStrategy);
        allocatorStrategyFactory.registerStrategyType(
            toBytes32("merkle-distributor-strategy"),
            address(merkleDistributorStrategy),
            "0x00",
            feeRecipient,
            feeBasisPoints
        );

        // 3. Add the ActionEncoders to the Factory registry
        VaultDepositPayoutActionEncoder vaultDepositPayoutActionEncoder = new VaultDepositPayoutActionEncoder();
        deployment.vaultDepositPayoutActionEncoder = address(vaultDepositPayoutActionEncoder);
        actionEncoderFactory.registerActionEncoder(
            toBytes32("vault-deposit-encoder"), address(vaultDepositPayoutActionEncoder), "0x00"
        );

        deployment.pluginMaintainer = pluginMaintainer;

        // 4. Deploying the Plugin Setup
        CapitalDistributorPluginSetup pluginSetup = deployPluginSetup();
        deployment.pluginSetup = address(pluginSetup);

        // 5. Publishing in the Aragon OSx Plugin Repository
        PluginRepo pluginRepo = deployPluginRepo(address(pluginSetup));
        deployment.pluginRepo = address(pluginRepo);

        // 6. Defining the DAO Settings
        DAOFactory.DAOSettings memory daoSettings = getDAOSettings();

        // 7. Defining the plugin settings
        DAOFactory.PluginSettings[] memory pluginSettings = getPluginSettings(pluginRepo);

        // 8. Deploying the DAO
        // Two plugins, one is the capital distributor and the other one is the Admin Plugin
        DAOFactory.InstalledPlugin[] memory installedPlugins = new DAOFactory.InstalledPlugin[](2);
        (createdDAO, installedPlugins) = daoFactory.createDao(daoSettings, pluginSettings);

        deployment.dao = address(createdDAO);
        deployment.capitalDistributorPlugin = installedPlugins[0].plugin;
        deployment.executeCondition = installedPlugins[0].preparedSetupData.helpers[0];
        deployment.adminPlugin = installedPlugins[1].plugin;

        console.log("ACTION_ENCODER_FACTORY=", address(actionEncoderFactory));
        console.log("ALLOCATOR_STRATEGY_FACTORY=", address(allocatorStrategyFactory));
        console.log("DAO=", address(createdDAO));
        console.log("PLUGIN=", installedPlugins[0].plugin);
        console.log("EXECUTE_CONDITION=", deployment.executeCondition);

        // Save deployment to file
        saveDeployment();
    }

    function deployPluginSetup() internal returns (CapitalDistributorPluginSetup) {
        CapitalDistributorPluginSetup pluginSetup = new CapitalDistributorPluginSetup();
        return pluginSetup;
    }

    function deployPluginRepo(address pluginSetup) public returns (PluginRepo pluginRepo) {
        pluginRepo = pluginRepoFactory.createPluginRepoWithFirstVersion(
            nameWithEntropy, pluginSetup, pluginMaintainer, "0x00", "0x00"
        );
    }

    function getDAOSettings() internal view returns (DAOFactory.DAOSettings memory) {
        return DAOFactory.DAOSettings(address(0), daoUri, daoName, "");
    }

    address trustedForwarder;
    string daoURI;
    string subdomain;
    bytes metadata;

    function getPluginSettings(PluginRepo pluginRepo)
        public
        view
        returns (DAOFactory.PluginSettings[] memory pluginSettings)
    {
        bytes memory pluginSettingsData = abi.encode(address(allocatorStrategyFactory), address(actionEncoderFactory));
        PluginRepo.Tag memory tag = PluginRepo.Tag(1, 1);
        pluginSettings = new DAOFactory.PluginSettings[](2);
        pluginSettings[0] = DAOFactory.PluginSettings(PluginSetupRef(tag, pluginRepo), pluginSettingsData);

        // Settings for the admin
        IPlugin.TargetConfig memory targetConfig = IPlugin.TargetConfig(address(0), IPlugin.Operation.Call);
        bytes memory adminSettingsData = abi.encode(adminOwner, targetConfig);
        PluginRepo.Tag memory adminTag = PluginRepo.Tag(1, 2);
        pluginSettings[1] = DAOFactory.PluginSettings(PluginSetupRef(adminTag, adminRepo), adminSettingsData);
    }

    function toBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        require(temp.length <= 32, "String too long");

        assembly ("memory-safe") {
            result := mload(add(temp, 32))
        }
    }

    function saveDeployment() internal {
        string memory filename = string.concat(
            "deployments/deployment-", vm.toString(deployment.chainId), "-", vm.toString(deployment.timestamp), ".json"
        );

        // Build JSON in parts to avoid stack too deep
        string memory jsonPart1 = string.concat(
            "{\n",
            '  "chainId": ',
            vm.toString(deployment.chainId),
            ",\n",
            '  "timestamp": ',
            vm.toString(deployment.timestamp),
            ",\n",
            '  "chainName": "',
            deployment.chainName,
            '",\n',
            '  "metadata": {\n',
            '    "daoName": "',
            deployment.daoName,
            '",\n',
            '    "daoUri": "',
            deployment.daoUri,
            '",\n',
            '    "pluginName": "',
            deployment.pluginName,
            '",\n',
            '    "adminOwner": "',
            vm.toString(deployment.adminOwner),
            '",\n',
            '    "feeRecipient": "',
            vm.toString(deployment.feeRecipient),
            '",\n',
            '    "feeBasisPoints": ',
            vm.toString(deployment.feeBasisPoints),
            "\n",
            "  },\n"
        );

        string memory jsonPart2 = string.concat(
            '  "addresses": {\n',
            '    "dao": "',
            vm.toString(deployment.dao),
            '",\n',
            '    "capitalDistributorPlugin": "',
            vm.toString(deployment.capitalDistributorPlugin),
            '",\n',
            '    "adminPlugin": "',
            vm.toString(deployment.adminPlugin),
            '",\n',
            '    "executeCondition": "',
            vm.toString(deployment.executeCondition),
            '",\n',
            '    "pluginSetup": "',
            vm.toString(deployment.pluginSetup),
            '",\n',
            '    "pluginRepo": "',
            vm.toString(deployment.pluginRepo),
            '",\n',
            '    "allocatorStrategyFactory": "',
            vm.toString(deployment.allocatorStrategyFactory),
            '",\n',
            '    "actionEncoderFactory": "',
            vm.toString(deployment.actionEncoderFactory),
            '",\n',
            '    "merkleDistributorStrategy": "',
            vm.toString(deployment.merkleDistributorStrategy),
            '",\n',
            '    "vaultDepositPayoutActionEncoder": "',
            vm.toString(deployment.vaultDepositPayoutActionEncoder),
            '"\n',
            "  }\n",
            "}"
        );

        string memory json = string.concat(jsonPart1, jsonPart2);

        vm.writeFile(filename, json);
        console.log("\nDeployment saved to:", filename);
    }
}
