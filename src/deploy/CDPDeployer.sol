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

// VE Governance deployment
import { SetupVe, VeDeployment, VeDeploymentParams } from "./SetupVe.sol";

// OSx deployment (test helper for fresh deployments)
import { ProtocolFactoryBuilder } from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";
import { ProtocolFactory } from "@aragon/protocol-factory/src/ProtocolFactory.sol";

// Aragon/OSx imports
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { DAOFactory } from "@aragon/osx/framework/dao/DAOFactory.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginSetupRef, hashHelpers } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import { IPluginSetup } from "@aragon/commons/plugin/setup/IPluginSetup.sol";
import { IPlugin } from "@aragon/commons/plugin/IPlugin.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";

// VE Governance imports
import { VotingEscrowV1_2_0 as VotingEscrow } from "@ve/escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { DynamicExitQueue as ExitQueue } from "@ve/queue/DynamicExitQueue.sol";

// OpenZeppelin imports
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @dev Minimal Vm interface for prank functions
interface IVm {
    function startPrank(address msgSender) external;
    function stopPrank() external;
}

// =============================================================================
// Structs
// =============================================================================

/// @notice Encoder types that can be deployed
enum EncoderType {
    None,
    VotingEscrow,
    VaultDeposit
}

/// @notice Parameters for deploying CDP infrastructure (factories, strategies, encoders)
struct CDPInfraParams {
    /// @notice Recipient for protocol fees (can be address(0) for no fees)
    address feeRecipient;
    /// @notice Fee in basis points (e.g., 100 = 1%)
    uint32 feeBasisPoints;
    /// @notice Which encoder(s) to deploy and register
    EncoderType encoderType;
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

/// @notice Parameters for deploying a new DAO with CDP plugin installed
struct CDPWithDAOParams {
    /// @notice OSx infrastructure addresses
    OSxAddresses osx;
    /// @notice CDP infrastructure (factories, strategies)
    CDPInfraDeployment infra;
    /// @notice Address that will control the Admin plugin
    address daoAdmin;
    /// @notice DAO metadata URI
    string daoUri;
    /// @notice DAO name/subdomain
    string daoName;
    /// @notice Plugin repo ENS subdomain
    string pluginRepoSubdomain;
    /// @notice Address that can maintain the plugin repo
    address pluginMaintainer;
}

/// @notice Result of deploying a DAO with CDP plugin
struct CDPWithDAODeployment {
    DAO dao;
    CapitalDistributorPlugin capitalDistributorPlugin;
    ExecuteSelectorCondition executeCondition;
    address adminPlugin;
    PluginRepo pluginRepo;
    CDPInfraDeployment infra;
}

/// @notice Parameters for configuring the ExecuteSelectorCondition for VE locks
struct ConditionConfig {
    /// @notice Target address for first allowed action (e.g., token for approve)
    address targetOne;
    /// @notice Selector for first allowed action
    bytes4 selectorOne;
    /// @notice Target address for second allowed action (e.g., votingEscrow for createLockFor)
    address targetTwo;
    /// @notice Selector for second allowed action
    bytes4 selectorTwo;
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
    CapitalDistributorPlugin plugin;
    ExecuteSelectorCondition condition;
    PluginRepo pluginRepo;
    PluginSetupRef pluginSetupRef;
    IPluginSetup.PreparedSetupData preparedSetupData;
}

/// @notice Parameters for full stack deployment (OSx + VE + CDP)
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

/// @notice Result of full stack deployment
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
}

// =============================================================================
// CDPDeployer Contract
// =============================================================================

