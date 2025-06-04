// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.29;

import {console2} from "forge-std/console2.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/commons/permission/PermissionLib.sol";
import {ProxyLib} from "@aragon/commons/utils/deployment/ProxyLib.sol";

import {PluginUpgradeableSetup} from "@aragon/commons/plugin/setup/PluginUpgradeableSetup.sol";
import {IPluginSetup} from "@aragon/commons/plugin/setup/IPluginSetup.sol";

import {CapitalDistributorPlugin} from "./CapitalDistributorPlugin.sol";
import {AllocatorStrategyFactory} from "./AllocatorStrategyFactory.sol";
import {ActionEncoderFactory} from "./ActionEncoderFactory.sol";

/// @title CapitalDistributorPlugin
/// @author Aragon Association - 2025
/// @notice The setup contract of the `CapitalDistributor` plugin.
/// @custom:security-contact sirt@aragon.org
contract CapitalDistributorPluginSetup is PluginUpgradeableSetup {
    using ProxyLib for address;

    bytes32 internal constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");
    bytes32 public constant UPGRADE_PLUGIN_PERMISSION_ID = keccak256("UPGRADE_PLUGIN_PERMISSION_ID");
    bytes32 public constant CAMPAIGN_CREATOR_PERMISSION_ID = keccak256("CAMPAIGN_CREATOR_PERMISSION");

    /// @notice The address of the `CapitalDistributorPlugin` base contract.
    CapitalDistributorPlugin private immutable capitalDistributorPluginBase;

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);
    error ZeroAddress();

    /// @notice The contract constructor deploying the plugin implementation contract
    constructor() PluginUpgradeableSetup(address(new CapitalDistributorPlugin())) {}

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _installParameters
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // Decode `_installParameters` to extract the params needed for deploying and initializing `CapitalDistributorPlugin` plugin,
        // and the required helpers
        (
            AllocatorStrategyFactory allocatorStrategyFactory,
            ActionEncoderFactory encodersFactory
        ) = decodeInstallationParams(_installParameters);
        if (address(allocatorStrategyFactory) == address(0)) revert ZeroAddress();

        // Prepare helpers.
        address[] memory helpers = new address[](1);
        helpers[0] = address(allocatorStrategyFactory);

        // Prepare and deploy plugin proxy.
        plugin = IMPLEMENTATION.deployUUPSProxy(
            abi.encodeCall(CapitalDistributorPlugin.initialize, (IDAO(_dao), allocatorStrategyFactory, encodersFactory))
        );

        // Prepare permissions
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](3);

        // Request the permissions to be granted

        // The DAO can upgrade the plugin implementation
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: UPGRADE_PLUGIN_PERMISSION_ID
        });

        // The plugin can make the DAO execute actions
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        // The DAO is the one who can create Campaigns through any of its governance mechanisms
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: CAMPAIGN_CREATOR_PERMISSION_ID
        });

        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // Prepare permissions.
        uint256 helperLength = _payload.currentHelpers.length;
        if (helperLength != 1) {
            revert WrongHelpersArrayLength({length: helperLength});
        }

        // Set permissions to be Revoked.
        permissions = new PermissionLib.MultiTargetPermission[](3);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: CAMPAIGN_CREATOR_PERMISSION_ID
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
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });
    }

    /// @inheritdoc IPluginSetup
    /// @dev Revoke the upgrade plugin permission to the DAO for all builds prior the current one (3).
    function prepareUpdate(
        address _dao,
        uint16 _fromBuild,
        SetupPayload calldata _payload
    ) external override returns (bytes memory initData, PreparedSetupData memory preparedSetupData) {
        // No update here
    }

    /// @notice Encodes the given installation parameters into a byte array
    function encodeInstallationParams() external pure returns (bytes memory) {
        // return abi.encode(_votingSettings, _tokenSettings, _mintSettings, _proposers);
    }

    /// @notice Decodes the given byte array into the original installation parameters
    function decodeInstallationParams(
        bytes memory _data
    ) public pure returns (AllocatorStrategyFactory strategiesFactory, ActionEncoderFactory actionEncoderFactory) {
        (address _strategiesFactory, address _actionEncoderFactory) = abi.decode(_data, (address, address));
        return (AllocatorStrategyFactory(_strategiesFactory), ActionEncoderFactory(_actionEncoderFactory));
    }
}
