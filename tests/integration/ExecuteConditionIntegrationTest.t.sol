// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { CapitalDistributorPlugin } from "../../src/CapitalDistributorPlugin.sol";
import { CapitalDistributorPluginSetup } from "../../src/CapitalDistributorPluginSetup.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AllocatorStrategyFactory } from "../../src/factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../../src/factories/ActionEncoderFactory.sol";
import { MintableERC20 } from "../../tests/mocks/MintableERC20.sol";
import { ConfigurableAllocatorStrategyMock } from "../../tests/mocks/ConfigurableAllocatorStrategyMock.sol";

import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { Action } from "@aragon/commons/executors/IExecutor.sol";
import { IPluginSetup } from "@aragon/commons/plugin/setup/IPluginSetup.sol";
import { IPermissionCondition } from "@aragon/commons/permission/condition/IPermissionCondition.sol";
import { PermissionLib } from "@aragon/commons/permission/PermissionLib.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title ExecuteConditionIntegrationTest
/// @notice Integration test showing how the execute condition blocks plugin execution
contract ExecuteConditionIntegrationTest is Test {
    DAO dao;
    CapitalDistributorPlugin plugin;
    ExecuteSelectorCondition condition;
    AllocatorStrategyFactory strategyFactory;
    ActionEncoderFactory encoderFactory;
    MintableERC20 token;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // Permission IDs
    bytes32 constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");
    bytes32 constant CAMPAIGN_MANAGER_PERMISSION_ID = keccak256("CAMPAIGN_MANAGER_PERMISSION");
    bytes32 constant MANAGE_SELECTORS_PERMISSION_ID = keccak256("MANAGE_SELECTORS_PERMISSION");
    bytes32 constant ROOT_PERMISSION_ID = 0x00;

    function setUp() public {
        // Deploy DAO
        dao = DAO(
            payable(
                createProxy(
                    address(new DAO()), abi.encodeCall(DAO.initialize, ("Test DAO", address(this), address(0), ""))
                )
            )
        );

        // Deploy factories
        strategyFactory = new AllocatorStrategyFactory();
        encoderFactory = new ActionEncoderFactory();

        // Register a mock strategy
        strategyFactory.registerStrategyType(
            bytes32("mock-strategy"),
            address(new ConfigurableAllocatorStrategyMock()),
            "Mock Strategy",
            address(0), // no fee recipient
            0 // no fees
        );

        // Deploy plugin using setup
        CapitalDistributorPluginSetup setup = new CapitalDistributorPluginSetup();

        bytes memory installParams = abi.encode(address(strategyFactory), address(encoderFactory));

        IPluginSetup.PreparedSetupData memory preparedSetupData;
        address pluginAddr;
        (pluginAddr, preparedSetupData) = setup.prepareInstallation(address(dao), installParams);

        plugin = CapitalDistributorPlugin(pluginAddr);
        condition = ExecuteSelectorCondition(preparedSetupData.helpers[0]);

        // Apply permissions (simulate PluginSetupProcessor)
        for (uint256 i = 0; i < preparedSetupData.permissions.length; i++) {
            PermissionLib.MultiTargetPermission memory perm = preparedSetupData.permissions[i];

            if (perm.operation == PermissionLib.Operation.Grant) {
                dao.grant(perm.where, perm.who, perm.permissionId);
            } else if (perm.operation == PermissionLib.Operation.GrantWithCondition) {
                dao.grantWithCondition(perm.where, perm.who, perm.permissionId, IPermissionCondition(perm.condition));
            }
        }

        // Setup token
        token = new MintableERC20();
        token.mint(address(dao), 1_000_000 ether);
    }

    function test_ExecuteBlockedByDefault() public {
        // Create a campaign
        vm.startPrank(address(dao));
        uint256 campaignId = plugin.createCampaign(
            "ipfs://test-campaign-metadata",
            CapitalDistributorPlugin.StrategyConfig(bytes32("mock-strategy"), "", ""),
            CapitalDistributorPlugin.PayoutConfig(token, bytes32(0), ""),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );
        vm.stopPrank();

        // Setup allocation for alice
        ConfigurableAllocatorStrategyMock strategy =
            ConfigurableAllocatorStrategyMock(address(plugin.getCampaign(campaignId).allocationStrategy));
        strategy.setClaimableAmount(campaignId, alice, 100 ether);

        // Try to claim - should fail because execute is blocked
        vm.startPrank(alice);
        vm.expectRevert(); // Will revert at the DAO level due to permission condition
        plugin.claimCampaignPayout(campaignId, alice, "", "");
        vm.stopPrank();
    }

    function test_ExecuteAllowedAfterApproval() public {
        // Create a campaign
        vm.startPrank(address(dao));
        uint256 campaignId = plugin.createCampaign(
            "ipfs://test-campaign-metadata",
            CapitalDistributorPlugin.StrategyConfig(bytes32("mock-strategy"), "", ""),
            CapitalDistributorPlugin.PayoutConfig(token, bytes32(0), ""),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        // Setup allocation for alice
        ConfigurableAllocatorStrategyMock strategy =
            ConfigurableAllocatorStrategyMock(address(plugin.getCampaign(campaignId).allocationStrategy));
        strategy.setClaimableAmount(campaignId, alice, 100 ether);

        // Now approve the token transfer selector for the specific token
        ExecuteSelectorCondition.SelectorTarget memory selectorToAllow =
            ExecuteSelectorCondition.SelectorTarget({ where: address(token), selectors: new bytes4[](1) });
        selectorToAllow.selectors[0] = IERC20.transfer.selector;

        condition.allowSelectors(selectorToAllow);
        vm.stopPrank();

        // Now claiming should work
        vm.startPrank(alice);
        uint256 balanceBefore = token.balanceOf(alice);
        plugin.claimCampaignPayout(campaignId, alice, "", "");
        uint256 balanceAfter = token.balanceOf(alice);

        assertEq(balanceAfter - balanceBefore, 100 ether, "Should have received tokens");
        vm.stopPrank();
    }

    function test_CanRevokeApprovedSelectors() public {
        vm.startPrank(address(dao));

        // Allow transfer selector
        ExecuteSelectorCondition.SelectorTarget memory selectorToAllow =
            ExecuteSelectorCondition.SelectorTarget({ where: address(token), selectors: new bytes4[](1) });
        selectorToAllow.selectors[0] = IERC20.transfer.selector;

        condition.allowSelectors(selectorToAllow);
        assertTrue(
            condition.allowedSelectors(address(token), IERC20.transfer.selector), "Transfer selector should be allowed"
        );

        // Revoke it
        condition.disallowSelectors(selectorToAllow);
        assertFalse(
            condition.allowedSelectors(address(token), IERC20.transfer.selector),
            "Transfer selector should be disallowed"
        );

        vm.stopPrank();
    }

    // Helper function to create proxies
    function createProxy(address _logic, bytes memory _data) internal returns (address) {
        return address(new ERC1967Proxy(_logic, _data));
    }
}
