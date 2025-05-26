// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

import {ProtocolFactoryBuilder} from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";
import {ProtocolFactory} from "@aragon/protocol-factory/src/ProtocolFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {CapitalDistributorPlugin} from "../../src/CapitalDistributorPlugin.sol";
import {CapitalDistributorPluginSetup} from "../../src/CapitalDistributorPluginSetup.sol";

contract AragonTest is Test {
    // Actors
    address constant ALICE_ADDRESS = address(0xa11ce000a11ce000a11ce000a11ce000a11ce);
    address constant BOB_ADDRESS = address(0xB0B00000000B0B00000000B0B00000000B0B0);
    address constant CAROL_ADDRESS = address(0xc4601000c4601000c4601000c4601000c4601);
    address constant DAVID_ADDRESS = address(0xd471d000d471d000d471d000d471d000d471d);

    address immutable alice = ALICE_ADDRESS;
    address immutable bob = BOB_ADDRESS;
    address immutable carol = CAROL_ADDRESS;
    address immutable david = DAVID_ADDRESS;
    address immutable randomWallet = vm.addr(1234567890);

    address immutable DAO_BASE = address(new DAO());

    bytes internal constant EMPTY_BYTES = "";
    ProtocolFactory.Deployment public deployment;
    address[] pluginAddress;

    DAO createdDAO;

    constructor() {
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(carol, "Carol");
        vm.label(david, "David");
        vm.label(randomWallet, "Random wallet");
        // Using the default parameters
        ProtocolFactory factory = new ProtocolFactoryBuilder().build();
        factory.deployOnce();

        // Get the deployed addresses
        deployment = factory.getDeployment();

        // 1. Deploying the Plugin Setup
        CapitalDistributorPluginSetup pluginSetup = deployPluginSetup();

        // 2. Publishing it in the Aragon OSx Protocol
        PluginRepo pluginRepo = deployPluginRepo(address(pluginSetup));

        // 3. Defining the DAO Settings
        DAOFactory.DAOSettings memory daoSettings = getDAOSettings();

        // 4. Defining the plugin settings
        DAOFactory.PluginSettings[] memory pluginSettings = getPluginSettings(pluginRepo);

        // 5. Deploying the DAO
        vm.recordLogs();
        (createdDAO, ) = DAOFactory(deployment.daoFactory).createDao(daoSettings, pluginSettings);

        // 6. Getting the Plugin Address
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
        pluginRepo = PluginRepoFactory(deployment.pluginRepoFactory).createPluginRepoWithFirstVersion(
            "capital-distributor",
            pluginSetup,
            msg.sender,
            "0x00",
            "0x00"
        );
    }

    function getDAOSettings() public pure returns (DAOFactory.DAOSettings memory) {
        return DAOFactory.DAOSettings(address(0), "", "capital-distributor", "");
    }

    function getPluginSettings(
        PluginRepo pluginRepo
    ) public pure returns (DAOFactory.PluginSettings[] memory pluginSettings) {
        bytes memory pluginSettingsData = bytes("");
        PluginRepo.Tag memory tag = PluginRepo.Tag(1, 1);
        pluginSettings = new DAOFactory.PluginSettings[](1);
        pluginSettings[0] = DAOFactory.PluginSettings(PluginSetupRef(tag, pluginRepo), pluginSettingsData);
    }
}
