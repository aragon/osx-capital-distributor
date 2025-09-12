// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.29 <0.9.0;

// import { Foo } from "../src/Foo.sol";
import { console2 } from "forge-std/console2.sol";

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
    PluginRepoFactory pluginRepoFactory;
    DAOFactory daoFactory;
    PluginRepo adminRepo;
    string nameWithEntropy;
    string daoName;
    address[] pluginAddress;
    address adminOwner;
    uint32 feeBasisPoints;
    address feeRecipient;

    AllocatorStrategyFactory public allocatorStrategyFactory;
    ActionEncoderFactory public actionEncoderFactory;

    DAO createdDAO;

    function setUp() public {
        pluginRepoFactory = PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY"));
        daoFactory = DAOFactory(vm.envAddress("DAO_FACTORY"));
        adminRepo = PluginRepo(vm.envAddress("ADMIN_REPO"));
        adminOwner = vm.envAddress("ADMIN_OWNER");
        nameWithEntropy =
            vm.envOr("PLUGIN_NAME", string.concat("osx-capital-distributor-", vm.toString(block.timestamp)));
        daoName = vm.envOr("DAO_NAME", string.concat("osx-capital-distributor-", vm.toString(block.timestamp)));
        feeRecipient = vm.envOr("FEE_RECIPIENT", address(0));
        feeBasisPoints = uint32(vm.envOr("FEE_BASIS_POINTS", uint256(0)));
    }

    function run() public broadcast {
        // 1. Deploy the Factories
        allocatorStrategyFactory = new AllocatorStrategyFactory();
        actionEncoderFactory = new ActionEncoderFactory();
        // 2. Add the AllocationStrategies to the Factory registry
        MerkleDistributorStrategy merkleDistributorStrategy = new MerkleDistributorStrategy();
        allocatorStrategyFactory.registerStrategyType(
            toBytes32("merkle-distributor-strategy"),
            address(merkleDistributorStrategy),
            "0x00",
            feeRecipient,
            feeBasisPoints
        );

        // 3. Add the ActionEncoders to the Factory registry
        VaultDepositPayoutActionEncoder vaultDepositPayoutActionEncoder = new VaultDepositPayoutActionEncoder();
        actionEncoderFactory.registerActionEncoder(
            toBytes32("vault-deposit-encoder"), address(vaultDepositPayoutActionEncoder), "0x00"
        );

        // 4. Deploying the Plugin Setup
        CapitalDistributorPluginSetup pluginSetup = deployPluginSetup();

        // 5. Publishing in the Aragon OSx Plugin Repository
        PluginRepo pluginRepo = deployPluginRepo(address(pluginSetup));

        // 6. Defining the DAO Settings
        DAOFactory.DAOSettings memory daoSettings = getDAOSettings();

        // 7. Defining the plugin settings
        DAOFactory.PluginSettings[] memory pluginSettings = getPluginSettings(pluginRepo);

        // 8. Deploying the DAO
        // Two plugins, one is the capital distributor and the other one is the Admin Plugin
        DAOFactory.InstalledPlugin[] memory installedPlugins = new DAOFactory.InstalledPlugin[](2);
        (createdDAO, installedPlugins) = daoFactory.createDao(daoSettings, pluginSettings);

        console2.log("ACTION_ENCODER_FACTORY=", address(actionEncoderFactory));
        console2.log("ALLOCATOR_STRATEGY_FACTORY=", address(allocatorStrategyFactory));
        console2.log("DAO=", address(createdDAO));
        console2.log("PLUGIN=", installedPlugins[0].plugin);
    }

    function deployPluginSetup() internal returns (CapitalDistributorPluginSetup) {
        CapitalDistributorPluginSetup pluginSetup = new CapitalDistributorPluginSetup();
        return pluginSetup;
    }

    function deployPluginRepo(address pluginSetup) public returns (PluginRepo pluginRepo) {
        pluginRepo =
            pluginRepoFactory.createPluginRepoWithFirstVersion(nameWithEntropy, pluginSetup, msg.sender, "0x00", "0x00");
    }

    function getDAOSettings() internal view returns (DAOFactory.DAOSettings memory) {
        return DAOFactory.DAOSettings(address(0), "", daoName, "");
    }

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
}
