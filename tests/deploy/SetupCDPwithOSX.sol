// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

// Capital Distributor imports
import { CapitalDistributorPlugin } from "../../src/CapitalDistributorPlugin.sol";
import { CapitalDistributorPluginSetup } from "../../src/CapitalDistributorPluginSetup.sol";
import { AllocatorStrategyFactory } from "../../src/factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../../src/factories/ActionEncoderFactory.sol";
import { MerkleDistributorStrategy } from "../../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import {
    VotingEscrowLockPayoutActionEncoder
} from "../../src/payoutActionEncoders/VotingEscrowLockPayoutActionEncoder.sol";

// Deploy utilities
import { SetupVe, VeDeployment, VeDeploymentParams } from "./SetupVe.sol";

// VE Governance imports
import { VotingEscrowV1_2_0 as VotingEscrow } from "@ve/escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { DynamicExitQueue as ExitQueue } from "@ve/queue/DynamicExitQueue.sol";

// Aragon/OSx imports
import { ProtocolFactoryBuilder } from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";
import { ProtocolFactory } from "@aragon/protocol-factory/src/ProtocolFactory.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { IPluginSetup } from "@aragon/commons/plugin/setup/IPluginSetup.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { PluginSetupRef, hashHelpers } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";

// OpenZeppelin imports
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

// Test utilities
import { MintableERC20 } from "../mocks/MintableERC20.sol";
import { Vm } from "forge-std/Vm.sol";

/// @notice Struct containing the full Capital Distributor deployment results
struct CapitalDistributorDeployment {
    // Core contracts
    DAO dao;
    CapitalDistributorPlugin capitalDistributorPlugin;
    ExecuteSelectorCondition condition;
    // Factories
    AllocatorStrategyFactory strategyFactory;
    ActionEncoderFactory encoderFactory;
    // Registered implementations
    MerkleDistributorStrategy merkleStrategy;
    VotingEscrowLockPayoutActionEncoder votingEscrowEncoder;
    // VE Governance contracts
    VotingEscrow votingEscrow;
    ExitQueue exitQueue;
    // Token
    MintableERC20 token;
    // Underlying deployments
    ProtocolFactory.Deployment osxDeployment;
    VeDeployment veDeployment;
}

/// @notice Parameters needed to deploy the Capital Distributor system
struct CapitalDistributorDeploymentParams {
    address admin;
    /// @notice Optional: If provided, uses this token. If address(0), creates a new MintableERC20.
    address token;
    /// @notice Optional: If provided, uses this OSx deployment. If dao is address(0), deploys new OSx.
    ProtocolFactory.Deployment osxDeployment;
    /// @notice Optional: If provided, uses this VE deployment. If dao is address(0), deploys new VE.
    VeDeployment veDeployment;
    /// @notice Optional: If provided, uses this address as the target of the first action. If address(0), uses the
    /// token.
    address encoderActionTargetAddressOne;
    /// @notice Optional: If provided, uses this address as the target of the second action. If address(0), uses the
    /// voting escrow.
    address encoderActionTargetAddressTwo;
    /// @notice Must be provided if encoderActionTargetAddressOne is provided.
    bytes4 encoderActionTargetSelectorOne;
    /// @notice Must be provided if encoderActionTargetAddressTwo is provided.
    bytes4 encoderActionTargetSelectorTwo;
}

