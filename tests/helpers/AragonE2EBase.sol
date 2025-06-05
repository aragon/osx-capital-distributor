// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import {CapitalDistributorPlugin} from "../../src/CapitalDistributorPlugin.sol";
import {CapitalDistributorPluginSetup} from "../../src/CapitalDistributorPluginSetup.sol";
import {AllocatorStrategyFactory} from "../../src/AllocatorStrategyFactory.sol";
import {ActionEncoderFactory} from "../../src/ActionEncoderFactory.sol";

/// @title AragonE2EBase
/// @notice Base contract for end-to-end tests of the Capital Distributor Plugin
/// @dev Provides common setup and utility functions for E2E tests across different chains
abstract contract AragonE2EBase is Test {
    // =============================================================================
    // Test Actors
    // =============================================================================

    address immutable alice = makeAddr("alice");
    address immutable bob = makeAddr("bob");
    address immutable carol = makeAddr("carol");
    address immutable david = makeAddr("david");
    address immutable daoOwner = makeAddr("daoOwner");

    // =============================================================================
    // Fork Configuration
    // =============================================================================

    uint256 internal fork;

    // =============================================================================
    // Protocol Contracts
    // =============================================================================

    CapitalDistributorPlugin public capitalDistributorPlugin;
    AllocatorStrategyFactory public allocatorStrategyFactory;
    ActionEncoderFactory public actionEncoderFactory;
    DAO public dao;

    // =============================================================================
    // OSx Framework Contracts
    // =============================================================================

    PluginRepoFactory internal pluginRepoFactory;
    DAOFactory internal daoFactory;

    // =============================================================================
    // Chain-Specific Configuration
    // =============================================================================

    struct ChainConfig {
        string rpcUrl;
        address pluginRepoFactory;
        address daoFactory;
    }

    // =============================================================================
    // Setup Functions
    // =============================================================================

    function setUp() public virtual {
        // Create and select fork
        string memory rpcUrl = getRpcUrl();
        require(bytes(rpcUrl).length > 0, "RPC URL must be provided");

        fork = vm.createFork(rpcUrl);
        vm.selectFork(fork);

        // Set chain-specific addresses
        setChainSpecificAddresses();

        // Deploy protocol contracts
        deployProtocolContracts();

        // Register strategies and encoders
        registerStrategiesAndEncoders();

        // Setup test-specific data (implemented by inheriting contracts)
        setupTestData();

        // Fund DAO if needed (implemented by inheriting contracts)
        fundDAO();
    }

    // =============================================================================
    // Abstract Functions (must be implemented by inheriting contracts)
    // =============================================================================

    /// @notice Get the RPC URL for the chain being tested
    /// @dev Should return the environment variable or hardcoded URL for the target chain
    /// @return rpcUrl The RPC URL string
    function getRpcUrl() internal virtual returns (string memory rpcUrl);

    /// @notice Set chain-specific contract addresses
    /// @dev Should set pluginRepoFactory and daoFactory addresses for the target chain
    function setChainSpecificAddresses() internal virtual;

    /// @notice Setup test-specific data
    /// @dev Implement test-specific setup like merkle trees, recipients, strategies, etc.
    function setupTestData() internal virtual;

    /// @notice Fund the DAO with necessary tokens
    /// @dev Implement DAO funding logic specific to the test scenario
    function fundDAO() internal virtual;

    /// @notice Register strategies and action encoders
    /// @dev Implement registration of strategies and encoders specific to the test
    function registerStrategiesAndEncoders() internal virtual;

    // =============================================================================
    // Common Deployment Logic
    // =============================================================================

    /// @notice Deploy the core protocol contracts
    /// @dev Deploys the plugin setup, creates plugin repo, and sets up the DAO
    function deployProtocolContracts() internal virtual {
        require(address(pluginRepoFactory) != address(0), "PluginRepoFactory address not set");
        require(address(daoFactory) != address(0), "DAOFactory address not set");

        vm.startPrank(daoOwner);

        // Deploy factories
        allocatorStrategyFactory = new AllocatorStrategyFactory();
        actionEncoderFactory = new ActionEncoderFactory();

        // Deploy plugin setup
        CapitalDistributorPluginSetup pluginSetup = new CapitalDistributorPluginSetup();

        // Create plugin repository
        PluginRepo pluginRepo = pluginRepoFactory.createPluginRepoWithFirstVersion(
            getPluginRepoName(),
            address(pluginSetup),
            msg.sender,
            "0x00",
            "0x00"
        );

        // Configure DAO settings
        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings(address(0), "", getDAOName(), "");

        // Configure plugin settings
        bytes memory pluginSettingsData = abi.encode(allocatorStrategyFactory, actionEncoderFactory);
        PluginRepo.Tag memory tag = PluginRepo.Tag(1, 1);
        DAOFactory.PluginSettings[] memory pluginSettings = new DAOFactory.PluginSettings[](1);
        pluginSettings[0] = DAOFactory.PluginSettings(PluginSetupRef(tag, pluginRepo), pluginSettingsData);

        // Deploy DAO
        (DAO createdDAO, DAOFactory.InstalledPlugin[] memory pluginAddresses) = daoFactory.createDao(
            daoSettings,
            pluginSettings
        );

        dao = createdDAO;
        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddresses[0].plugin);

        vm.stopPrank();
    }

    // =============================================================================
    // Virtual Functions (can be overridden by inheriting contracts)
    // =============================================================================

    /// @notice Get the name for the plugin repository
    /// @dev Can be overridden to customize the plugin repo name
    /// @return name The plugin repository name
    function getPluginRepoName() internal virtual returns (string memory name) {
        return "capital-distributor-e2e-test";
    }

    /// @notice Get the name for the DAO
    /// @dev Can be overridden to customize the DAO name
    /// @return name The DAO name
    function getDAOName() internal virtual returns (string memory name) {
        return "capital-distributor-e2e-dao";
    }

    // =============================================================================
    // Utility Functions
    // =============================================================================

    /// @notice Convert string to bytes32
    /// @param source The string to convert
    /// @return result The bytes32 representation
    function toBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        require(temp.length <= 32, "String too long");

        assembly ("memory-safe") {
            result := mload(add(temp, 32))
        }
    }

    /// @notice Hash two bytes32 values in sorted order (for merkle tree construction)
    /// @param a First hash
    /// @param b Second hash
    /// @return The combined hash
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /// @notice Deal tokens to an address using forge's deal function
    /// @param token The token address
    /// @param to The recipient address
    /// @param amount The amount to deal
    function dealTokens(address token, address to, uint256 amount) internal {
        deal(token, to, amount);
    }

    /// @notice Get current fork ID
    /// @return The current fork ID
    function getCurrentFork() internal view returns (uint256) {
        return fork;
    }

    // =============================================================================
    // Common Assertions
    // =============================================================================

    /// @notice Assert that all protocol contracts are properly deployed
    function assertProtocolDeployed() internal view {
        assertTrue(address(capitalDistributorPlugin) != address(0), "Plugin should be deployed");
        assertTrue(address(allocatorStrategyFactory) != address(0), "Strategy factory should be deployed");
        assertTrue(address(actionEncoderFactory) != address(0), "Action encoder factory should be deployed");
        assertTrue(address(dao) != address(0), "DAO should be deployed");
    }

    /// @notice Assert that a campaign exists with expected properties
    /// @param campaignId The campaign ID to check
    /// @param expectedToken The expected token address
    function assertCampaignExists(uint256 campaignId, address expectedToken) internal view {
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(address(campaign.allocationStrategy) != address(0), "Campaign should have allocation strategy");
        assertEq(address(campaign.token), expectedToken, "Campaign should use expected token");
    }

    /// @notice Assert that an address has expected token balance
    /// @param token The token address
    /// @param account The account to check
    /// @param expectedBalance The expected balance
    /// @param message Custom assertion message
    function assertTokenBalance(
        address token,
        address account,
        uint256 expectedBalance,
        string memory message
    ) internal view {
        assertEq(IERC20(token).balanceOf(account), expectedBalance, message);
    }

    // =============================================================================
    // Common Chain Configurations
    // =============================================================================

    /// @notice Get mainnet chain configuration
    /// @return config The mainnet configuration
    function getMainnetConfig() internal pure returns (ChainConfig memory config) {
        return
            ChainConfig({
                rpcUrl: "MAINNET_RPC_URL",
                pluginRepoFactory: 0xcf59C627b7a4052041C4F16B4c635a960e29554A,
                daoFactory: 0x246503df057A9a85E0144b6867a828c99676128B
            });
    }

    /// @notice Get Polygon chain configuration
    /// @return config The Polygon configuration
    function getPolygonConfig() internal pure returns (ChainConfig memory config) {
        return
            ChainConfig({
                rpcUrl: "POLYGON_RPC_URL",
                pluginRepoFactory: address(0), // Replace with actual Polygon address
                daoFactory: address(0) // Replace with actual Polygon address
            });
    }

    /// @notice Get Arbitrum chain configuration
    /// @return config The Arbitrum configuration
    function getArbitrumConfig() internal pure returns (ChainConfig memory config) {
        return
            ChainConfig({
                rpcUrl: "ARBITRUM_RPC_URL",
                pluginRepoFactory: address(0), // Replace with actual Arbitrum address
                daoFactory: address(0) // Replace with actual Arbitrum address
            });
    }

    // =============================================================================
    // Helper Functions for Common Test Patterns
    // =============================================================================

    /// @notice Create a simple merkle tree from recipients and amounts
    /// @param recipients Array of recipient addresses
    /// @param amounts Array of corresponding amounts
    /// @return merkleRoot The computed merkle root
    /// @return leaves Array of leaf hashes
    function createSimpleMerkleTree(
        address[] memory recipients,
        uint256[] memory amounts
    ) internal pure returns (bytes32 merkleRoot, bytes32[] memory leaves) {
        require(recipients.length == amounts.length, "Recipients and amounts length mismatch");
        require(recipients.length > 0, "No recipients provided");

        leaves = new bytes32[](recipients.length);

        // Create leaves
        for (uint256 i = 0; i < recipients.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(recipients[i], amounts[i]));
        }

        // For simplicity, this creates a basic merkle root for small trees
        // In production, use a proper merkle tree library
        if (recipients.length == 1) {
            merkleRoot = leaves[0];
        } else if (recipients.length == 2) {
            merkleRoot = _hashPair(leaves[0], leaves[1]);
        } else if (recipients.length <= 4) {
            bytes32 level1_0 = recipients.length > 1 ? _hashPair(leaves[0], leaves[1]) : leaves[0];
            bytes32 level1_1 = recipients.length > 3 ? _hashPair(leaves[2], leaves[3]) : leaves[2];
            merkleRoot = _hashPair(level1_0, level1_1);
        } else {
            revert("SimpleMerkleTree only supports up to 4 recipients");
        }
    }

    /// @notice Generate merkle proof for a recipient in a simple 4-person tree
    /// @param leaves The array of leaf hashes
    /// @param index The index of the recipient (0-3)
    /// @return proof The merkle proof
    function getSimpleMerkleProof(
        bytes32[] memory leaves,
        uint256 index
    ) internal pure returns (bytes32[] memory proof) {
        require(leaves.length <= 4, "SimpleMerkleProof only supports up to 4 recipients");
        require(index < leaves.length, "Index out of bounds");

        if (leaves.length <= 2) {
            proof = new bytes32[](1);
            proof[0] = leaves[index == 0 ? 1 : 0];
        } else {
            proof = new bytes32[](2);
            if (index == 0) {
                proof[0] = leaves[1];
                proof[1] = _hashPair(leaves[2], leaves[3]);
            } else if (index == 1) {
                proof[0] = leaves[0];
                proof[1] = _hashPair(leaves[2], leaves[3]);
            } else if (index == 2) {
                proof[0] = leaves[3];
                proof[1] = _hashPair(leaves[0], leaves[1]);
            } else {
                proof[0] = leaves[2];
                proof[1] = _hashPair(leaves[0], leaves[1]);
            }
        }
    }
}
