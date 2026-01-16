// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ProtocolFactoryBuilder } from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";
import { ProtocolFactory } from "@aragon/protocol-factory/src/ProtocolFactory.sol";
import {
    GaugesDaoFactoryV1_4_0 as VeGovernanceFactory,
    Deployment as VeFactoryDeployment,
    DeploymentParameters,
    TokenParameters,
    GaugePluginSet
} from "@ve/factory/GaugesDaoFactory_v1_4_0.sol";
import { PluginRepoFactory } from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import { PluginSetupProcessor } from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import { PluginRepo } from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { Multisig } from "@aragon/multisig-plugin/Multisig.sol";

import { GaugeVoterSetupV1_4_0 as GaugeVoterSetup } from "@ve/setup/GaugeVoterSetup_v1_4_0.sol";
import { AddressGaugeVoter as GaugeVoter } from "@ve/voting/AddressGaugeVoter.sol";

import { LinearIncreasingCurve as Curve } from "@ve/curve/LinearIncreasingCurve.sol";
import { DynamicExitQueue as ExitQueue } from "@ve/queue/DynamicExitQueue.sol";
import { VotingEscrowV1_2_0 as VotingEscrow } from "@ve/escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { ClockV1_2_0 as Clock } from "@ve/clock/Clock_v1_2_0.sol";
import { LockV1_2_0 as Lock } from "@ve/lock/Lock_v1_2_0.sol";
import { EscrowIVotesAdapter } from "@ve/delegation/EscrowIVotesAdapter.sol";

/// @notice Struct containing the VE deployment results
struct VeDeployment {
    DAO dao;
    GaugePluginSet pluginSet;
    Multisig multisig;
    ProtocolFactory.Deployment osxDeployment;
}

/// @notice Parameters needed to deploy the VE governance system
struct VeDeploymentParams {
    address admin;
    address token;
    ProtocolFactory.Deployment osxDeployment;
}

/// @title SetupVe
/// @notice Helper contract to deploy the ve-governance system locally in Foundry tests
/// @dev This mimics the production deployment flow but runs entirely in a local test environment
contract SetupVe {
    VeDeployment private deployment;

    /**
     * @dev Deploys a complete VE governance system including DAO, voting escrow, and gauge voter
     * @notice This function deploys the entire VE infrastructure in one transaction
     * @param params Deployment parameters including admin address, token, and OSx deployment
     * @return deployment Struct containing all deployed contracts and references
     *
     * Order of operations:
     * 1. Sets up VE factory deployment parameters
     * 2. Creates DAO with multisig plugin
     * 3. Deploys gauge voter plugin with voting escrow
     * 4. Extracts and stores deployment references
     *
     * Should be called by: Test setup or deployment scripts
     * Prerequisites: OSx infrastructure must be deployed, token must exist
     * Side effects: Stores deployment internally for later retrieval via getDeployment()
     */
    function deploy(VeDeploymentParams memory params) external returns (VeDeployment memory) {
        address[] memory multisigMembers = new address[](2);
        multisigMembers[0] = msg.sender;
        multisigMembers[1] = params.admin;

        TokenParameters[] memory tokenParameters = new TokenParameters[](1);
        tokenParameters[0] =
            TokenParameters({ token: params.token, veTokenName: "Vote Escrowed Token", veTokenSymbol: "veTOKEN" });

        // flat curve (constant voting power)
        int256[3] memory coefficients;
        coefficients[0] = 1e18;
        coefficients[1] = 0;
        coefficients[2] = 0;

        address gaugeVoterPluginSetup = address(
            new GaugeVoterSetup(
                address(new GaugeVoter()),
                address(new Curve(coefficients, 0)),
                address(new ExitQueue()),
                address(new VotingEscrow()),
                address(new Clock()),
                address(new Lock()),
                address(new EscrowIVotesAdapter(coefficients, 0))
            )
        );

        DeploymentParameters memory parameters = DeploymentParameters({
            daoExecutor: address(0),
            daoMetadataURI: "ipfs://ve-test-dao",
            daoSubdomain: "",
            minApprovals: 1,
            multisigMembers: multisigMembers,
            multisigMetadata: "ipfs://multisig-metadata",
            tokenParameters: tokenParameters,
            feePercent: 100, // 1% exit fee (100 basis points in 10000 scale)
            cooldownPeriod: 1 days,
            minLockDuration: 1, // Minimum 1 second lock duration (cannot be 0)
            votingPaused: false,
            minDeposit: 1, // Minimum 1 wei deposit
            multisigPluginRepo: PluginRepo(params.osxDeployment.multisigPluginRepo),
            multisigPluginRelease: 1,
            multisigPluginBuild: 3, // Must match ProtocolFactoryBuilder's multisig build number
            voterPluginSetup: GaugeVoterSetup(gaugeVoterPluginSetup),
            voterEnsSubdomain: "ve-voter-test",
            osxDaoFactory: params.osxDeployment.daoFactory,
            pluginSetupProcessor: PluginSetupProcessor(params.osxDeployment.pluginSetupProcessor),
            pluginRepoFactory: PluginRepoFactory(params.osxDeployment.pluginRepoFactory)
        });

        VeGovernanceFactory veGovFactory = new VeGovernanceFactory(parameters);
        veGovFactory.deployOnce();

        VeFactoryDeployment memory factoryDeployment = veGovFactory.getDeployment();

        deployment.dao = factoryDeployment.dao;
        deployment.pluginSet = factoryDeployment.gaugeVoterPluginSets[0];
        deployment.multisig = Multisig(address(factoryDeployment.multisigPlugin));
        deployment.osxDeployment = params.osxDeployment;

        return deployment;
    }

    /**
     * @dev Returns the stored VE deployment from the last deploy() call
     * @notice Retrieves deployment details without re-deploying
     * @return deployment Struct containing all deployed contract addresses
     *
     * Should be called by: Any contract needing VE deployment references
     * Prerequisites: deploy() must have been called successfully
     * Caveats: Returns empty struct if deploy() hasn't been called
     */
    function getDeployment() external view returns (VeDeployment memory) {
        return deployment;
    }
}
