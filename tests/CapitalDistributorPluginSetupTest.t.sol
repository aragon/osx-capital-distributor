// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import { CapitalDistributorPluginSetup } from "../src/CapitalDistributorPluginSetup.sol";
import { CapitalDistributorPlugin } from "../src/CapitalDistributorPlugin.sol";
import { AllocatorStrategyFactory } from "../src/factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../src/factories/ActionEncoderFactory.sol";

import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { PermissionLib } from "@aragon/commons/permission/PermissionLib.sol";
import { IPluginSetup } from "@aragon/commons/plugin/setup/IPluginSetup.sol";
import { IPlugin } from "@aragon/commons/plugin/IPlugin.sol";

/// @title CapitalDistributorPluginSetupTest
/// @notice Comprehensive test suite for the CapitalDistributorPluginSetup contract
/// @dev Tests installation, uninstallation, and update functionality
contract CapitalDistributorPluginSetupTest is Test {
    // Contracts
    CapitalDistributorPluginSetup internal setup;
    DAO internal dao;
    AllocatorStrategyFactory internal strategyFactory;
    ActionEncoderFactory internal encoderFactory;

    // Addresses
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // Constants
    address internal immutable DAO_BASE;

    // Parameters for installation
    bytes internal encodedParams;

    // Results from prepareInstallation
    address internal pluginAddr;

    // Permission IDs
    bytes32 internal constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");
    bytes32 internal constant UPGRADE_PLUGIN_PERMISSION_ID = keccak256("UPGRADE_PLUGIN_PERMISSION");
    bytes32 internal constant CAMPAIGN_MANAGER_PERMISSION_ID = keccak256("CAMPAIGN_MANAGER_PERMISSION");
    bytes32 internal constant SET_METADATA_PERMISSION_ID = keccak256("SET_METADATA_PERMISSION");

    constructor() {
        DAO_BASE = address(new DAO());
    }

    function setUp() public {
        setup = new CapitalDistributorPluginSetup();
        dao = DAO(
            payable(
                createProxyAndCall(
                    DAO_BASE, abi.encodeCall(DAO.initialize, ("Test DAO", address(this), address(0x0), ""))
                )
            )
        );

        // Deploy factories
        strategyFactory = new AllocatorStrategyFactory();
        encoderFactory = new ActionEncoderFactory();
    }

    function test_WhenDeployingANewInstance() external {
        // It completes without errors
        CapitalDistributorPluginSetup newSetup = new CapitalDistributorPluginSetup();
        assertNotEq(address(newSetup), address(0));
        assertTrue(address(newSetup).code.length > 0);
    }

    modifier whenPreparingAnInstallation() {
        // Encode installation parameters with both factories
        encodedParams = abi.encode(address(strategyFactory), address(encoderFactory));
        _;
    }

    function test_WhenPreparingAnInstallation() external whenPreparingAnInstallation {
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        (pluginAddr, preparedSetupData) = setup.prepareInstallation(address(dao), encodedParams);

        // It should return the plugin address
        assertNotEq(pluginAddr, address(0));
        assertTrue(pluginAddr.code.length > 0);

        // It should return a list with 0 helpers (empty array)
        assertEq(preparedSetupData.helpers.length, 0, "helpers length should be 0");

        // It all plugins use the same implementation
        address pluginImplementation = _getImplementation(pluginAddr);
        assertEq(pluginImplementation, setup.implementation(), "plugin implementation mismatch");

        // It the plugin has the given settings
        CapitalDistributorPlugin plugin = CapitalDistributorPlugin(pluginAddr);
        assertEq(address(plugin.allocatorStrategyFactory()), address(strategyFactory));
        assertEq(address(plugin.actionEncoderFactory()), address(encoderFactory));
        assertEq(address(plugin.dao()), address(dao));

        // It the list of permissions should match
        assertEq(preparedSetupData.permissions.length, 4, "permissions length mismatch");

        // 0. DAO can upgrade the plugin
        _assertPermission(
            preparedSetupData.permissions[0],
            PermissionLib.Operation.Grant,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            UPGRADE_PLUGIN_PERMISSION_ID
        );

        // 1. Plugin can execute on DAO
        _assertPermission(
            preparedSetupData.permissions[1],
            PermissionLib.Operation.Grant,
            address(dao),
            pluginAddr,
            PermissionLib.NO_CONDITION,
            EXECUTE_PERMISSION_ID
        );

        // 2. DAO can create campaigns
        _assertPermission(
            preparedSetupData.permissions[2],
            PermissionLib.Operation.Grant,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            CAMPAIGN_MANAGER_PERMISSION_ID
        );

        // 3. The DAO can change the metadata of the plugin
        _assertPermission(
            preparedSetupData.permissions[3],
            PermissionLib.Operation.Grant,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            SET_METADATA_PERMISSION_ID
        );
    }

    function test_RevertWhen_PassingZeroStrategyFactory() external {
        // It should revert
        bytes memory invalidParams = abi.encode(address(0), address(encoderFactory));
        vm.expectRevert(CapitalDistributorPluginSetup.ZeroAddress.selector);
        setup.prepareInstallation(address(dao), invalidParams);
    }

    function test_RevertWhen_PassingZeroEncoderFactory() external {
        // It should revert
        bytes memory invalidParams = abi.encode(address(strategyFactory), address(0));
        vm.expectRevert(CapitalDistributorPluginSetup.ZeroAddress.selector);
        setup.prepareInstallation(address(dao), invalidParams);
    }

    function test_RevertWhen_PassingBothZeroFactories() external {
        // It should revert
        bytes memory invalidParams = abi.encode(address(0), address(0));
        vm.expectRevert(CapitalDistributorPluginSetup.ZeroAddress.selector);
        setup.prepareInstallation(address(dao), invalidParams);
    }

    modifier whenPreparingAnUninstallation() {
        // First prepare an installation
        encodedParams = abi.encode(address(strategyFactory), address(encoderFactory));
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        (pluginAddr, preparedSetupData) = setup.prepareInstallation(address(dao), encodedParams);
        _;
    }

    function test_WhenPreparingAnUninstallation() external whenPreparingAnUninstallation {
        // It generates a correct list of permission changes

        // Create proper payload with 1 helper as expected
        address[] memory helpers = new address[](1);
        helpers[0] = address(0x1234); // Dummy helper address

        IPluginSetup.SetupPayload memory payload =
            IPluginSetup.SetupPayload({ plugin: pluginAddr, currentHelpers: helpers, data: "" });

        PermissionLib.MultiTargetPermission[] memory revokePermissions =
            setup.prepareUninstallation(address(dao), payload);

        assertEq(revokePermissions.length, 4, "uninstallation permissions length mismatch");

        // 0. Revoke DAO can create campaigns
        _assertPermission(
            revokePermissions[0],
            PermissionLib.Operation.Revoke,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            CAMPAIGN_MANAGER_PERMISSION_ID
        );

        // 1. Revoke DAO can upgrade plugin
        _assertPermission(
            revokePermissions[1],
            PermissionLib.Operation.Revoke,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            UPGRADE_PLUGIN_PERMISSION_ID
        );

        // 2. Revoke Plugin can execute on DAO
        _assertPermission(
            revokePermissions[2],
            PermissionLib.Operation.Revoke,
            address(dao),
            pluginAddr,
            PermissionLib.NO_CONDITION,
            EXECUTE_PERMISSION_ID
        );

        // 3. Revoke DAO can change metadata
        _assertPermission(
            revokePermissions[3],
            PermissionLib.Operation.Revoke,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            SET_METADATA_PERMISSION_ID
        );
    }

    function test_RevertGiven_AListOfHelpersWithZero() external whenPreparingAnUninstallation {
        // It should revert

        // Case 1: Empty helpers array
        address[] memory wrongHelpers1 = new address[](0);
        IPluginSetup.SetupPayload memory payload1 =
            IPluginSetup.SetupPayload({ plugin: pluginAddr, currentHelpers: wrongHelpers1, data: "" });

        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPluginSetup.WrongHelpersArrayLength.selector, 0));
        setup.prepareUninstallation(address(dao), payload1);
    }

    function test_RevertGiven_AListOfHelpersWithMoreThanOne() external whenPreparingAnUninstallation {
        // It should revert

        // Case 2: Two helpers
        address[] memory wrongHelpers2 = new address[](2);
        wrongHelpers2[0] = address(0x1);
        wrongHelpers2[1] = address(0x2);
        IPluginSetup.SetupPayload memory payload2 =
            IPluginSetup.SetupPayload({ plugin: pluginAddr, currentHelpers: wrongHelpers2, data: "" });

        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPluginSetup.WrongHelpersArrayLength.selector, 2));
        setup.prepareUninstallation(address(dao), payload2);

        // Case 3: Three helpers
        address[] memory wrongHelpers3 = new address[](3);
        IPluginSetup.SetupPayload memory payload3 =
            IPluginSetup.SetupPayload({ plugin: pluginAddr, currentHelpers: wrongHelpers3, data: "" });

        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPluginSetup.WrongHelpersArrayLength.selector, 3));
        setup.prepareUninstallation(address(dao), payload3);
    }

    function test_PrepareUpdate_Reverts() external {
        // It should revert
        address[] memory helpers = new address[](1);
        helpers[0] = address(0x1234);

        IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
            plugin: alice, // dummy plugin address
            currentHelpers: helpers,
            data: ""
        });

        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPluginSetup.NotImplemented.selector));
        (bytes memory initData, IPluginSetup.PreparedSetupData memory preparedSetupData) =
            setup.prepareUpdate(address(dao), 1, payload);
    }

    function test_DecodeInstallationParams_Success() external {
        // Test parameter decoding
        address testStrategyFactory = address(0x1234);
        address testEncoderFactory = address(0x5678);

        bytes memory params = abi.encode(testStrategyFactory, testEncoderFactory);

        (AllocatorStrategyFactory decodedStrategy, ActionEncoderFactory decodedEncoder) =
            setup.decodeInstallationParams(params);

        assertEq(address(decodedStrategy), testStrategyFactory);
        assertEq(address(decodedEncoder), testEncoderFactory);
    }

    function test_Implementation_IsSet() external {
        // Verify implementation is set correctly
        address impl = setup.implementation();
        assertNotEq(impl, address(0));
        assertTrue(impl.code.length > 0);

        // Verify it's a CapitalDistributorPlugin
        CapitalDistributorPlugin implContract = CapitalDistributorPlugin(impl);
        // Try to call a view function to verify it's the right contract type
        // numCampaigns() returns 0 on uninitialized contracts, which is fine
        assertEq(implContract.numCampaigns(), 0);

        // Verify the implementation has the expected interface
        assertTrue(implContract.supportsInterface(type(IPlugin).interfaceId));
    }

    function test_FullInstallationFlow() external {
        // Test complete installation with real contracts
        bytes memory params = abi.encode(address(strategyFactory), address(encoderFactory));

        // Prepare installation
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        (pluginAddr, preparedSetupData) = setup.prepareInstallation(address(dao), params);

        // Apply permissions to DAO (simulate what PluginSetupProcessor would do)
        // In a real scenario, the PluginSetupProcessor would handle this
        // For now, let's skip permission application and just verify the plugin works

        // Verify plugin can be used
        CapitalDistributorPlugin plugin = CapitalDistributorPlugin(pluginAddr);

        // Plugin should be able to create campaigns (with proper setup)
        assertEq(plugin.numCampaigns(), 0);

        // Verify proxy pattern
        assertTrue(_isProxy(pluginAddr));
        assertEq(_getImplementation(pluginAddr), setup.implementation());
    }

    function testFuzz_DecodeInstallationParams(address _strategyFactory, address _encoderFactory) external {
        // Fuzz test encoding/decoding
        bytes memory params = abi.encode(_strategyFactory, _encoderFactory);

        (AllocatorStrategyFactory decodedStrategy, ActionEncoderFactory decodedEncoder) =
            setup.decodeInstallationParams(params);

        assertEq(address(decodedStrategy), _strategyFactory);
        assertEq(address(decodedEncoder), _encoderFactory);
    }

    // ============================================
    // Helper Functions
    // ============================================

    /// @dev Asserts that a permission matches the expected values
    function _assertPermission(
        PermissionLib.MultiTargetPermission memory actual,
        PermissionLib.Operation op,
        address where,
        address who,
        address condition,
        bytes32 permissionId
    )
        internal
        pure
    {
        assertEq(uint8(actual.operation), uint8(op), "operation mismatch");
        assertEq(actual.where, where, "permission where");
        assertEq(actual.who, who, "permission who");
        assertEq(actual.condition, condition, "permission condition");
        assertEq(actual.permissionId, permissionId, "permission id");
    }

    /// @dev Gets the implementation address from an ERC1967 proxy
    function _getImplementation(address proxy) internal view returns (address) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 implBytes = vm.load(proxy, slot);
        return address(uint160(uint256(implBytes)));
    }

    /// @dev Checks if an address is a proxy by looking for the ERC1967 implementation slot
    function _isProxy(address addr) internal view returns (bool) {
        if (addr.code.length == 0) return false;
        address impl = _getImplementation(addr);
        return impl != address(0) && impl.code.length > 0;
    }

    /// @dev Creates a proxy and initializes it with the given data
    function createProxyAndCall(address _logic, bytes memory _data) internal returns (address) {
        // Deploy minimal proxy and call initialize
        address proxy = Clones.clone(_logic);
        (bool success,) = proxy.call(_data);
        require(success, "Proxy initialization failed");
        return proxy;
    }
}
