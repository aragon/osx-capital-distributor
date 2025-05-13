// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {CapitalDistributorPlugin} from "../src/CapitalDistributorPlugin.sol";
import {AragonTest} from "./helpers/AragonTest.sol";
import {IAllocatorStrategy} from "../src/interfaces/IAllocatorStrategy.sol";

contract CapitalDistributorPluginTest is AragonTest {
    CapitalDistributorPlugin capitalDistributorPlugin;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Instantiate the contract-under-test.
        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddress[0]);
    }

    function test_CreateCampaign() public {
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";

        vm.expectEmit();
        emit CapitalDistributorPlugin.CampaignCreated(0, "", address(0), address(0));
        uint256 campaignId = capitalDistributorPlugin.setCampaign(0, metadata, address(0), address(0));

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.metadataURI, metadata, "Metadata not equal");
        assertEq(address(campaign.allocationStrategy), address(0), "AllocationStrategy not equal");
        assertEq(address(campaign.vault), address(0), "Vault not equal");
    }

    function test_CannotCreateCampaignWithoutPermissions() public {
        vm.startPrank(address(alice));
        bytes memory metadata = "";

        vm.expectRevert();
        capitalDistributorPlugin.setCampaign(0, metadata, address(0), address(0));
    }
}
