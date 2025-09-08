// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.29 <0.9.0;

import { CapitalDistributorPlugin } from "../src/CapitalDistributorPlugin.sol";
import { AragonTest } from "./helpers/AragonTest.sol";
import { AllocatorStrategyMock } from "./mocks/AllocatorStrategyMock.sol";
import {
    IVault, VaultDepositPayoutActionEncoder
} from "../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";

import { MintableERC20 } from "./mocks/MintableERC20.sol";
import { ERC4626Mock } from "./mocks/ERC4626Mock.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";

contract CapitalDistributorPluginTest is AragonTest {
    CapitalDistributorPlugin capitalDistributorPlugin;
    AllocatorStrategyMock strategy;
    MintableERC20 token;
    ERC4626Mock vaultToSendTokens;
    VaultDepositPayoutActionEncoder vaultDepositActionEncoder;
    ExecuteSelectorCondition condition;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Instantiate the contract-under-test.
        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddress[0]);
        condition = ExecuteSelectorCondition(conditions[0]);
        token = new MintableERC20();
        strategy = new AllocatorStrategyMock();
        // Add the strategy to the StrategyFactory
        allocatorStrategyFactory.registerStrategyType(toBytes32("mock-strategy"), address(strategy), "", address(0), 0);

        vaultToSendTokens = new ERC4626Mock(address(token));

        // Add token transfer permission to the plugin
        ExecuteSelectorCondition.SelectorTarget memory selectorToAllow =
            ExecuteSelectorCondition.SelectorTarget({ where: address(token), selectors: new bytes4[](1) });
        selectorToAllow.selectors[0] = IERC20.transfer.selector;

        vm.prank(address(createdDao));
        condition.allowSelectors(selectorToAllow);
    }

    function test_CreateCampaign() public {
        vm.startPrank(address(createdDao));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("mock-strategy"),
                allocatorDeploymentParams,
                metadata // Doesn't have to be metadata, just empty bytes
            ),
            CapitalDistributorPlugin.PayoutConfig(
                IERC20(token),
                bytes32(0),
                metadata // Doesn't have to be metadata, just empty bytes
            ),
            CapitalDistributorPlugin.CampaignSettings(false, 0, 0)
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.metadataUri, metadata, "Metadata not equal");
        assertTrue(address(campaign.allocationStrategy) != address(0), "Allocation strategy not set");
    }

    function test_CannotCreateCampaignWithoutPermissions() public {
        vm.startPrank(address(alice));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("mock-strategy"),
                allocatorDeploymentParams,
                metadata // Doesn't have to be metadata, just empty bytes
            ),
            CapitalDistributorPlugin.PayoutConfig(
                IERC20(token),
                bytes32(0),
                metadata // Doesn't have to be metadata, just empty bytes
            ),
            CapitalDistributorPlugin.CampaignSettings(false, 0, 0)
        );
    }

    function test_PayoutIsSent() public {
        token.mint(address(createdDao), 1 ether);
        vm.startPrank(address(createdDao));
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("mock-strategy"),
                allocatorDeploymentParams,
                metadata // Doesn't have to be metadata, just empty bytes
            ),
            CapitalDistributorPlugin.PayoutConfig(
                IERC20(token),
                bytes32(0),
                metadata // Doesn't have to be metadata, just empty bytes
            ),
            CapitalDistributorPlugin.CampaignSettings(false, 0, 0)
        );

        assertEq(token.balanceOf(address(createdDao)), 1 ether, "DAO doesn't have funds");
        assertEq(token.balanceOf(alice), 0 ether, "Alice has funds");
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, metadata, "");
        assertEq(token.balanceOf(address(createdDao)), 0 ether, "DAO has funds");
        assertEq(token.balanceOf(alice), 1 ether, "Alice has funds");
    }

    function test_PayoutIsSentToVault() public {
        token.mint(address(createdDao), 1 ether);
        bytes memory metadata = "";
        bytes memory allocatorDeploymentParams = "";

        // Add vault deposit permission to the plugin
        ExecuteSelectorCondition.SelectorTarget memory selectorToAllow =
            ExecuteSelectorCondition.SelectorTarget({ where: address(vaultToSendTokens), selectors: new bytes4[](1) });
        selectorToAllow.selectors[0] = IVault.deposit.selector;

        vm.prank(address(createdDao));
        condition.allowSelectors(selectorToAllow);

        // Add token approve permission to the plugin
        selectorToAllow = ExecuteSelectorCondition.SelectorTarget({ where: address(token), selectors: new bytes4[](1) });
        selectorToAllow.selectors[0] = IERC20.approve.selector;

        vm.prank(address(createdDao));
        condition.allowSelectors(selectorToAllow);

        uint256 campaignId = 0;

        vm.startPrank(address(createdDao));
        capitalDistributorPlugin.createCampaign(
            metadata,
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("mock-strategy"),
                allocatorDeploymentParams,
                metadata // Doesn't have to be metadata, just empty bytes
            ),
            CapitalDistributorPlugin.PayoutConfig(
                IERC20(token), toBytes32("vault-deposit-encoder"), abi.encode(address(vaultToSendTokens))
            ),
            CapitalDistributorPlugin.CampaignSettings(false, 0, 0)
        );

        assertEq(token.balanceOf(address(createdDao)), 1 ether, "DAO doesn't have funds");
        assertEq(token.balanceOf(alice), 0 ether, "Alice has funds");
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, metadata, "");
        assertEq(token.balanceOf(address(createdDao)), 0 ether, "DAO has funds");
        assertEq(token.balanceOf(address(vaultToSendTokens)), 1 ether, "Vault has funds");
    }
}
