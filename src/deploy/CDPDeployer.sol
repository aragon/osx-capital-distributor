// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

// Capital Distributor imports
import { CapitalDistributorPlugin } from "../CapitalDistributorPlugin.sol";
import { CapitalDistributorPluginSetup } from "../CapitalDistributorPluginSetup.sol";
import { AllocatorStrategyFactory } from "../factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../factories/ActionEncoderFactory.sol";
import { MerkleDistributorStrategy } from "../allocatorStrategies/MerkleDistributorStrategy.sol";
import { VotingEscrowLockPayoutActionEncoder } from "../payoutActionEncoders/VotingEscrowLockPayoutActionEncoder.sol";
import { VaultDepositPayoutActionEncoder } from "../payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";

// VE Governance deployment (for local tests)
import { SetupVe, VeDeployment, VeDeploymentParams } from "./SetupVe.sol";

// OSx deployment (for local tests - fresh deployments)
import { ProtocolFactoryBuilder } from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";
import { ProtocolFactory } from "@aragon/protocol-factory/src/ProtocolFactory.sol";

// Aragon/OSx imports
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { Action } from "@aragon/commons/executors/IExecutor.sol";
import { DAOFactory } from "@aragon/osx/framework/dao/DAOFactory.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginSetupRef, hashHelpers } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import { IPluginSetup } from "@aragon/commons/plugin/setup/IPluginSetup.sol";
import { IPlugin } from "@aragon/commons/plugin/IPlugin.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";

// VE Governance imports (for local tests)
import { VotingEscrowV1_2_0 as VotingEscrow } from "@ve/escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { DynamicExitQueue as ExitQueue } from "@ve/queue/DynamicExitQueue.sol";

// OpenZeppelin imports
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

// #############################################################################################
//
//                              STRUCTS - PRODUCTION DEPLOYMENT
//
// #############################################################################################

/// @notice Parameters for deploying CDP infrastructure (factories, strategies, encoders)
struct CDPInfraParams {
    /// @notice Recipient for protocol fees (can be address(0) for no fees)
    address feeRecipient;
    /// @notice Fee in basis points (e.g., 100 = 1%)
    uint32 feeBasisPoints;
}

/// @notice Result of deploying CDP infrastructure
struct CDPInfraDeployment {
    AllocatorStrategyFactory strategyFactory;
    ActionEncoderFactory encoderFactory;
    MerkleDistributorStrategy merkleStrategy;
    VotingEscrowLockPayoutActionEncoder votingEscrowEncoder;
    VaultDepositPayoutActionEncoder vaultDepositEncoder;
}

/// @notice OSx deployment addresses required for CDP deployment
struct OSxAddresses {
    address daoFactory;
    address pluginRepoFactory;
    address pluginSetupProcessor;
    /// @notice Admin plugin repo for the Admin plugin (used as secondary governance)
    address adminPluginRepo;
    /// @notice Multisig plugin repo for VE governance
    address multisigPluginRepo;
}

/// @notice Parameters for installing CDP into an existing DAO
struct InstallCDPParams {
    /// @notice The existing DAO to install CDP into
    DAO dao;
    /// @notice OSx infrastructure addresses
    OSxAddresses osx;
    /// @notice CDP infrastructure (factories, strategies)
    CDPInfraDeployment infra;
    /// @notice Plugin repo maintainer address
    address pluginMaintainer;
    /// @notice Plugin repo ENS subdomain
    string pluginRepoSubdomain;
}

/// @notice Result of preparing CDP installation
struct PreparedCDPInstallation {
    DAO dao;
    CapitalDistributorPlugin plugin;
    ExecuteSelectorCondition condition;
    PluginRepo pluginRepo;
    PluginSetupRef pluginSetupRef;
    IPluginSetup.PreparedSetupData preparedSetupData;
}

