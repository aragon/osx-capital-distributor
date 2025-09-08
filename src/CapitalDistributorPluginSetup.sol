// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.29;

import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { PermissionLib } from "@aragon/commons/permission/PermissionLib.sol";
import { ProxyLib } from "@aragon/commons/utils/deployment/ProxyLib.sol";

import { PluginUpgradeableSetup } from "@aragon/commons/plugin/setup/PluginUpgradeableSetup.sol";
import { IPluginSetup } from "@aragon/commons/plugin/setup/IPluginSetup.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";

import { CapitalDistributorPlugin } from "./CapitalDistributorPlugin.sol";
import { AllocatorStrategyFactory } from "./factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "./factories/ActionEncoderFactory.sol";

/// @title CapitalDistributorPlugin
/// @author Aragon Association - 2025
/// @notice The setup contract of the `CapitalDistributor` plugin.
/// @custom:security-contact sirt@aragon.org
contract CapitalDistributorPluginSetup is PluginUpgradeableSetup {
    using ProxyLib for address;

    bytes32 internal constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");
    bytes32 private constant UPGRADE_PLUGIN_PERMISSION_ID = keccak256("UPGRADE_PLUGIN_PERMISSION");
    bytes32 public constant CAMPAIGN_MANAGER_PERMISSION_ID = keccak256("CAMPAIGN_MANAGER_PERMISSION");
    bytes32 public constant SET_METADATA_PERMISSION_ID = keccak256("SET_METADATA_PERMISSION");
    bytes32 public constant MANAGE_SELECTORS_PERMISSION_ID = keccak256("MANAGE_SELECTORS_PERMISSION");

    /// @notice The address of the `CapitalDistributorPlugin` base contract.
    CapitalDistributorPlugin private immutable CAPITAL_DISTRIBUTOR_PLUGIN_BASE;

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);
    error ZeroAddress();
    error NotImplemented();

    /// @notice The contract constructor deploying the plugin implementation contract
    constructor() PluginUpgradeableSetup(address(new CapitalDistributorPlugin())) {
        CAPITAL_DISTRIBUTOR_PLUGIN_BASE = CapitalDistributorPlugin(implementation());
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _installParameters
    )
        external
        returns (address plugin, PreparedSetupData memory preparedSetupData)
    {
        // Decode `_installParameters` to extract the params needed for deploying and initializing
        // `CapitalDistributorPlugin` plugin,
        // and the required helpers
        (AllocatorStrategyFactory allocatorStrategyFactory, ActionEncoderFactory encodersFactory) =
            decodeInstallationParams(_installParameters);
        if (address(allocatorStrategyFactory) == address(0) || address(encodersFactory) == address(0)) {
            revert ZeroAddress();
        }

        // Deploy the execute condition with no initial selectors
        ExecuteSelectorCondition.SelectorTarget[] memory initialSelectors =
            new ExecuteSelectorCondition.SelectorTarget[](0);
        ExecuteSelectorCondition executeCondition = new ExecuteSelectorCondition(IDAO(_dao), initialSelectors);

        // Prepare helpers.
        address[] memory helpers = new address[](1);
        helpers[0] = address(executeCondition);

        // Prepare and deploy plugin proxy.
        plugin = address(CAPITAL_DISTRIBUTOR_PLUGIN_BASE).deployUUPSProxy(
            abi.encodeCall(CapitalDistributorPlugin.initialize, (IDAO(_dao), allocatorStrategyFactory, encodersFactory))
        );

        // Prepare permissions
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](5);

        // Request the permissions to be granted

        // The DAO can upgrade the plugin implementation
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: UPGRADE_PLUGIN_PERMISSION_ID
        });

        // The plugin can make the DAO execute actions (with condition)
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.GrantWithCondition,
            where: _dao,
            who: plugin,
            condition: address(executeCondition),
            permissionId: EXECUTE_PERMISSION_ID
        });

        // The DAO is the one who can create Campaigns through any of its governance mechanisms
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: CAMPAIGN_MANAGER_PERMISSION_ID
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_METADATA_PERMISSION_ID
        });

        // The DAO can manage allowed selectors on the execute condition
        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(executeCondition),
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: MANAGE_SELECTORS_PERMISSION_ID
        });

        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    )
        external
        pure
        returns (PermissionLib.MultiTargetPermission[] memory permissions)
    {
        // Prepare permissions.
        uint256 helperLength = _payload.currentHelpers.length;
        if (helperLength != 1) {
            revert WrongHelpersArrayLength({ length: helperLength });
        }

        address executeCondition = _payload.currentHelpers[0];

        // Set permissions to be Revoked.
        permissions = new PermissionLib.MultiTargetPermission[](5);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: CAMPAIGN_MANAGER_PERMISSION_ID
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: UPGRADE_PLUGIN_PERMISSION_ID
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: executeCondition,
            permissionId: EXECUTE_PERMISSION_ID
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_METADATA_PERMISSION_ID
        });

        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: executeCondition,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: MANAGE_SELECTORS_PERMISSION_ID
        });
    }

    /// @inheritdoc IPluginSetup
    /// @dev Revoke the upgrade plugin permission to the DAO for all builds prior the current one (3).
    function prepareUpdate(
        address,
        uint16,
        SetupPayload calldata
    )
        external
        pure
        override
        returns (bytes memory, PreparedSetupData memory)
    {
        revert NotImplemented();
    }

    /// @notice Encodes the installation parameters into a byte array
    /// @param _strategiesFactory The address of the allocator strategy factory
    /// @param _actionEncoderFactory The address of the action encoder factory
    /// @return The encoded installation parameters
    function encodeInstallationParams(
        address _strategiesFactory,
        address _actionEncoderFactory
    )
        public
        pure
        returns (bytes memory)
    {
        return abi.encode(_strategiesFactory, _actionEncoderFactory);
    }

    /// @notice Decodes the given byte array into the original installation parameters
    function decodeInstallationParams(bytes memory _data)
        public
        pure
        returns (AllocatorStrategyFactory strategiesFactory, ActionEncoderFactory actionEncoderFactory)
    {
        (address _strategiesFactory, address _actionEncoderFactory) = abi.decode(_data, (address, address));
        return (AllocatorStrategyFactory(_strategiesFactory), ActionEncoderFactory(_actionEncoderFactory));
    }
}