/// @title SetupCDPwithOSX
/// @notice Helper contract to deploy the full Capital Distributor stack locally in Foundry tests
/// @dev This deploys OSx, ve-governance, and Capital Distributor Plugin in one go
contract SetupCDPwithOSX {
    /// @notice Error thrown if encoderActionTargetAddressOne is provided but encoderActionTargetSelectorOne is not.
    error InvalidEncoderActionTargetOneActionSelectorCombo();
    /// @notice Error thrown if encoderActionTargetAddressTwo is provided but encoderActionTargetSelectorTwo is not.
    error InvalidEncoderActionTargetTwoActionSelectorCombo();

    /// @notice Foundry VM for pranks during setup
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    CapitalDistributorDeployment private deployment;

    // Strategy and encoder type IDs
    bytes32 public constant MERKLE_STRATEGY_ID = bytes32("merkle-distributor-strategy");
    bytes32 public constant VOTING_ESCROW_ENCODER_ID = bytes32("voting-escrow-lock-encoder");

    /**
     * @dev Deploys a complete Capital Distributor system including OSx, VE governance, and the plugin
     * @notice This function deploys the entire infrastructure in one transaction
     * @param params Deployment parameters (can provide existing deployments or let it create new ones)
     * @return deployment_ Struct containing all deployed contracts and references
     *
     * Order of operations:
     * 1. Deploy token (if not provided)
     * 2. Deploy OSx infrastructure (if not provided)
     * 3. Deploy VE governance system (if not provided)
     * 4. Deploy Capital Distributor factories
     * 5. Register strategies and encoders
     * 6. Deploy and install Capital Distributor Plugin via PSP
     * 7. Configure ExecuteSelectorCondition for VE operations
     *
     * Should be called by: Test setup or deployment scripts
     * Prerequisites: None (can deploy everything from scratch)
     * Side effects: Stores deployment internally for later retrieval via getDeployment()
     */
    function deploy(CapitalDistributorDeploymentParams memory params)
        external
        returns (CapitalDistributorDeployment memory deployment_)
    {
        // 1-3. Deploy core infrastructure (token, OSx, VE)
        _deployCoreInfrastructure(params);

        // 4-6. Deploy factories and register strategies/encoders
        _deployFactoriesAndRegisterStrategiesAndEncoders();

        // 7-11. Install the Capital Distributor Plugin via PSP
        _installPlugin(params.admin);

        // 12-13. Configure condition and finalize
        _finalizeAndConfigureCondition(params);

        return deployment;
    }

    /**
     * @dev Deploys token, OSx, and VE governance infrastructure
     */
    function _deployCoreInfrastructure(CapitalDistributorDeploymentParams memory params) internal {
        // Deploy or use existing token
        if (params.token == address(0)) {
            deployment.token = new MintableERC20();
        } else {
            deployment.token = MintableERC20(params.token);
        }

        // Deploy or use existing OSx infrastructure
        if (params.osxDeployment.daoFactory == address(0)) {
            ProtocolFactory factory = new ProtocolFactoryBuilder().build();
            factory.deployOnce();
            deployment.osxDeployment = factory.getDeployment();
        } else {
            deployment.osxDeployment = params.osxDeployment;
        }

        // Deploy or use existing VE governance system
        if (address(params.veDeployment.dao) == address(0)) {
            SetupVe setupVe = new SetupVe();
            deployment.veDeployment = setupVe.deploy(
                VeDeploymentParams({
                    admin: params.admin, token: address(deployment.token), osxDeployment: deployment.osxDeployment
                })
            );
        } else {
            deployment.veDeployment = params.veDeployment;
        }

        deployment.dao = deployment.veDeployment.dao;
        deployment.votingEscrow = VotingEscrow(address(deployment.veDeployment.pluginSet.votingEscrow));
        deployment.exitQueue = ExitQueue(address(deployment.veDeployment.pluginSet.exitQueue));
    }

    /**
     * @dev Deploys factories and registers strategies/encoders
     */
    function _deployFactoriesAndRegisterStrategiesAndEncoders() internal {
        // Deploy factories
        deployment.strategyFactory = new AllocatorStrategyFactory();
        deployment.encoderFactory = new ActionEncoderFactory();

        // Deploy and register merkle strategy
        deployment.merkleStrategy = new MerkleDistributorStrategy();
        deployment.strategyFactory
            .registerStrategyType(MERKLE_STRATEGY_ID, address(deployment.merkleStrategy), "", address(0), 0);

        // Deploy and register voting escrow encoder
        deployment.votingEscrowEncoder = new VotingEscrowLockPayoutActionEncoder();
        deployment.encoderFactory
            .registerActionEncoder(VOTING_ESCROW_ENCODER_ID, address(deployment.votingEscrowEncoder), "");
    }

    /**
     * @dev Creates plugin repo and installs the Capital Distributor Plugin via PSP
     */
    function _installPlugin(address admin) internal {
        ProtocolFactory.Deployment memory osxDeploy = deployment.osxDeployment;

        // Create PluginRepo
        PluginRepo capitalDistributorRepo = PluginRepoFactory(osxDeploy.pluginRepoFactory)
            .createPluginRepoWithFirstVersion(
                "capital-distributor",
                address(new CapitalDistributorPluginSetup()),
                admin,
                bytes("ipfs://release-metadata"),
                bytes("ipfs://build-metadata")
            );

        // Prepare installation
        PluginSetupProcessor psp = PluginSetupProcessor(osxDeploy.pluginSetupProcessor);
        PluginSetupRef memory pluginSetupRef = PluginSetupRef({
            versionTag: PluginRepo.Tag({ release: 1, build: 1 }), pluginSetupRepo: capitalDistributorRepo
        });

        bytes memory installParams = abi.encode(address(deployment.strategyFactory), address(deployment.encoderFactory));

        (address pluginAddr, IPluginSetup.PreparedSetupData memory preparedSetupData) = psp.prepareInstallation(
            address(deployment.dao),
            PluginSetupProcessor.PrepareInstallationParams({ pluginSetupRef: pluginSetupRef, data: installParams })
        );

        deployment.capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddr);
        deployment.condition = ExecuteSelectorCondition(address(preparedSetupData.helpers[0]));

        // Grant permissions and apply installation
        vm.startPrank(address(deployment.dao));
        deployment.dao.grant(address(deployment.dao), address(psp), deployment.dao.ROOT_PERMISSION_ID());
        deployment.dao.grant(address(psp), address(this), psp.APPLY_INSTALLATION_PERMISSION_ID());
        vm.stopPrank();

        psp.applyInstallation(
            address(deployment.dao),
            PluginSetupProcessor.ApplyInstallationParams({
                pluginSetupRef: pluginSetupRef,
                plugin: address(deployment.capitalDistributorPlugin),
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            })
        );
    }

    /**
     * @dev Revokes temporary permissions and configures the condition
     */
    function _finalizeAndConfigureCondition(CapitalDistributorDeploymentParams memory params) internal {
        PluginSetupProcessor psp = PluginSetupProcessor(deployment.osxDeployment.pluginSetupProcessor);

        vm.startPrank(address(deployment.dao));
        deployment.dao.revoke(address(deployment.dao), address(psp), deployment.dao.ROOT_PERMISSION_ID());
        deployment.dao.revoke(address(psp), address(this), psp.APPLY_INSTALLATION_PERMISSION_ID());

        // Resolve action targets and selectors
        address targetOne = params.encoderActionTargetAddressOne;
        bytes4 selectorOne = params.encoderActionTargetSelectorOne;
        address targetTwo = params.encoderActionTargetAddressTwo;
        bytes4 selectorTwo = params.encoderActionTargetSelectorTwo;

        if (targetOne == address(0)) {
            targetOne = address(deployment.token);
            selectorOne = IERC20.approve.selector;
        } else if (selectorOne == bytes4(0)) {
            revert InvalidEncoderActionTargetOneActionSelectorCombo();
        }

        if (targetTwo == address(0)) {
            targetTwo = address(deployment.votingEscrow);
            selectorTwo = bytes4(keccak256("createLockFor(uint256,address)"));
        } else if (selectorTwo == bytes4(0)) {
            revert InvalidEncoderActionTargetTwoActionSelectorCombo();
        }

        // Configure condition
        _configureConditionForVE(deployment.condition, targetOne, targetTwo, selectorOne, selectorTwo);

        vm.stopPrank();
    }

    /**
     * @dev Configures the ExecuteSelectorCondition to allow token approve and VE createLockFor
     * @param condition The condition contract to configure
     * @param encoderActionTargetAddressOne The address to allow the first action on
     * @param encoderActionTargetAddressTwo The address to allow the second action on
     * @param encoderActionTargetSelectorOne The selector to allow the first action on
     * @param encoderActionTargetSelectorTwo The selector to allow the second action on
     */
    function _configureConditionForVE(
        ExecuteSelectorCondition condition,
        address encoderActionTargetAddressOne,
        address encoderActionTargetAddressTwo,
        bytes4 encoderActionTargetSelectorOne,
        bytes4 encoderActionTargetSelectorTwo
    )
        internal
    {
        // Allow target one selector
        ExecuteSelectorCondition.SelectorTarget memory targetOne = ExecuteSelectorCondition.SelectorTarget({
            where: encoderActionTargetAddressOne, selectors: new bytes4[](1)
        });
        targetOne.selectors[0] = encoderActionTargetSelectorOne;
        condition.allowSelectors(targetOne);

        // Allow target two selector
        ExecuteSelectorCondition.SelectorTarget memory targetTwo = ExecuteSelectorCondition.SelectorTarget({
            where: encoderActionTargetAddressTwo, selectors: new bytes4[](1)
        });
        targetTwo.selectors[0] = encoderActionTargetSelectorTwo;
        condition.allowSelectors(targetTwo);
    }

    /**
     * @dev Returns the stored deployment from the last deploy() call
     * @notice Retrieves deployment details without re-deploying
     * @return Struct containing all deployed contract addresses
     *
     * Should be called by: Any contract needing deployment references
     * Prerequisites: deploy() must have been called successfully
     * Caveats: Returns empty struct if deploy() hasn't been called
     */
    function getDeployment() external view returns (CapitalDistributorDeployment memory) {
        return deployment;
    }
}