/// @notice Parameters for configuring the ExecuteSelectorCondition
struct ConditionConfig {
    /// @notice Target address for allowed action (e.g., token for approve)
    address target;
    /// @notice Selector for allowed action
    bytes4 selector;
}

/// @notice Parameters for VE (Voting Escrow) condition configuration in installation actions
/// @dev Used by buildInstallationActions() to configure condition for VE payout flows
struct VEConditionParams {
    /// @notice The token address (for approve selector)
    address token;
    /// @notice The VotingEscrow address (for createLockFor selector)
    address votingEscrow;
}

// #############################################################################################
//
//                              STRUCTS - LOCAL TEST DEPLOYMENT
//
// #############################################################################################

/// @notice Parameters for full stack deployment (OSx + VE + CDP) - LOCAL TESTS ONLY
struct FullStackParams {
    /// @notice Admin address for all deployments
    address admin;
    /// @notice Token to use (address(0) means deploy new MintableERC20 externally)
    address token;
    /// @notice Protocol fee recipient (can be address(0) for no fees)
    address feeRecipient;
    /// @notice Protocol fee in basis points
    uint32 feeBasisPoints;
    /// @notice Plugin repo subdomain for CDP
    string pluginRepoSubdomain;
}

/// @notice Result of full stack deployment - LOCAL TESTS ONLY
struct FullStackDeployment {
    // Core contracts
    DAO dao;
    CapitalDistributorPlugin capitalDistributorPlugin;
    ExecuteSelectorCondition condition;
    // CDP infrastructure
    CDPInfraDeployment cdpInfra;
    // VE Governance contracts
    VotingEscrow votingEscrow;
    ExitQueue exitQueue;
    // Underlying deployments
    ProtocolFactory.Deployment osxDeployment;
    VeDeployment veDeployment;
    // Prepared installation (for applyInstallation)
    PreparedCDPInstallation preparedInstallation;
    PluginSetupProcessor pluginSetupProcessor;
}

// #############################################################################################
//
//                                    CDP DEPLOYER CONTRACT
//
// #############################################################################################

