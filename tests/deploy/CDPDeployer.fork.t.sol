// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { console2 as console } from "forge-std/console2.sol";

// CDP Deployer utility
import {
    CDPDeployer,
    CDPInfraParams,
    CDPInfraDeployment,
    OSxAddresses,
    InstallCDPParams,
    PreparedCDPInstallation,
    ConditionConfig,
    VEConditionParams
} from "../../src/deploy/CDPDeployer.sol";

// Capital Distributor imports
import { CapitalDistributorPlugin } from "../../src/CapitalDistributorPlugin.sol";
import { ICapitalDistributorPlugin } from "../../src/interfaces/ICapitalDistributorPlugin.sol";

// Aragon/OSx imports
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { Action } from "@aragon/commons/executors/IExecutor.sol";
import { DAOFactory } from "@aragon/osx/framework/dao/DAOFactory.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginSetupRef } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";
import { IPlugin } from "@aragon/commons/plugin/IPlugin.sol";

// OpenZeppelin imports
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title CDPDeployerForkTest
/// @notice Fork tests for CDP deployment using real OSx contracts on Katana
/// @dev This test forks Katana to test the production deployment flow:
///      1. Deploy infrastructure (permissionless)
///      2. Prepare installation (permissionless)
///      3. Apply installation (requires DAO permissions)
///      4. Configure condition (requires DAO permissions)
contract CDPDeployerForkTest is Test {
    // =============================================================================
    // Katana Mainnet Configuration (Chain ID: 747474)
    // =============================================================================

    string constant KATANA_RPC_URL = "https://rpc.katana.network";

    address constant KATANA_DAO_FACTORY = 0x57c52Ed735Cc678936278B88B5AbCB916B9e201B;
    address constant KATANA_PLUGIN_REPO_FACTORY = 0xbA428E29900DAE3854B9383613580BF7113cba39;
    address constant KATANA_PSP = 0x6240e3aFa085B8393EB072911f3d65EF080b6bEf;
    address constant KATANA_ADMIN_PLUGIN_REPO = 0x95d1ACA58E631774bDE4d1bC67DD784f01cCDAeC;
    address constant KATANA_DAO = 0x0cD4B1347D06e386970b89A010f54e3a9Cc31834;
    address constant KATANA_TOKEN = 0xD073c389D9c3B9Da328907Cbe42b49AB517B214F;
    address constant KATANA_VOTING_ESCROW = 0x9bA5d5b6215BE24e40795838dcbE716130A4b635;

    // =============================================================================
    // Test State
    // =============================================================================

    CDPDeployer deployer;
    OSxAddresses osx;

    address admin;
    address pluginMaintainer;
    uint256 forkId;

    // Existing Katana DAO for testing
    DAO testDao;

    function setUp() public {
        // Create fork of Katana network
        forkId = vm.createSelectFork(KATANA_RPC_URL);

        pluginMaintainer = makeAddr("pluginMaintainer");

        // Use hardcoded Katana OSx addresses
        osx = OSxAddresses({
            daoFactory: KATANA_DAO_FACTORY,
            pluginRepoFactory: KATANA_PLUGIN_REPO_FACTORY,
            pluginSetupProcessor: KATANA_PSP,
            adminPluginRepo: KATANA_ADMIN_PLUGIN_REPO,
            multisigPluginRepo: address(0)
        });

        // Create deployer
        deployer = new CDPDeployer();

        // Use existing Katana DAO
        testDao = DAO(payable(KATANA_DAO));

        // Admin is the DAO itself (for granting permissions via prank)
        admin = address(testDao);

        // Log configuration
        console.log("=== Fork Test Configuration ===");
        console.log("Fork ID:", forkId);
        console.log("Katana DAO:", address(testDao));
        console.log("DAO Factory:", osx.daoFactory);
        console.log("Plugin Repo Factory:", osx.pluginRepoFactory);
        console.log("PSP:", osx.pluginSetupProcessor);
    }

    // =============================================================================
    // Deploy Script Full Flow Test
    // =============================================================================

    /// @notice Simulates the actual deploy script execution on Katana mainnet
    /// @dev Tests the complete flow: deploy infrastructure -> prepare installation -> apply via DAO.execute()
    function test_Fork_DeployScript_FullFlow() public {
        console.log("\n");
        console.log("================================================================");
        console.log("       CDP DEPLOY SCRIPT - FULL FLOW SIMULATION");
        console.log("================================================================");

        // -------------------------------------------------------------------------
        // Step 1: Deploy Infrastructure (permissionless)
        // -------------------------------------------------------------------------
        console.log("\n--- Step 1: Deploy Infrastructure ---");

        CDPInfraDeployment memory infra =
            deployer.deployInfrastructure(CDPInfraParams({ feeRecipient: address(0), feeBasisPoints: 0 }));

        _verifyInfrastructureDeployment(infra);

        // -------------------------------------------------------------------------
        // Step 2: Prepare Installation (permissionless)
        // -------------------------------------------------------------------------
        console.log("\n--- Step 2: Prepare Installation ---");

        string memory subdomain = string.concat("cdp-deploy-", vm.toString(block.timestamp));
        InstallCDPParams memory installParams = InstallCDPParams({
            dao: testDao, osx: osx, infra: infra, pluginMaintainer: pluginMaintainer, pluginRepoSubdomain: subdomain
        });

        PreparedCDPInstallation memory prepared = deployer.prepareInstallation(installParams);

        _verifyPreparedInstallation(prepared);

        // -------------------------------------------------------------------------
        // Step 3: Apply Installation via DAO.execute() (requires DAO permissions)
        // -------------------------------------------------------------------------
        console.log("\n--- Step 3: Apply Installation via DAO.execute() ---");

        VEConditionParams memory veParams =
            VEConditionParams({ token: KATANA_TOKEN, votingEscrow: KATANA_VOTING_ESCROW });

        // Generate installation actions (grant ROOT -> apply -> revoke ROOT -> configure condition)
        Action[] memory actions = deployer.buildInstallationActions(address(testDao), KATANA_PSP, prepared, veParams);
        _logGeneratedActions(actions, KATANA_TOKEN, KATANA_VOTING_ESCROW);

        // Execute installation through the DAO (simulates proposal execution)
        _executeInstallationActions(actions);

        _verifyAppliedInstallation(prepared, KATANA_TOKEN, KATANA_VOTING_ESCROW);

        // -------------------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------------------
        console.log("\n================================================================");
        console.log("       DEPLOYMENT COMPLETE");
        console.log("================================================================");
        console.log("  DAO:            ", address(testDao));
        console.log("  CDP Plugin:     ", address(prepared.plugin));
        console.log("  Condition:      ", address(prepared.condition));
        console.log("  Plugin Repo:    ", address(prepared.pluginRepo));
        console.log("  Strategy Factory:", address(infra.strategyFactory));
        console.log("  Encoder Factory: ", address(infra.encoderFactory));
    }

    // =============================================================================
    // Internal Verification Functions
    // =============================================================================

    /// @dev Verifies that infrastructure was deployed correctly
    function _verifyInfrastructureDeployment(CDPInfraDeployment memory infra) internal view {
        // Verify factories deployed
        assertTrue(address(infra.strategyFactory) != address(0), "Strategy factory not deployed");
        assertTrue(address(infra.encoderFactory) != address(0), "Encoder factory not deployed");

        // Verify merkle strategy registered
        assertTrue(address(infra.merkleStrategy) != address(0), "Merkle strategy not deployed");
        (address strategyImpl,) = infra.strategyFactory.registeredTypes(deployer.MERKLE_STRATEGY_ID());
        assertEq(strategyImpl, address(infra.merkleStrategy), "Merkle strategy not registered");

        // Verify voting escrow encoder registered
        assertTrue(address(infra.votingEscrowEncoder) != address(0), "VE encoder not deployed");
        (address veEncoderImpl,) = infra.encoderFactory.registeredTypes(deployer.VOTING_ESCROW_ENCODER_ID());
        assertEq(veEncoderImpl, address(infra.votingEscrowEncoder), "VE encoder not registered");

        // Verify vault deposit encoder registered
        assertTrue(address(infra.vaultDepositEncoder) != address(0), "Vault encoder not deployed");
        (address vaultEncoderImpl,) = infra.encoderFactory.registeredTypes(deployer.VAULT_DEPOSIT_ENCODER_ID());
        assertEq(vaultEncoderImpl, address(infra.vaultDepositEncoder), "Vault encoder not registered");

        console.log("  [OK] Strategy Factory:", address(infra.strategyFactory));
        console.log("  [OK] Encoder Factory:", address(infra.encoderFactory));
        console.log("  [OK] Merkle Strategy:", address(infra.merkleStrategy));
        console.log("  [OK] VE Encoder:", address(infra.votingEscrowEncoder));
        console.log("  [OK] Vault Encoder:", address(infra.vaultDepositEncoder));
    }

    /// @dev Verifies that installation was prepared correctly
    function _verifyPreparedInstallation(PreparedCDPInstallation memory prepared) internal view {
        // Verify all components are deployed
        assertTrue(address(prepared.pluginRepo) != address(0), "Plugin repo not created");
        assertTrue(address(prepared.plugin) != address(0), "CDP plugin not prepared");
        assertTrue(address(prepared.condition) != address(0), "Condition not prepared");

        // Verify DAO linkage
        assertEq(address(prepared.dao), address(testDao), "DAO mismatch in prepared data");

        // Verify plugin setup reference
        assertEq(
            address(prepared.pluginSetupRef.pluginSetupRepo), address(prepared.pluginRepo), "Plugin setup ref mismatch"
        );

        console.log("  [OK] Plugin Repo:", address(prepared.pluginRepo));
        console.log("  [OK] CDP Plugin:", address(prepared.plugin));
        console.log("  [OK] Condition:", address(prepared.condition));
    }

    /// @dev Logs the generated installation actions for visibility
    function _logGeneratedActions(Action[] memory actions, address token, address votingEscrow) internal view {
        assertEq(actions.length, 5, "Should generate exactly 5 actions");

        console.log("  Generated actions:");
        console.log("    [0] Grant ROOT to PSP  -> target:", actions[0].to);
        console.log("    [1] Apply Installation -> target:", actions[1].to);
        console.log("    [2] Revoke ROOT from PSP -> target:", actions[2].to);
        console.log("    [3] Allow approve() on token -> target:", actions[3].to);
        console.log("    [4] Allow createLockFor() on VE -> target:", actions[4].to);
        console.log("  VE Condition Config:");
        console.log("    Token:", token);
        console.log("    VotingEscrow:", votingEscrow);
    }

    /// @dev Executes the installation actions through the DAO
    /// @notice TEST-ONLY: In production, a governance plugin (multisig/token voting) would have
    ///         EXECUTE_PERMISSION and call dao.execute() after proposal approval. Here we grant
    ///         permissions directly to the DAO to simulate proposal execution without setting up
    ///         a full governance flow.
    function _executeInstallationActions(Action[] memory actions) internal {
        PluginSetupProcessor psp = PluginSetupProcessor(KATANA_PSP);
        bytes32 executePermissionId = keccak256("EXECUTE_PERMISSION");

        // TEST-ONLY: Grant permissions to simulate governance plugin behavior
        // In production:
        //   - EXECUTE_PERMISSION would be held by a governance plugin (e.g., Admin, Multisig, TokenVoting)
        //   - APPLY_INSTALLATION_PERMISSION would be granted to the governance plugin, not the DAO itself
        //   - The governance plugin would call dao.execute() after a proposal passes
        vm.startPrank(address(testDao));
        testDao.grant(address(testDao), address(testDao), executePermissionId);
        testDao.grant(address(psp), address(testDao), psp.APPLY_INSTALLATION_PERMISSION_ID());

        // Execute via DAO (simulates a passed proposal being executed by governance plugin)
        testDao.execute(bytes32(uint256(1)), actions, 0);
        vm.stopPrank();

        console.log("  [OK] Actions executed via DAO.execute()");

        // Cleanup test-only permissions (these wouldn't exist in production)
        vm.startPrank(address(testDao));
        testDao.revoke(address(psp), address(testDao), psp.APPLY_INSTALLATION_PERMISSION_ID());
        testDao.revoke(address(testDao), address(testDao), executePermissionId);
        vm.stopPrank();
    }

    /// @dev Verifies that installation was applied correctly
    function _verifyAppliedInstallation(
        PreparedCDPInstallation memory prepared,
        address token,
        address votingEscrow
    )
        internal
        view
    {
        PluginSetupProcessor psp = PluginSetupProcessor(KATANA_PSP);

        // 1. Plugin linked to DAO
        assertEq(address(prepared.plugin.dao()), address(testDao), "Plugin not linked to DAO");
        console.log("  [OK] Plugin linked to DAO");

        // 2. DAO has CAMPAIGN_MANAGER_PERMISSION on plugin
        bytes32 campaignManagerPermissionId = keccak256("CAMPAIGN_MANAGER_PERMISSION");
        assertTrue(
            testDao.hasPermission(address(prepared.plugin), address(testDao), campaignManagerPermissionId, bytes("")),
            "DAO missing CAMPAIGN_MANAGER_PERMISSION"
        );
        console.log("  [OK] DAO has CAMPAIGN_MANAGER_PERMISSION on plugin");

        // 3. Condition linked to DAO
        assertEq(address(prepared.condition.dao()), address(testDao), "Condition not linked to DAO");
        console.log("  [OK] Condition linked to DAO");

        // 4. Plugin has conditional EXECUTE_PERMISSION on DAO
        bytes32 executePermissionId = keccak256("EXECUTE_PERMISSION");
        Action[] memory emptyActions = new Action[](0);
        bytes memory executeCalldata = abi.encodeCall(DAO.execute, (bytes32(0), emptyActions, 0));
        assertTrue(
            testDao.hasPermission(address(testDao), address(prepared.plugin), executePermissionId, executeCalldata),
            "Plugin missing EXECUTE_PERMISSION on DAO"
        );
        console.log("  [OK] Plugin has EXECUTE_PERMISSION on DAO (with condition)");

        // 5. ROOT_PERMISSION revoked from PSP (security check)
        assertFalse(
            testDao.hasPermission(address(testDao), address(psp), testDao.ROOT_PERMISSION_ID(), bytes("")),
            "ROOT_PERMISSION not revoked from PSP"
        );
        console.log("  [OK] ROOT_PERMISSION revoked from PSP");

        // 6. Condition configured with approve selector for token
        assertTrue(
            prepared.condition.allowedSelectors(token, IERC20.approve.selector),
            "Condition not configured for token.approve()"
        );
        console.log("  [OK] Condition allows token.approve()");

        // 7. Condition configured with createLockFor selector for votingEscrow
        assertTrue(
            prepared.condition.allowedSelectors(votingEscrow, bytes4(keccak256("createLockFor(uint256,address)"))),
            "Condition not configured for votingEscrow.createLockFor()"
        );
        console.log("  [OK] Condition allows votingEscrow.createLockFor()");
    }

    // =============================================================================
    // Edge Case Tests
    // =============================================================================

    /// @notice Test deploying infrastructure with fees
    function test_Fork_DeployInfrastructureWithFees() public {
        address feeRecipient = makeAddr("feeRecipient");
        uint32 feeBasisPoints = 100; // 1%

        CDPInfraDeployment memory infraWithFees = deployer.deployInfrastructure(
            CDPInfraParams({ feeRecipient: feeRecipient, feeBasisPoints: feeBasisPoints })
        );

        // Verify fee configuration
        (address registeredFeeRecipient, uint32 registeredFee) =
            infraWithFees.strategyFactory.strategyFees(deployer.MERKLE_STRATEGY_ID());
        assertEq(registeredFeeRecipient, feeRecipient, "Fee recipient mismatch");
        assertEq(registeredFee, feeBasisPoints, "Fee basis points mismatch");
    }

    /// @notice Test that prepareInstallation reverts with zero DAO address
    function test_Fork_RevertOnZeroDAO() public {
        CDPInfraDeployment memory infra =
            deployer.deployInfrastructure(CDPInfraParams({ feeRecipient: address(0), feeBasisPoints: 0 }));

        InstallCDPParams memory badParams = InstallCDPParams({
            dao: DAO(payable(address(0))),
            osx: osx,
            infra: infra,
            pluginMaintainer: pluginMaintainer,
            pluginRepoSubdomain: "test"
        });

        vm.expectRevert(abi.encodeWithSelector(CDPDeployer.ZeroAddress.selector, "dao"));
        deployer.prepareInstallation(badParams);
    }

    /// @notice Test creating plugin repo with zero maintainer reverts
    function test_Fork_RevertOnZeroMaintainer() public {
        vm.expectRevert(abi.encodeWithSelector(CDPDeployer.ZeroAddress.selector, "maintainer"));
        deployer.createPluginRepo(osx.pluginRepoFactory, "test-subdomain", address(0));
    }
}
