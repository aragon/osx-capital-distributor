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
    CDPWithDAOParams,
    CDPWithDAODeployment,
    ConditionConfig,
    EncoderType
} from "../../src/deploy/CDPDeployer.sol";

// Capital Distributor imports
import { ICapitalDistributorPlugin } from "../../src/interfaces/ICapitalDistributorPlugin.sol";

// Aragon/OSx imports
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

// OpenZeppelin imports
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title DeployCDPForkTest
/// @notice Fork tests for the CDP deployment using real OSx contracts
/// @dev This test forks Katana (or other networks with OSx deployed) to test
///      the production deployment flow with real OSx infrastructure.
///
/// Required Environment Variables:
/// - KATANA_DAO_FACTORY: OSx DAOFactory address
/// - KATANA_PLUGIN_REPO_FACTORY: OSx PluginRepoFactory address
/// - KATANA_PSP: OSx PluginSetupProcessor address
/// - KATANA_ADMIN_PLUGIN_REPO: Admin plugin repo address
///
/// To run with Katana:
/// ```bash
/// export KATANA_DAO_FACTORY=0xd59D2bEF6465cC71efEc40afd2D72901470Dd835
/// export KATANA_PLUGIN_REPO_FACTORY=0x98DE0Dc6e86f4CDD69646e7fFFF8d6f4bb997b10
/// export KATANA_PSP=0xfD4dBD760e253b7ee0CE81d47946DAdd2531F1fC
/// export KATANA_ADMIN_PLUGIN_REPO=0x95d1ACA58E631774bDE4d1bC67DD784f01cCDAeC
/// forge test --match-contract DeployCDPForkTest --fork-url $KATANA_RPC_URL -vvv
/// ```
contract DeployCDPForkTest is Test {
    // =============================================================================
    // Test Setup
    // =============================================================================

    CDPDeployer deployer;
    OSxAddresses osx;

    address admin;
    address pluginMaintainer;
    uint256 forkId;

    function setUp() public {
        admin = makeAddr("admin");
        pluginMaintainer = makeAddr("pluginMaintainer");

        // Load OSx addresses from environment variables
        // Required env vars: KATANA_DAO_FACTORY, KATANA_PLUGIN_REPO_FACTORY,
        //                    KATANA_PSP, KATANA_ADMIN_PLUGIN_REPO
        osx = OSxAddresses({
            daoFactory: vm.envAddress("KATANA_DAO_FACTORY"),
            pluginRepoFactory: vm.envAddress("KATANA_PLUGIN_REPO_FACTORY"),
            pluginSetupProcessor: vm.envAddress("KATANA_PSP"),
            adminPluginRepo: vm.envAddress("KATANA_ADMIN_PLUGIN_REPO"),
            multisigPluginRepo: address(0) // Not used for deployDAOWithCDP
        });

        // Log configuration
        console.log("=== Fork Test Configuration ===");
        console.log("DAO Factory:", osx.daoFactory);
        console.log("Plugin Repo Factory:", osx.pluginRepoFactory);
        console.log("PSP:", osx.pluginSetupProcessor);
        console.log("Admin Plugin Repo:", osx.adminPluginRepo);
    }

    // =============================================================================
    // Core Deployment Tests
    // =============================================================================

    /// @notice Test deploying CDP infrastructure (factories, strategies, encoders)
    function test_Fork_DeployInfrastructure() public {
        deployer = new CDPDeployer();

        CDPInfraDeployment memory infra = deployer.deployInfrastructure(
            CDPInfraParams({ feeRecipient: address(0), feeBasisPoints: 0, encoderType: EncoderType.VotingEscrow })
        );

        // Verify factories deployed
        assertTrue(address(infra.strategyFactory) != address(0), "Strategy factory not deployed");
        assertTrue(address(infra.encoderFactory) != address(0), "Encoder factory not deployed");

        // Verify strategies registered
        assertTrue(address(infra.merkleStrategy) != address(0), "Merkle strategy not deployed");
        (address impl,) = infra.strategyFactory.registeredTypes(deployer.MERKLE_STRATEGY_ID());
        assertEq(impl, address(infra.merkleStrategy), "Merkle strategy not registered");

        // Verify encoders registered
        assertTrue(address(infra.votingEscrowEncoder) != address(0), "VE encoder not deployed");
        (address encoderImpl,) = infra.encoderFactory.registeredTypes(deployer.VOTING_ESCROW_ENCODER_ID());
        assertEq(encoderImpl, address(infra.votingEscrowEncoder), "VE encoder not registered");

        console.log("Infrastructure deployed successfully");
        console.log("  Strategy Factory:", address(infra.strategyFactory));
        console.log("  Encoder Factory:", address(infra.encoderFactory));
    }

    /// @notice Test creating a plugin repo
    /// @dev This test requires a fork to be active. Run with: forge test --fork-url $RPC_URL
    function test_Fork_CreatePluginRepo() public {
        // Skip if not forked (code at OSx addresses will be empty)
        if (osx.pluginRepoFactory.code.length == 0) {
            console.log("Skipping: No fork detected. Run with --fork-url $RPC_URL");
            return;
        }

        deployer = new CDPDeployer();

        string memory subdomain = string.concat("cdp-test-", vm.toString(block.timestamp));

        (PluginRepo repo,) = deployer.createPluginRepo(osx.pluginRepoFactory, subdomain, pluginMaintainer);

        assertTrue(address(repo) != address(0), "Plugin repo not created");

        // Verify version exists
        PluginRepo.Tag memory tag = PluginRepo.Tag({ release: 1, build: 1 });
        PluginRepo.Version memory version = repo.getVersion(tag);
        assertTrue(version.pluginSetup != address(0), "Plugin setup not set");

        console.log("Plugin repo created:", address(repo));
    }

    /// @notice Test full DAO + CDP deployment
    /// @dev This test requires a fork to be active. Run with: forge test --fork-url $RPC_URL
    function test_Fork_DeployDAOWithCDP() public {
        // Skip if not forked
        if (osx.daoFactory.code.length == 0) {
            console.log("Skipping: No fork detected. Run with --fork-url $RPC_URL");
            return;
        }

        deployer = new CDPDeployer();

        // Deploy infrastructure first
        CDPInfraDeployment memory infra = deployer.deployInfrastructure(
            CDPInfraParams({ feeRecipient: address(0), feeBasisPoints: 0, encoderType: EncoderType.VotingEscrow })
        );

        // Prepare deployment params
        string memory timestamp = vm.toString(block.timestamp);
        CDPWithDAOParams memory params = CDPWithDAOParams({
            osx: osx,
            infra: infra,
            daoAdmin: admin,
            daoUri: "ipfs://fork-test-dao",
            daoName: string.concat("fork-test-", timestamp),
            pluginRepoSubdomain: string.concat("fork-cdp-", timestamp),
            pluginMaintainer: pluginMaintainer
        });

        // Deploy DAO with CDP
        CDPWithDAODeployment memory deployment = deployer.deployDAOWithCDP(params);

        // Verify DAO
        assertTrue(address(deployment.dao) != address(0), "DAO not deployed");
        assertEq(deployment.dao.daoURI(), "ipfs://fork-test-dao", "DAO URI mismatch");

        // Verify CDP Plugin
        assertTrue(address(deployment.capitalDistributorPlugin) != address(0), "CDP plugin not deployed");
        assertEq(address(deployment.capitalDistributorPlugin.dao()), address(deployment.dao), "CDP plugin dao mismatch");

        // Verify Execute Condition
        assertTrue(address(deployment.executeCondition) != address(0), "Execute condition not deployed");

        // Verify Admin Plugin
        assertTrue(deployment.adminPlugin != address(0), "Admin plugin not deployed");

        // Verify Plugin Repo
        assertTrue(address(deployment.pluginRepo) != address(0), "Plugin repo not created");

        console.log("DAO with CDP deployed successfully");
        console.log("  DAO:", address(deployment.dao));
        console.log("  CDP Plugin:", address(deployment.capitalDistributorPlugin));
        console.log("  Execute Condition:", address(deployment.executeCondition));
        console.log("  Admin Plugin:", deployment.adminPlugin);
    }

    /// @notice Test configuring the execute condition for VE locks
    /// @dev This test requires a fork to be active. Run with: forge test --fork-url $RPC_URL
    function test_Fork_ConfigureCondition() public {
        // Skip if not forked
        if (osx.daoFactory.code.length == 0) {
            console.log("Skipping: No fork detected. Run with --fork-url $RPC_URL");
            return;
        }

        deployer = new CDPDeployer();

        // Deploy infrastructure
        CDPInfraDeployment memory infra = deployer.deployInfrastructure(
            CDPInfraParams({ feeRecipient: address(0), feeBasisPoints: 0, encoderType: EncoderType.VotingEscrow })
        );

        // Deploy DAO with CDP
        string memory timestamp = vm.toString(block.timestamp);
        CDPWithDAOParams memory params = CDPWithDAOParams({
            osx: osx,
            infra: infra,
            daoAdmin: admin,
            daoUri: "ipfs://fork-test-dao",
            daoName: string.concat("fork-test-ve-", timestamp),
            pluginRepoSubdomain: string.concat("fork-cdp-ve-", timestamp),
            pluginMaintainer: pluginMaintainer
        });

        CDPWithDAODeployment memory deployment = deployer.deployDAOWithCDP(params);

        // Mock token and voting escrow addresses for testing
        address mockToken = makeAddr("mockToken");
        address mockVotingEscrow = makeAddr("mockVotingEscrow");

        // Build condition config for VE lock operations
        ConditionConfig memory config = ConditionConfig({
            targetOne: mockToken,
            selectorOne: IERC20.approve.selector,
            targetTwo: mockVotingEscrow,
            selectorTwo: bytes4(keccak256("createLockFor(uint256,address)"))
        });

        // Configure condition (must be called by DAO which has MANAGE_SELECTORS_PERMISSION)
        vm.prank(address(deployment.dao));
        deployer.configureCondition(deployment.executeCondition, config);

        // Verify selectors are allowed
        assertTrue(
            deployment.executeCondition.allowedSelectors(mockToken, IERC20.approve.selector), "Approve not allowed"
        );
        assertTrue(
            deployment.executeCondition
                .allowedSelectors(mockVotingEscrow, bytes4(keccak256("createLockFor(uint256,address)"))),
            "createLockFor not allowed"
        );

        console.log("Condition configured for VE locks");
    }

    // =============================================================================
    // Integration Tests
    // =============================================================================

    /// @notice Test creating a campaign after deployment
    /// @dev This test requires a fork to be active. Run with: forge test --fork-url $RPC_URL
    function test_Fork_CreateCampaignAfterDeployment() public {
        // Skip if not forked
        if (osx.daoFactory.code.length == 0) {
            console.log("Skipping: No fork detected. Run with --fork-url $RPC_URL");
            return;
        }

        deployer = new CDPDeployer();

        // Deploy infrastructure
        CDPInfraDeployment memory infra = deployer.deployInfrastructure(
            CDPInfraParams({ feeRecipient: address(0), feeBasisPoints: 0, encoderType: EncoderType.VotingEscrow })
        );

        // Deploy DAO with CDP
        string memory timestamp = vm.toString(block.timestamp);
        CDPWithDAOParams memory params = CDPWithDAOParams({
            osx: osx,
            infra: infra,
            daoAdmin: admin,
            daoUri: "ipfs://fork-test-dao",
            daoName: string.concat("fork-test-campaign-", timestamp),
            pluginRepoSubdomain: string.concat("fork-cdp-campaign-", timestamp),
            pluginMaintainer: pluginMaintainer
        });

        CDPWithDAODeployment memory deployment = deployer.deployDAOWithCDP(params);

        // Mock token for campaign
        address mockToken = makeAddr("campaignToken");
        address mockVotingEscrow = makeAddr("campaignVE");

        // Create a simple merkle root (single leaf for testing)
        address testRecipient = makeAddr("recipient");
        uint256 testAmount = 1000e18;
        bytes32 merkleRoot = keccak256(abi.encodePacked(testRecipient, testAmount));

        // Create campaign (must be called by DAO)
        vm.prank(address(deployment.dao));
        uint256 campaignId = deployment.capitalDistributorPlugin
            .createCampaign(
                bytes("ipfs://test-campaign"),
                ICapitalDistributorPlugin.StrategyConfig({
                    strategyId: deployer.MERKLE_STRATEGY_ID(), strategyParams: "", initData: abi.encode(merkleRoot)
                }),
                ICapitalDistributorPlugin.PayoutConfig({
                    actionEncoderId: deployer.VOTING_ESCROW_ENCODER_ID(),
                    actionEncoderInitData: infra.votingEscrowEncoder.encodeSetupCampaignParams(mockVotingEscrow),
                    token: IERC20(mockToken)
                }),
                ICapitalDistributorPlugin.CampaignSettings({ startTime: 0, endTime: 0 })
            );

        // Verify campaign created
        assertEq(campaignId, 0, "Campaign ID should be 0 (first campaign)");

        ICapitalDistributorPlugin.Campaign memory campaign = deployment.capitalDistributorPlugin.getCampaign(campaignId);
        assertEq(string(campaign.metadataUri), "ipfs://test-campaign", "Campaign metadata mismatch");
        assertTrue(address(campaign.allocationStrategy) != address(0), "Campaign strategy not set");
        assertTrue(address(campaign.actionEncoder) != address(0), "Campaign encoder not set");

        console.log("Campaign created successfully");
        console.log("  Campaign ID:", campaignId);
    }

    // =============================================================================
    // Edge Case Tests
    // =============================================================================

    /// @notice Test deploying infrastructure with fees
    function test_Fork_DeployInfrastructureWithFees() public {
        deployer = new CDPDeployer();

        address feeRecipient = makeAddr("feeRecipient");
        uint32 feeBasisPoints = 100; // 1%

        CDPInfraDeployment memory infra = deployer.deployInfrastructure(
            CDPInfraParams({
                feeRecipient: feeRecipient, feeBasisPoints: feeBasisPoints, encoderType: EncoderType.VotingEscrow
            })
        );

        // Verify fee configuration via strategyFees mapping
        (address registeredFeeRecipient, uint32 registeredFee) =
            infra.strategyFactory.strategyFees(deployer.MERKLE_STRATEGY_ID());
        assertEq(registeredFeeRecipient, feeRecipient, "Fee recipient mismatch");
        assertEq(registeredFee, feeBasisPoints, "Fee basis points mismatch");

        console.log("Infrastructure with fees deployed");
        console.log("  Fee Recipient:", feeRecipient);
        console.log("  Fee Basis Points:", feeBasisPoints);
    }

    /// @notice Test that deployment reverts with zero addresses
    function test_Fork_RevertOnZeroAddresses() public {
        deployer = new CDPDeployer();

        CDPInfraDeployment memory infra = deployer.deployInfrastructure(
            CDPInfraParams({ feeRecipient: address(0), feeBasisPoints: 0, encoderType: EncoderType.VotingEscrow })
        );

        // Try to deploy with zero daoFactory
        OSxAddresses memory badOsx = osx;
        badOsx.daoFactory = address(0);

        CDPWithDAOParams memory params = CDPWithDAOParams({
            osx: badOsx,
            infra: infra,
            daoAdmin: admin,
            daoUri: "ipfs://test",
            daoName: "test",
            pluginRepoSubdomain: "test",
            pluginMaintainer: pluginMaintainer
        });

        vm.expectRevert(abi.encodeWithSelector(CDPDeployer.ZeroAddress.selector, "daoFactory"));
        deployer.deployDAOWithCDP(params);
    }

    /// @notice Test creating plugin repo with zero maintainer reverts
    function test_Fork_RevertOnZeroMaintainer() public {
        deployer = new CDPDeployer();

        vm.expectRevert(abi.encodeWithSelector(CDPDeployer.ZeroAddress.selector, "maintainer"));
        deployer.createPluginRepo(osx.pluginRepoFactory, "test-subdomain", address(0));
    }
}