/// @title CDPDeployer
/// @notice Utility contract for deploying Capital Distributor Plugin infrastructure
/// @dev Handles all deployment scenarios:
///      - Full stack deployment (OSx + VE + CDP) for local testing
///      - CDP-only deployment with existing OSx (for production)
///      - CDP installation into existing DAO
contract CDPDeployer {
    /// @notice Foundry VM for pranks during setup (used in test deployments)
    IVm private constant vm = IVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    // Strategy and encoder type IDs
    bytes32 public constant MERKLE_STRATEGY_ID = bytes32("merkle-distributor-strategy");
    bytes32 public constant VOTING_ESCROW_ENCODER_ID = bytes32("voting-escrow-lock-encoder");
    bytes32 public constant VAULT_DEPOSIT_ENCODER_ID = bytes32("vault-deposit-encoder");

    // =============================================================================
    // Errors
    // =============================================================================

    error ZeroAddress(string param);
    error InvalidConditionSelectorConfig();

    // =============================================================================
    // Full Stack Deployment (OSx + VE + CDP)
    // =============================================================================

    /**
     * @notice Deploys the complete stack: fresh OSx, VE governance, and CDP plugin
     * @dev This is the main entry point for local test deployments.
     *      Deploys everything from scratch including OSx protocol.
     * @param params Full stack deployment parameters
     * @return deployment Struct containing all deployed contracts
     */
    function deployFullStack(FullStackParams memory params) external returns (FullStackDeployment memory deployment) {
        if (params.token == address(0)) revert ZeroAddress("token");
        if (params.admin == address(0)) revert ZeroAddress("admin");

        // 1. Deploy fresh OSx infrastructure
        deployment.osxDeployment = _deployFreshOSx();

        // 2. Deploy VE governance system
        deployment.veDeployment = _deployVeGovernance(params.admin, params.token, deployment.osxDeployment);

        deployment.dao = deployment.veDeployment.dao;
        deployment.votingEscrow = VotingEscrow(address(deployment.veDeployment.pluginSet.votingEscrow));
        deployment.exitQueue = ExitQueue(address(deployment.veDeployment.pluginSet.exitQueue));

        // 3. Deploy CDP infrastructure (with VotingEscrow encoder for full stack VE deployment)
        deployment.cdpInfra = deployInfrastructure(
            CDPInfraParams({
                feeRecipient: params.feeRecipient,
                feeBasisPoints: params.feeBasisPoints,
                encoderType: EncoderType.VotingEscrow
            })
        );

        // 4. Install CDP plugin into VE DAO
        (deployment.capitalDistributorPlugin, deployment.condition) = _installCDPIntoDAO(
            deployment.dao, deployment.osxDeployment, deployment.cdpInfra, params.admin, params.pluginRepoSubdomain
        );

        ConditionConfig memory conditionConfig = ConditionConfig({
            targetOne: address(params.token),
            selectorOne: IERC20.approve.selector,
            targetTwo: address(deployment.votingEscrow),
            selectorTwo: bytes4(keccak256("createLockFor(uint256,address)"))
        });

        // 5. Configure condition for VE operations
        vm.startPrank(address(deployment.dao));
        configureCondition(deployment.condition, conditionConfig);
        vm.stopPrank();

        return deployment;
    }

    /**
     * @dev Deploys fresh OSx infrastructure using ProtocolFactoryBuilder
     */
    function _deployFreshOSx() internal returns (ProtocolFactory.Deployment memory osxDeployment) {
        ProtocolFactory factory = new ProtocolFactoryBuilder().build();
        factory.deployOnce();
        return factory.getDeployment();
    }

    /**
     * @dev Deploys VE governance system using SetupVe
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
     * @dev Installs CDP plugin into an existing DAO using PSP with vm.prank
     */
    function _installCDPIntoDAO(
        DAO dao,
        ProtocolFactory.Deployment memory osxDeployment,
        CDPInfraDeployment memory cdpInfra,
        address pluginMaintainer,
        string memory pluginRepoSubdomain
    )
        internal
        returns (CapitalDistributorPlugin plugin, ExecuteSelectorCondition condition)
    {
        // Prepare installation
        InstallCDPParams memory installParams = InstallCDPParams({
            dao: dao,
            osx: OSxAddresses({
                daoFactory: osxDeployment.daoFactory,
                pluginRepoFactory: osxDeployment.pluginRepoFactory,
                pluginSetupProcessor: osxDeployment.pluginSetupProcessor,
                adminPluginRepo: osxDeployment.adminPluginRepo,
                multisigPluginRepo: osxDeployment.multisigPluginRepo
            }),
            infra: cdpInfra,
            pluginMaintainer: pluginMaintainer,
            pluginRepoSubdomain: pluginRepoSubdomain
        });

        PreparedCDPInstallation memory prepared = prepareInstallation(installParams);
        plugin = prepared.plugin;
        condition = prepared.condition;

        // Apply installation using vm.prank for permissions
        PluginSetupProcessor psp = PluginSetupProcessor(osxDeployment.pluginSetupProcessor);

        vm.startPrank(address(dao));
        dao.grant(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
        dao.grant(address(psp), address(this), psp.APPLY_INSTALLATION_PERMISSION_ID());
        vm.stopPrank();

        PluginSetupProcessor.ApplyInstallationParams memory applyParams = buildApplyInstallationParams(prepared);
        psp.applyInstallation(address(dao), applyParams);

        // Revoke temporary permissions
        vm.startPrank(address(dao));
        dao.revoke(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
        dao.revoke(address(psp), address(this), psp.APPLY_INSTALLATION_PERMISSION_ID());
        vm.stopPrank();
    }

    // =============================================================================
    // Infrastructure Deployment
    // =============================================================================

    /**
     * @notice Deploys CDP infrastructure: factories, strategies, and encoders
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

        // Deploy and register encoder based on encoderType
        if (params.encoderType == EncoderType.VotingEscrow) {
            deployment.votingEscrowEncoder = new VotingEscrowLockPayoutActionEncoder();
            deployment.encoderFactory
                .registerActionEncoder(VOTING_ESCROW_ENCODER_ID, address(deployment.votingEscrowEncoder), "");
        } else if (params.encoderType == EncoderType.VaultDeposit) {
            deployment.vaultDepositEncoder = new VaultDepositPayoutActionEncoder();
            deployment.encoderFactory
                .registerActionEncoder(VAULT_DEPOSIT_ENCODER_ID, address(deployment.vaultDepositEncoder), "");
        }

        return deployment;
    }

    // =============================================================================
    // Plugin Repo Deployment
    // =============================================================================

    /**
     * @notice Creates a plugin repo with the CDP plugin setup
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

    // =============================================================================
    // Full DAO + CDP Deployment (via DAOFactory) - For Production
    // =============================================================================

    /**
     * @notice Deploys a new DAO with CDP plugin installed using DAOFactory
     * @dev Uses DAOFactory.createDao which handles all permission setup internally.
     *      This is for production deployments with existing OSx.
     * @param params Deployment parameters including OSx addresses and configuration
     * @return deployment Struct containing all deployed contracts
     */
    function deployDAOWithCDP(CDPWithDAOParams memory params)
        external
        returns (CDPWithDAODeployment memory deployment)
    {
        _validateOSxAddresses(params.osx);

        deployment.infra = params.infra;

        // Create plugin repo
        (deployment.pluginRepo,) =
            createPluginRepo(params.osx.pluginRepoFactory, params.pluginRepoSubdomain, params.pluginMaintainer);

        // Prepare and execute deployment
        (deployment.dao, deployment.capitalDistributorPlugin, deployment.executeCondition, deployment.adminPlugin) =
            _createDAOWithPlugins(params, deployment.pluginRepo);

        return deployment;
    }

    // =============================================================================
    // Install CDP into Existing DAO (via PSP)
    // =============================================================================

    /**
     * @notice Prepares CDP plugin installation into an existing DAO
     * @dev This function creates the plugin repo and prepares the installation.
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

        prepared.plugin = CapitalDistributorPlugin(pluginAddr);
        prepared.condition = ExecuteSelectorCondition(prepared.preparedSetupData.helpers[0]);

        return prepared;
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

    // =============================================================================
    // Condition Configuration
    // =============================================================================

    /**
     * @notice Configures the ExecuteSelectorCondition to allow specific selectors
     * @dev Must be called by an address with MANAGE_SELECTORS_PERMISSION on the condition
     * @param condition The condition contract to configure
     * @param config The selector configuration
     */
    function configureCondition(ExecuteSelectorCondition condition, ConditionConfig memory config) public {
        if (
            config.targetOne == address(0) || config.selectorOne == bytes4(0) || config.targetTwo == address(0)
                || config.selectorTwo == bytes4(0)
        ) {
            revert InvalidConditionSelectorConfig();
        }

        // Allow target one selector
        ExecuteSelectorCondition.SelectorTarget memory targetOne =
            ExecuteSelectorCondition.SelectorTarget({ where: config.targetOne, selectors: new bytes4[](1) });
        targetOne.selectors[0] = config.selectorOne;
        condition.allowSelectors(targetOne);

        // Allow target two selector
        ExecuteSelectorCondition.SelectorTarget memory targetTwo =
            ExecuteSelectorCondition.SelectorTarget({ where: config.targetTwo, selectors: new bytes4[](1) });
        targetTwo.selectors[0] = config.selectorTwo;
        condition.allowSelectors(targetTwo);
    }

    // =============================================================================
    // Internal Functions - DAO Creation
    // =============================================================================

    function _createDAOWithPlugins(
        CDPWithDAOParams memory params,
        PluginRepo cdpPluginRepo
    )
        internal
        returns (DAO dao, CapitalDistributorPlugin cdpPlugin, ExecuteSelectorCondition condition, address adminPlugin)
    {
        DAOFactory.DAOSettings memory daoSettings = _buildDAOSettings(params.daoUri, params.daoName);
        DAOFactory.PluginSettings[] memory pluginSettings =
            _buildPluginSettings(params.infra, params.osx.adminPluginRepo, params.daoAdmin, cdpPluginRepo);

        DAOFactory.InstalledPlugin[] memory installedPlugins;
        (dao, installedPlugins) = DAOFactory(params.osx.daoFactory).createDao(daoSettings, pluginSettings);

        cdpPlugin = CapitalDistributorPlugin(installedPlugins[0].plugin);
        condition = ExecuteSelectorCondition(installedPlugins[0].preparedSetupData.helpers[0]);
        adminPlugin = installedPlugins[1].plugin;
    }

    function _buildDAOSettings(
        string memory daoUri,
        string memory daoName
    )
        internal
        pure
        returns (DAOFactory.DAOSettings memory)
    {
        return
            DAOFactory.DAOSettings({ trustedForwarder: address(0), daoURI: daoUri, subdomain: daoName, metadata: "" });
    }

    function _buildPluginSettings(
        CDPInfraDeployment memory infra,
        address adminPluginRepo,
        address daoAdmin,
        PluginRepo cdpPluginRepo
    )
        internal
        pure
        returns (DAOFactory.PluginSettings[] memory pluginSettings)
    {
        pluginSettings = new DAOFactory.PluginSettings[](2);
        pluginSettings[0] = _buildCDPPluginSettings(infra, cdpPluginRepo);
        pluginSettings[1] = _buildAdminPluginSettings(adminPluginRepo, daoAdmin);
    }

    function _buildCDPPluginSettings(
        CDPInfraDeployment memory infra,
        PluginRepo cdpPluginRepo
    )
        internal
        pure
        returns (DAOFactory.PluginSettings memory)
    {
        bytes memory cdpInstallData = abi.encode(address(infra.strategyFactory), address(infra.encoderFactory));

        return DAOFactory.PluginSettings({
            pluginSetupRef: PluginSetupRef({
                versionTag: PluginRepo.Tag({ release: 1, build: 1 }), pluginSetupRepo: cdpPluginRepo
            }),
            data: cdpInstallData
        });
    }

    function _buildAdminPluginSettings(
        address adminPluginRepo,
        address daoAdmin
    )
        internal
        pure
        returns (DAOFactory.PluginSettings memory)
    {
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({ target: address(0), operation: IPlugin.Operation.Call });

        return DAOFactory.PluginSettings({
            pluginSetupRef: PluginSetupRef({
                versionTag: PluginRepo.Tag({ release: 1, build: 2 }), pluginSetupRepo: PluginRepo(adminPluginRepo)
            }),
            data: abi.encode(daoAdmin, targetConfig)
        });
    }

    // =============================================================================
    // Utilities
    // =============================================================================

    function toBytes32(string memory source) external pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        require(temp.length <= 32, "String too long");

        assembly ("memory-safe") {
            result := mload(add(temp, 32))
        }
    }

    function _validateOSxAddresses(OSxAddresses memory osx) internal pure {
        if (osx.daoFactory == address(0)) revert ZeroAddress("daoFactory");
        if (osx.pluginRepoFactory == address(0)) revert ZeroAddress("pluginRepoFactory");
        if (osx.pluginSetupProcessor == address(0)) revert ZeroAddress("pluginSetupProcessor");
        if (osx.adminPluginRepo == address(0)) revert ZeroAddress("adminPluginRepo");
    }
}
