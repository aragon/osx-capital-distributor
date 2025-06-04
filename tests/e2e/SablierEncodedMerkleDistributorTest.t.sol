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
import {MerkleDistributorStrategy} from "../../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import {IAllocatorStrategyFactory} from "../../src/interfaces/IAllocatorStrategyFactory.sol";
import {IPayoutActionEncoder} from "../../src/interfaces/IPayoutActionEncoder.sol";
import {ISablierLockup, SablierLinearPayoutActionEncoder} from "../../src/payoutActionEncoders/SablierLinearPayoutActionEncoder.sol";

/// @title SablierEncodedMerkleDistributorTest
/// @notice E2E test for Merkle distributor with Sablier stream encoding on mainnet fork
/// @dev This test forks mainnet to test real Sablier protocol integration
contract SablierEncodedMerkleDistributorTest is Test {
    // Mainnet addresses
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Replace with actual USDC address
    address constant SABLIER_V2_LOCKUP_LINEAR = 0x3F6E8a8Cffe377c4649aCeB01e6F20c60fAA356c; // Replace with actual Sablier address
    address constant SABLIER_V2_LOCKUP = 0x7C01AA3783577E15fD7e272443D44B92d5b21056; // Replace with actual Sablier address

    // Test actors
    address immutable alice = makeAddr("alice");
    address immutable bob = makeAddr("bob");
    address immutable carol = makeAddr("carol");
    address immutable david = makeAddr("david");
    address immutable daoOwner = makeAddr("daoOwner");

    // OSx contracts
    PluginRepoFactory pluginRepoFactory = PluginRepoFactory(0xcf59C627b7a4052041C4F16B4c635a960e29554A);
    DAOFactory daoFactory = DAOFactory(0x246503df057A9a85E0144b6867a828c99676128B);
    address[] pluginAddress;

    // Protocol contracts
    CapitalDistributorPlugin public capitalDistributorPlugin;
    AllocatorStrategyFactory public allocatorStrategyFactory;
    ActionEncoderFactory public actionEncoderFactory;
    MerkleDistributorStrategy public merkleStrategy;
    DAO public dao;
    IERC20 public usdc;
    MerkleDistributorStrategy strategy;
    uint256 campaignId;

    // Test data
    uint256 constant TOTAL_DISTRIBUTION_AMOUNT = 10_000e6; // 10,000 USDC
    bytes32 merkleRoot;
    mapping(address => uint256) recipientAmounts;
    mapping(address => bytes32[]) recipientProofs;

    // Fork configuration
    uint256 mainnetFork;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        // Create and select mainnet fork
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        // Initialize mainnet contracts
        usdc = IERC20(USDC_MAINNET);

        // Deploy our protocol contracts
        deployProtocolContracts();

        // Setup test data
        setupTestRecipients();
        setupMerkleTree();

        // Fund the DAO with USDC
        fundDAO();

        // Setup campaign
        setupDistributionCampaign();
    }

    function deployProtocolContracts() internal {
        vm.startPrank(daoOwner);
        allocatorStrategyFactory = new AllocatorStrategyFactory();
        actionEncoderFactory = new ActionEncoderFactory();
        strategy = new MerkleDistributorStrategy();
        allocatorStrategyFactory.registerStrategyType(toBytes32("merkle-strategy"), address(strategy), "");

        CapitalDistributorPluginSetup pluginSetup = new CapitalDistributorPluginSetup();
        PluginRepo pluginRepo = pluginRepoFactory.createPluginRepoWithFirstVersion(
            "capital-distributor-test",
            address(pluginSetup),
            msg.sender,
            "0x00",
            "0x00"
        );

        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings(
            address(0),
            "",
            "capital-distributor-test",
            ""
        );

        // Plugin settings
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

        SablierLinearPayoutActionEncoder sablierLinearPayoutActionEncoder = new SablierLinearPayoutActionEncoder();
        actionEncoderFactory.registerActionEncoder(
            toBytes32("sablier-linear-encoder"),
            address(sablierLinearPayoutActionEncoder),
            ""
        );
    }

    function setupTestRecipients() internal {
        recipientAmounts[alice] = 2_500e6; // 2,500 USDC
        recipientAmounts[bob] = 3_000e6; // 3,000 USDC
        recipientAmounts[carol] = 2_000e6; // 2,000 USDC
        recipientAmounts[david] = 2_500e6; // 2,500 USDC
    }

    function setupMerkleTree() internal {
        // In a real implementation, this would use a proper merkle tree library
        // For now, we'll create a simplified version

        address[] memory recipients = new address[](4);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;
        recipients[3] = david;

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = recipientAmounts[alice];
        amounts[1] = recipientAmounts[bob];
        amounts[2] = recipientAmounts[carol];
        amounts[3] = recipientAmounts[david];

        // Create leaves
        bytes32[] memory leaves = new bytes32[](4);
        for (uint256 i = 0; i < recipients.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(recipients[i], amounts[i]));
        }

        // Create merkle root (simplified - in practice use a proper merkle tree library)
        bytes32 level1_0 = _hashPair(leaves[0], leaves[1]);
        bytes32 level1_1 = _hashPair(leaves[2], leaves[3]);
        merkleRoot = _hashPair(level1_0, level1_1);

        // Generate proofs for each recipient
        recipientProofs[alice] = new bytes32[](2);
        recipientProofs[alice][0] = leaves[1]; // Bob's leaf
        recipientProofs[alice][1] = level1_1; // Carol + David branch

        recipientProofs[bob] = new bytes32[](2);
        recipientProofs[bob][0] = leaves[0]; // Alice's leaf
        recipientProofs[bob][1] = level1_1; // Carol + David branch

        recipientProofs[carol] = new bytes32[](2);
        recipientProofs[carol][0] = leaves[3]; // David's leaf
        recipientProofs[carol][1] = level1_0; // Alice + Bob branch

        recipientProofs[david] = new bytes32[](2);
        recipientProofs[david][0] = leaves[2]; // Carol's leaf
        recipientProofs[david][1] = level1_0; // Alice + Bob branch
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function fundDAO() internal {
        deal(address(usdc), address(dao), TOTAL_DISTRIBUTION_AMOUNT);

        assertEq(usdc.balanceOf(address(dao)), TOTAL_DISTRIBUTION_AMOUNT, "DAO should be funded with USDC");
    }

    function setupDistributionCampaign() internal {
        vm.startPrank(address(dao));

        // Deployment parameters for merkle strategy
        IAllocatorStrategyFactory.DeploymentParams memory deploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({dao: IDAO(address(dao)), epochDuration: 30 days, claimOpen: true, auxData: ""});

        // Create campaign with Sablier encoder
        campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://QmTestCampaignMetadata", // metadataURI
            toBytes32("merkle-strategy"), // strategyId
            deploymentParams,
            abi.encode(merkleRoot), // allocationStrategyAuxData
            address(0), // vault (not used for this test)
            usdc, // token
            toBytes32("sablier-linear-encoder"), // defaultActionEncoderId
            abi.encode(
                SABLIER_V2_LOCKUP_LINEAR, // sablier contract
                1 weeks, // stream duration
                0, // no cliff
                0, // No immediate unlock
                0, // No cliff unlock
                true, // Cancelable
                false, // Transferable
                address(0), // No broker
                0
            ) // actionEncoderInitializationAuxData
        );

        vm.stopPrank();
    }

    // =============================================================================
    // Test Functions
    // =============================================================================

    function test_SetupIsCorrect() public view {
        // Verify contracts are deployed
        assertTrue(address(capitalDistributorPlugin) != address(0), "Plugin should be deployed");
        assertTrue(address(allocatorStrategyFactory) != address(0), "Strategy factory should be deployed");
        assertTrue(address(actionEncoderFactory) != address(0), "Action encoder factory should be deployed");

        // Verify DAO has funds
        assertEq(usdc.balanceOf(address(dao)), TOTAL_DISTRIBUTION_AMOUNT, "DAO should have USDC");

        // Verify campaign exists
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(address(campaign.allocationStrategy) != address(0), "Campaign should have allocation strategy");
        assertEq(address(campaign.token), address(usdc), "Campaign should use USDC");
    }

    function test_CanCalculateCorrectPayouts() public {
        // Test Alice's payout calculation
        bytes memory claimData = abi.encode(recipientProofs[alice], recipientAmounts[alice]);
        uint256 alicePayout = capitalDistributorPlugin.getCampaignPayout(campaignId, alice, claimData);
        assertEq(alicePayout, recipientAmounts[alice], "Alice's payout should match expected amount");

        // Test Bob's payout calculation
        claimData = abi.encode(recipientProofs[bob], recipientAmounts[bob]);
        uint256 bobPayout = capitalDistributorPlugin.getCampaignPayout(campaignId, bob, claimData);
        assertEq(bobPayout, recipientAmounts[bob], "Bob's payout should match expected amount");
    }

    function test_RejectsInvalidProofs() public view {
        // Try to claim with Bob's proof for Alice
        bytes memory invalidClaimData = abi.encode(recipientProofs[bob], recipientAmounts[alice]);
        uint256 payout = capitalDistributorPlugin.getCampaignPayout(campaignId, alice, invalidClaimData);
        assertEq(payout, 0, "Invalid proof should result in zero payout");
    }

    function test_SuccessfulClaim_CreatesActions() public {
        // This test would verify that claiming creates the correct Sablier stream actions
        // Implementation depends on the Sablier action encoder being implemented

        bytes memory claimData = abi.encode(recipientProofs[alice], recipientAmounts[alice]);

        // Record initial balances
        uint256 initialDAOBalance = usdc.balanceOf(address(dao));
        uint256 initialAliceBalance = usdc.balanceOf(alice);

        // Claim payout (this should create Sablier stream instead of direct transfer)
        vm.startPrank(address(alice));
        ISablierLockup sablierLockup = ISablierLockup(SABLIER_V2_LOCKUP);
        uint256 streamId = sablierLockup.nextStreamId();
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, claimData);

        // Verify DAO balance decreased
        assertLt(usdc.balanceOf(address(dao)), initialDAOBalance, "DAO balance should decrease");
        assertEq(usdc.balanceOf(address(alice)), 0, "Alice balance should increase");

        // Note: With Sablier streams, Alice might not immediately receive tokens
        // The actual verification would depend on Sablier contract state
        vm.warp(block.timestamp + 1.1 weeks);
        sablierLockup.withdrawMax(streamId, address(alice));
        assertEq(usdc.balanceOf(address(alice)), 2500e6, "Alice balance should increase");

        vm.stopPrank();
    }

    function test_MultipleClaimsWork() public {
        vm.startPrank(address(dao));

        // Alice claims
        bytes memory aliceClaimData = abi.encode(recipientProofs[alice], recipientAmounts[alice]);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, aliceClaimData);

        // Bob claims
        bytes memory bobClaimData = abi.encode(recipientProofs[bob], recipientAmounts[bob]);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, bob, bobClaimData);

        vm.stopPrank();

        // Verify both have claimed
        assertGt(capitalDistributorPlugin.getClaimedAmount(campaignId, alice), 0, "Alice should have claimed");
        assertGt(capitalDistributorPlugin.getClaimedAmount(campaignId, bob), 0, "Bob should have claimed");
    }

    function test_CannotClaimTwice() public {
        vm.startPrank(address(dao));

        // Alice claims successfully
        bytes memory claimData = abi.encode(recipientProofs[alice], recipientAmounts[alice]);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, claimData);

        // Alice tries to claim again
        vm.expectRevert(CapitalDistributorPlugin.NoPayoutToClaim.selector);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, claimData);

        vm.stopPrank();
    }

    function test_GasUsage() public {
        bytes memory claimData = abi.encode(recipientProofs[alice], recipientAmounts[alice]);

        vm.startPrank(address(dao));

        uint256 gasBefore = gasleft();
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, claimData);
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        // Assert reasonable gas usage (adjust based on actual implementation)
        assertTrue(gasUsed < 500_000, "Claim should use reasonable amount of gas");
    }

    function toBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        require(temp.length <= 32, "String too long");

        assembly ("memory-safe") {
            result := mload(add(temp, 32))
        }
    }
}