/// @title CDPDeployer
/// @notice Utility contract for deploying Capital Distributor Plugin infrastructure
/// @dev Handles two deployment scenarios:
///      1. PRODUCTION: Install CDP into existing DAO (e.g., Katana DAO)
///      2. LOCAL TESTS: Full stack deployment (fresh OSx + VE + CDP)
contract CDPDeployer {
    // =====================================================================================
    // Constants
    // =====================================================================================

    bytes32 public constant MERKLE_STRATEGY_ID = bytes32("merkle-distributor-strategy");
    bytes32 public constant VOTING_ESCROW_ENCODER_ID = bytes32("voting-escrow-lock-encoder");
    bytes32 public constant VAULT_DEPOSIT_ENCODER_ID = bytes32("vault-deposit-encoder");

    // =====================================================================================
    // Errors
    // =====================================================================================

    error ZeroAddress(string param);
    error InvalidConditionSelectorConfig();

    // #############################################################################################
    //
    //                      PRODUCTION DEPLOYMENT FUNCTIONS
    //
    //     Use these functions when deploying to mainnet/testnet with existing OSx infrastructure
    //
    // #############################################################################################

    // =====================================================================================
    // CDP Infrastructure Deployment i.e. strategies and encoders
    // =====================================================================================

    /**
     * @notice Deploys CDP infrastructure: factories, strategies, and encoders
     * @dev This is permissionless and can be called by anyone.
     * @param params Infrastructure deployment parameters
     * @return deployment Struct containing all deployed infrastructure contracts
     */
    function deployInfrastructure(CDPInfraParams memory params) public returns (CDPInfraDeployment memory deployment) {
        // Deploy factories
        deployment.strategyFactory = new AllocatorStrategyFactory();
        deployment.encoderFactory = new ActionEncoderFactory();

        // Deploy and register merkle strategy
        deployment.merkleStrategy = new MerkleDistributorStrategy();
        deployment.strategyFactory
            .registerStrategyType(
                MERKLE_STRATEGY_ID, address(deployment.merkleStrategy), "", params.feeRecipient, params.feeBasisPoints
            );

        // Deploy and register encoders
        deployment.votingEscrowEncoder = new VotingEscrowLockPayoutActionEncoder();
        deployment.encoderFactory
            .registerActionEncoder(VOTING_ESCROW_ENCODER_ID, address(deployment.votingEscrowEncoder), "");
        deployment.vaultDepositEncoder = new VaultDepositPayoutActionEncoder();
        deployment.encoderFactory
            .registerActionEncoder(VAULT_DEPOSIT_ENCODER_ID, address(deployment.vaultDepositEncoder), "");

        return deployment;
    }

    // =====================================================================================
    // Plugin Repo Deployment
    // =====================================================================================

    /**
     * @notice Creates a plugin repo with the CDP plugin setup
     * @dev This is permissionless and can be called by anyone.
     * @param pluginRepoFactory The OSx PluginRepoFactory address
     * @param subdomain ENS subdomain for the plugin repo
     * @param maintainer Address that can maintain the repo
     * @return pluginRepo The created plugin repo
     * @return pluginSetup The deployed plugin setup
     */
    function createPluginRepo(
        address pluginRepoFactory,
        string memory subdomain,
        address maintainer
    )
        public
        returns (PluginRepo pluginRepo, CapitalDistributorPluginSetup pluginSetup)
    {
        if (pluginRepoFactory == address(0)) revert ZeroAddress("pluginRepoFactory");
        if (maintainer == address(0)) revert ZeroAddress("maintainer");

        pluginSetup = new CapitalDistributorPluginSetup();

        pluginRepo = PluginRepoFactory(pluginRepoFactory)
            .createPluginRepoWithFirstVersion(
                subdomain,
                address(pluginSetup),
                maintainer,
                bytes("ipfs://release-metadata"),
                bytes("ipfs://build-metadata")
            );

        return (pluginRepo, pluginSetup);
    }

    // =====================================================================================
    // Prepare Installation (via PSP)
    // =====================================================================================

    /**
     * @notice Prepares CDP plugin installation into an existing DAO
     * @dev This is permissionless. Creates the plugin repo and prepares the installation.
     *      After calling this, use applyInstallation() or buildInstallationActions() to complete.
     * @param params Installation parameters
     * @return prepared Struct containing prepared installation data
     */
    function prepareInstallation(InstallCDPParams memory params)
        public
        returns (PreparedCDPInstallation memory prepared)
    {
        if (address(params.dao) == address(0)) revert ZeroAddress("dao");
        if (params.osx.pluginRepoFactory == address(0)) revert ZeroAddress("pluginRepoFactory");
        if (params.osx.pluginSetupProcessor == address(0)) revert ZeroAddress("pluginSetupProcessor");

        // Create plugin repo
        (prepared.pluginRepo,) =
            createPluginRepo(params.osx.pluginRepoFactory, params.pluginRepoSubdomain, params.pluginMaintainer);

        // Prepare installation via PSP
        PluginSetupProcessor psp = PluginSetupProcessor(params.osx.pluginSetupProcessor);
        prepared.pluginSetupRef = PluginSetupRef({
            versionTag: PluginRepo.Tag({ release: 1, build: 1 }), pluginSetupRepo: prepared.pluginRepo
        });

        bytes memory installData =
            abi.encode(address(params.infra.strategyFactory), address(params.infra.encoderFactory));

        address pluginAddr;
        (pluginAddr, prepared.preparedSetupData) = psp.prepareInstallation(
            address(params.dao),
            PluginSetupProcessor.PrepareInstallationParams({
                pluginSetupRef: prepared.pluginSetupRef, data: installData
            })
        );

        prepared.dao = params.dao;
        prepared.plugin = CapitalDistributorPlugin(pluginAddr);
        prepared.condition = ExecuteSelectorCondition(prepared.preparedSetupData.helpers[0]);

        return prepared;
    }

    // =====================================================================================
    // Condition Configuration
    // =====================================================================================

    /**
     * @notice Configures the ExecuteSelectorCondition to allow specific selectors
     * @dev REQUIRES PERMISSIONS. Must be called by an address with MANAGE_SELECTORS_PERMISSION on the condition.
     * @param condition The condition contract to configure
     * @param configs The selector configurations to allow
     */
    function configureCondition(ExecuteSelectorCondition condition, ConditionConfig[] memory configs) public {
        for (uint256 i = 0; i < configs.length; i++) {
            if (configs[i].target == address(0) || configs[i].selector == bytes4(0)) {
                revert InvalidConditionSelectorConfig();
            }
        }

        for (uint256 i = 0; i < configs.length; i++) {
            ExecuteSelectorCondition.SelectorTarget memory target =
                ExecuteSelectorCondition.SelectorTarget({ where: configs[i].target, selectors: new bytes4[](1) });
            target.selectors[0] = configs[i].selector;
            condition.allowSelectors(target);
        }
    }

    // =====================================================================================
    // Calldata Building Helpers (for DAO proposal execution)
    // =====================================================================================

    bytes4 private constant GRANT_SELECTOR = bytes4(keccak256("grant(address,address,bytes32)"));
    bytes4 private constant REVOKE_SELECTOR = bytes4(keccak256("revoke(address,address,bytes32)"));

    /**
     * @notice Build calldata for DAO to execute applyInstallation via PSP
     * @dev Returns the raw calldata for psp.applyInstallation() that can be executed by the DAO
     * @param prepared The prepared installation data
     * @return calldata_ The encoded calldata for applyInstallation
     */
    function buildApplyInstallationCalldata(PreparedCDPInstallation memory prepared)
        public
        pure
        returns (bytes memory calldata_)
    {
        PluginSetupProcessor.ApplyInstallationParams memory applyParams =
            PluginSetupProcessor.ApplyInstallationParams({
                pluginSetupRef: prepared.pluginSetupRef,
                plugin: address(prepared.plugin),
                permissions: prepared.preparedSetupData.permissions,
                helpersHash: hashHelpers(prepared.preparedSetupData.helpers)
            });

        return abi.encodeCall(PluginSetupProcessor.applyInstallation, (address(prepared.dao), applyParams));
    }

    /**
     * @notice Build calldata for granting ROOT_PERMISSION to PSP
     * @param dao The DAO address
     * @param psp The PluginSetupProcessor address
     * @return calldata_ The encoded calldata for dao.grant()
     */
    function buildGrantRootToPSPCalldata(address dao, address psp) public pure returns (bytes memory calldata_) {
        bytes32 rootPermissionId = keccak256("ROOT_PERMISSION");
        return abi.encodeWithSelector(GRANT_SELECTOR, dao, psp, rootPermissionId);
    }

    /**
     * @notice Build calldata for revoking ROOT_PERMISSION from PSP
     * @param dao The DAO address
     * @param psp The PluginSetupProcessor address
     * @return calldata_ The encoded calldata for dao.revoke()
     */
    function buildRevokeRootFromPSPCalldata(address dao, address psp) public pure returns (bytes memory calldata_) {
        bytes32 rootPermissionId = keccak256("ROOT_PERMISSION");
        return abi.encodeWithSelector(REVOKE_SELECTOR, dao, psp, rootPermissionId);
    }

    /**
     * @notice Build calldata for condition.allowSelectors()
     * @param target The target address (e.g., token or votingEscrow)
     * @param selector The function selector to allow
     * @return calldata_ The encoded calldata for condition.allowSelectors()
     */
    function buildAllowSelectorsCalldata(
        address target,
        bytes4 selector
    )
        public
        pure
        returns (bytes memory calldata_)
    {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        ExecuteSelectorCondition.SelectorTarget memory selectorTarget =
            ExecuteSelectorCondition.SelectorTarget({ where: target, selectors: selectors });
        return abi.encodeCall(ExecuteSelectorCondition.allowSelectors, (selectorTarget));
    }

    /**
     * @notice Build Action array for the complete installation process including condition configuration
     * @dev Returns actions for: grant ROOT → applyInstallation → revoke ROOT → configure condition
     *      These actions can be executed via a DAO proposal.
     *      The condition configuration allows the plugin to call:
     *        - token.approve() for ERC20 approvals
     *        - votingEscrow.createLockFor() for creating VE locks
     * @param dao The DAO address
     * @param psp The PluginSetupProcessor address
     * @param prepared The prepared installation data
     * @param veParams The VE condition configuration params (token and votingEscrow addresses)
     * @return actions The array of Actions to execute
     */
    function buildInstallationActions(
        address dao,
        address psp,
        PreparedCDPInstallation memory prepared,
        VEConditionParams memory veParams
    )
        public
        pure
        returns (Action[] memory actions)
    {
        actions = new Action[](5);

        // 1. Grant ROOT_PERMISSION to PSP
        actions[0] = Action({ to: dao, value: 0, data: buildGrantRootToPSPCalldata(dao, psp) });

        // 2. Apply installation
        actions[1] = Action({ to: psp, value: 0, data: buildApplyInstallationCalldata(prepared) });

        // 3. Revoke ROOT_PERMISSION from PSP
        actions[2] = Action({ to: dao, value: 0, data: buildRevokeRootFromPSPCalldata(dao, psp) });

        // 4. Allow token.approve() on condition (for ERC20 approvals before VE lock)
        actions[3] = Action({
            to: address(prepared.condition),
            value: 0,
            data: buildAllowSelectorsCalldata(veParams.token, IERC20.approve.selector)
        });

        // 5. Allow votingEscrow.createLockFor() on condition (for creating VE locks)
        actions[4] = Action({
            to: address(prepared.condition),
            value: 0,
            data: buildAllowSelectorsCalldata(veParams.votingEscrow, bytes4(keccak256("createLockFor(uint256,address)")))
        });

        return actions;
    }

    // =====================================================================================
    // Utilities
    // =====================================================================================

    function toBytes32(string memory source) external pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        require(temp.length <= 32, "String too long");

        assembly ("memory-safe") {
            result := mload(add(temp, 32))
        }
    }

    // #############################################################################################
    //
    //                        LOCAL TEST DEPLOYMENT FUNCTIONS
    //
    //     Use these functions for local testing when you need fresh OSx + VE infrastructure
    //
    // #############################################################################################

    /**
     * @notice Deploys the complete stack: fresh OSx, VE governance, and CDP plugin
     * @dev LOCAL TESTS ONLY. This is the main entry point for local test deployments.
     *      Deploys everything from scratch including OSx protocol.
     *      After calling, use applyInstallation() to complete the CDP installation.
     * @param params Full stack deployment parameters
     * @return deployment Struct containing all deployed contracts
     */
    function deployFullStack(FullStackParams memory params) external returns (FullStackDeployment memory deployment) {
        if (params.token == address(0)) revert ZeroAddress("token");
        if (params.admin == address(0)) revert ZeroAddress("admin");

        // 1. Deploy fresh OSx infrastructure
        deployment.osxDeployment = _deployFreshOSx();

        // 2. Deploy VE governance system (this creates a DAO with VE plugins)
        deployment.veDeployment = _deployVeGovernance(params.admin, params.token, deployment.osxDeployment);

        deployment.dao = deployment.veDeployment.dao;
        deployment.votingEscrow = VotingEscrow(address(deployment.veDeployment.pluginSet.votingEscrow));
        deployment.exitQueue = ExitQueue(address(deployment.veDeployment.pluginSet.exitQueue));

        // 3. Deploy CDP infrastructure
        deployment.cdpInfra = deployInfrastructure(
            CDPInfraParams({ feeRecipient: params.feeRecipient, feeBasisPoints: params.feeBasisPoints })
        );

        // 4. Store PSP for later use
        deployment.pluginSetupProcessor = PluginSetupProcessor(deployment.osxDeployment.pluginSetupProcessor);

        // 5. Prepare CDP installation into the VE DAO (caller must handle permissions to apply)
        InstallCDPParams memory installParams = InstallCDPParams({
            dao: deployment.dao,
            osx: OSxAddresses({
                daoFactory: deployment.osxDeployment.daoFactory,
                pluginRepoFactory: deployment.osxDeployment.pluginRepoFactory,
                pluginSetupProcessor: deployment.osxDeployment.pluginSetupProcessor,
                adminPluginRepo: deployment.osxDeployment.adminPluginRepo,
                multisigPluginRepo: deployment.osxDeployment.multisigPluginRepo
            }),
            infra: deployment.cdpInfra,
            pluginMaintainer: params.admin,
            pluginRepoSubdomain: params.pluginRepoSubdomain
        });

        deployment.preparedInstallation = prepareInstallation(installParams);
        deployment.capitalDistributorPlugin = deployment.preparedInstallation.plugin;
        deployment.condition = deployment.preparedInstallation.condition;

        return deployment;
    }

    /**
     * @dev Deploys fresh OSx infrastructure using ProtocolFactoryBuilder
     *      LOCAL TESTS ONLY.
     */
    function _deployFreshOSx() internal returns (ProtocolFactory.Deployment memory osxDeployment) {
        ProtocolFactory factory = new ProtocolFactoryBuilder().build();
        factory.deployOnce();
        return factory.getDeployment();
    }

    /**
     * @dev Deploys VE governance system using SetupVe
     *      LOCAL TESTS ONLY.
     */
    function _deployVeGovernance(
        address admin,
        address token,
        ProtocolFactory.Deployment memory osxDeployment
    )
        internal
        returns (VeDeployment memory)
    {
        SetupVe setupVe = new SetupVe();
        return setupVe.deploy(VeDeploymentParams({ admin: admin, token: token, osxDeployment: osxDeployment }));
    }

    /**
     * @notice Apply a prepared CDP installation
     * @dev LOCAL TESTS ONLY. Requires permissions setup before calling.
     *      Required permissions before calling:
     *        - dao.grant(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
     *        - dao.grant(address(psp), caller, psp.APPLY_INSTALLATION_PERMISSION_ID());
     *      Revoke after calling:
     *        - dao.revoke(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
     *        - dao.revoke(address(psp), caller, psp.APPLY_INSTALLATION_PERMISSION_ID());
     *      For production, use buildInstallationActions() to generate DAO proposal actions instead.
     * @param psp The PluginSetupProcessor
     * @param prepared The prepared installation data from prepareInstallation()
     */
    function applyInstallation(PluginSetupProcessor psp, PreparedCDPInstallation memory prepared) public {
        PluginSetupProcessor.ApplyInstallationParams memory applyParams = buildApplyInstallationParams(prepared);
        psp.applyInstallation(address(prepared.dao), applyParams);
    }

    /**
     * @notice Builds the ApplyInstallationParams struct for PSP
     * @param prepared The prepared installation data
     * @return applyParams The params to pass to psp.applyInstallation()
     */
    function buildApplyInstallationParams(PreparedCDPInstallation memory prepared)
        public
        pure
        returns (PluginSetupProcessor.ApplyInstallationParams memory applyParams)
    {
        return PluginSetupProcessor.ApplyInstallationParams({
            pluginSetupRef: prepared.pluginSetupRef,
            plugin: address(prepared.plugin),
            permissions: prepared.preparedSetupData.permissions,
            helpersHash: hashHelpers(prepared.preparedSetupData.helpers)
        });
    }
}
