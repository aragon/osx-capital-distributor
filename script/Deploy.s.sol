// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

// import { Foo } from "../src/Foo.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import {CapitalDistributorPluginSetup} from "../src/CapitalDistributorPluginSetup.sol";
import {AllocatorStrategyFactory} from "../src/AllocatorStrategyFactory.sol";
import {ActionEncoderFactory} from "../src/ActionEncoderFactory.sol";
import {VaultDepositPayoutActionEncoder} from "../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";

import {BaseScript} from "./Base.s.sol";

contract Deploy is BaseScript {
    PluginRepoFactory pluginRepoFactory;
    DAOFactory daoFactory;
    string nameWithEntropy;
    string daoName;
    address[] pluginAddress;

    AllocatorStrategyFactory public allocatorStrategyFactory;
    ActionEncoderFactory public actionEncoderFactory;

    DAO createdDAO;

    function setUp() public {
        pluginRepoFactory = PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY"));
        daoFactory = DAOFactory(vm.envAddress("DAO_FACTORY"));
        nameWithEntropy = vm.envOr(
            "osx-capital-distributor",
            string.concat("osx-capital-distributor-", vm.toString(block.timestamp))
        );
        daoName = vm.envOr(
            "osx-capital-distributor",
            string.concat("osx-capital-distributor-", vm.toString(block.timestamp))
        );
    }

    function run() public broadcast {
        // 0. Setting up foundry
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // 1. Deploy the Factories
        allocatorStrategyFactory = new AllocatorStrategyFactory();
        actionEncoderFactory = new ActionEncoderFactory();
        // 2. Add the AllocationStrategies to the Factory registry
        // 3. Add the ActionEncoders to the Factory registry
        VaultDepositPayoutActionEncoder vaultDepositPayoutActionEncoder = new VaultDepositPayoutActionEncoder();
        actionEncoderFactory.registerActionEncoder(
            toBytes32("vault-deposit-encoder"),
            address(vaultDepositPayoutActionEncoder),
            ""
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
        (createdDAO, ) = daoFactory.createDao(daoSettings, pluginSettings);

        Vm.Log[] memory logEntries = vm.getRecordedLogs();
        for (uint256 i = 0; i < logEntries.length; i++) {
            if (logEntries[i].topics[0] == keccak256("InstallationApplied(address,address,bytes32,bytes32)")) {
                pluginAddress.push(address(uint160(uint256(logEntries[i].topics[2]))));
            }
        }
    }

    function deployPluginSetup() internal returns (CapitalDistributorPluginSetup) {
        CapitalDistributorPluginSetup pluginSetup = new CapitalDistributorPluginSetup();
        return pluginSetup;
    }

    function deployPluginRepo(address pluginSetup) public returns (PluginRepo pluginRepo) {
        pluginRepo = pluginRepoFactory.createPluginRepoWithFirstVersion(
            nameWithEntropy,
            pluginSetup,
            msg.sender,
            "",
            ""
        );
    }

    function getDAOSettings() internal view returns (DAOFactory.DAOSettings memory) {
        return DAOFactory.DAOSettings(address(0), "", daoName, "");
    }

    function getPluginSettings(
        PluginRepo pluginRepo
    ) public view returns (DAOFactory.PluginSettings[] memory pluginSettings) {
        bytes memory pluginSettingsData = abi.encode(address(allocatorStrategyFactory), address(actionEncoderFactory));
        PluginRepo.Tag memory tag = PluginRepo.Tag(1, 1);
        pluginSettings = new DAOFactory.PluginSettings[](1);
        pluginSettings[0] = DAOFactory.PluginSettings(PluginSetupRef(tag, pluginRepo), pluginSettingsData);
    }

    function toBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        require(temp.length <= 32, "String too long");

        assembly ("memory-safe") {
            result := mload(add(temp, 32))
        }
    }
}
