// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {IPayoutActionBuilder} from "../src/interfaces/IPayoutActionBuilder.sol";
import {CapitalDistributorPlugin} from "../src/CapitalDistributorPlugin.sol";
import {AragonTest} from "./helpers/AragonTest.sol";
import {IAllocatorStrategy} from "../src/interfaces/IAllocatorStrategy.sol";
import {AllocatorStrategyMock} from "./mocks/AllocatorStrategyMock.sol";

import {MintableERC20} from "./mocks/MintableERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract CapitalDistributorPluginTest is AragonTest {
    CapitalDistributorPlugin capitalDistributorPlugin;
    AllocatorStrategyMock strategy;
    MintableERC20 token;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Instantiate the contract-under-test.
        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddress[0]);
        token = new MintableERC20();
        strategy = new AllocatorStrategyMock(createdDAO, 1 days, true);
    }

    function test_CreateCampaign() public {
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";

        vm.expectEmit();
        emit CapitalDistributorPlugin.CampaignCreated(
            0,
            "",
            address(strategy),
            address(0),
            IERC20(token),
            IPayoutActionBuilder(address(0))
        );
        uint256 campaignId = capitalDistributorPlugin.setCampaign(
            0,
            metadata,
            address(strategy),
            address(0),
            IERC20(token),
            IPayoutActionBuilder(address(0))
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.metadataURI, metadata, "Metadata not equal");
        assertEq(address(campaign.allocationStrategy), address(strategy), "AllocationStrategy not equal");
        assertEq(address(campaign.vault), address(0), "Vault not equal");
    }

    function test_CannotCreateCampaignWithoutPermissions() public {
        vm.startPrank(address(alice));
        bytes memory metadata = "";

        vm.expectRevert();
        capitalDistributorPlugin.setCampaign(
            0,
            metadata,
            address(0),
            address(0),
            IERC20(token),
            IPayoutActionBuilder(address(0))
        );
    }

    function test_PayoutIsSent() public {
        token.mint(address(createdDAO), 1 ether);
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";

        uint256 campaignId = capitalDistributorPlugin.setCampaign(
            0,
            metadata,
            address(strategy),
            address(0),
            IERC20(token),
            IPayoutActionBuilder(address(0))
        );

        assertEq(token.balanceOf(address(createdDAO)), 1 ether, "DAO doesn't have funds");
        assertEq(token.balanceOf(alice), 0 ether, "Alice has funds");
        capitalDistributorPlugin.sendCampaignPayout(campaignId, alice, metadata);
        assertEq(token.balanceOf(address(createdDAO)), 0 ether, "DAO has funds");
        assertEq(token.balanceOf(alice), 1 ether, "Alice has funds");
    }
}
