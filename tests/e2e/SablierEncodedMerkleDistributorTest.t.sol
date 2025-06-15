// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";

import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {CapitalDistributorPlugin} from "../../src/CapitalDistributorPlugin.sol";

import {AragonE2EBase} from "../helpers/AragonE2EBase.sol";
import {MerkleDistributorStrategy} from "../../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import {IAllocatorStrategyFactory} from "../../src/interfaces/IAllocatorStrategyFactory.sol";
import {IPayoutActionEncoder} from "../../src/interfaces/IPayoutActionEncoder.sol";
import {ISablierLockup, SablierLinearPayoutActionEncoder} from "../../src/payoutActionEncoders/SablierLinearPayoutActionEncoder.sol";

/// @title SablierEncodedMerkleDistributorTest
/// @notice E2E test for Merkle distributor with Sablier stream encoding on mainnet fork
/// @dev This test forks mainnet to test real Sablier protocol integration
contract SablierEncodedMerkleDistributorTest is AragonE2EBase {
    // Mainnet addresses
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Replace with actual USDC address
    address constant SABLIER_V2_LOCKUP_LINEAR = 0x3F6E8a8Cffe377c4649aCeB01e6F20c60fAA356c; // Replace with actual Sablier address
    address constant SABLIER_V2_LOCKUP = 0x7C01AA3783577E15fD7e272443D44B92d5b21056; // Replace with actual Sablier address

    // Test-specific contracts
    MerkleDistributorStrategy public merkleStrategy;
    IERC20 public usdc;
    MerkleDistributorStrategy strategy;
    uint256 campaignId;

    // Test data
    uint256 constant TOTAL_DISTRIBUTION_AMOUNT = 10_000e6; // 10,000 USDC
    bytes32 merkleRoot;
    mapping(address => uint256) recipientAmounts;
    mapping(address => bytes32[]) recipientProofs;

    // =============================================================================
    // Abstract Function Implementations
    // =============================================================================

    function getRpcUrl() internal override returns (string memory) {
        return vm.envString("MAINNET_RPC_URL");
    }

    function setChainSpecificAddresses() internal override {
        ChainConfig memory config = getMainnetConfig();
        pluginRepoFactory = PluginRepoFactory(config.pluginRepoFactory);
        daoFactory = DAOFactory(config.daoFactory);
    }

    function registerStrategiesAndEncoders() internal override {
        vm.startPrank(daoOwner);

        // Register merkle strategy
        strategy = new MerkleDistributorStrategy();
        allocatorStrategyFactory.registerStrategyType(toBytes32("merkle-strategy"), address(strategy), "");

        // Register Sablier action encoder
        SablierLinearPayoutActionEncoder sablierLinearPayoutActionEncoder = new SablierLinearPayoutActionEncoder();
        actionEncoderFactory.registerActionEncoder(
            toBytes32("sablier-linear-encoder"),
            address(sablierLinearPayoutActionEncoder),
            ""
        );

        vm.stopPrank();
    }

    function setupTestData() internal override {
        // Initialize USDC contract
        usdc = IERC20(USDC_MAINNET);

        // Setup test recipients
        setupTestRecipients();

        // Setup merkle tree
        setupMerkleTree();

        // Setup distribution campaign
        setupDistributionCampaign();
    }

    function fundDAO() internal override {
        dealTokens(address(usdc), address(dao), TOTAL_DISTRIBUTION_AMOUNT);
        assertTokenBalance(address(usdc), address(dao), TOTAL_DISTRIBUTION_AMOUNT, "DAO should be funded with USDC");
    }

    // =============================================================================
    // Test-Specific Setup Functions
    // =============================================================================

    function setupTestRecipients() internal {
        recipientAmounts[alice] = 2_500e6; // 2,500 USDC
        recipientAmounts[bob] = 3_000e6; // 3,000 USDC
        recipientAmounts[carol] = 2_000e6; // 2,000 USDC
        recipientAmounts[david] = 2_500e6; // 2,500 USDC
    }

    function setupMerkleTree() internal {
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

        // Use the base contract's utility function
        bytes32[] memory leaves;
        (merkleRoot, leaves) = createSimpleMerkleTree(recipients, amounts);

        // Generate proofs for each recipient
        recipientProofs[alice] = getSimpleMerkleProof(leaves, 0);
        recipientProofs[bob] = getSimpleMerkleProof(leaves, 1);
        recipientProofs[carol] = getSimpleMerkleProof(leaves, 2);
        recipientProofs[david] = getSimpleMerkleProof(leaves, 3);
    }

    function setupDistributionCampaign() internal {
        vm.startPrank(address(dao));

        // Deployment parameters for merkle strategy
        IAllocatorStrategyFactory.DeploymentParams memory deploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({auxData: ""});

        // Create campaign with Sablier encoder
        campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://QmTestCampaignMetadata", // metadataURI
            toBytes32("merkle-strategy"), // strategyId
            deploymentParams,
            abi.encode(merkleRoot), // allocationStrategyAuxData
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
            ), // actionEncoderInitializationAuxData
            false,
            0,
            0
        );

        vm.stopPrank();
    }

    // =============================================================================
    // Test Functions
    // =============================================================================

    function test_SetupIsCorrect() public view {
        // Verify contracts are deployed using base assertions
        assertProtocolDeployed();

        // Verify DAO has funds
        assertTokenBalance(address(usdc), address(dao), TOTAL_DISTRIBUTION_AMOUNT, "DAO should have USDC");

        // Verify campaign exists
        assertCampaignExists(campaignId, address(usdc));
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
        assertTokenBalance(address(usdc), alice, 0, "Alice should not have immediate balance with streams");

        // Note: With Sablier streams, Alice might not immediately receive tokens
        // The actual verification would depend on Sablier contract state
        vm.warp(block.timestamp + 1.1 weeks);
        sablierLockup.withdrawMax(streamId, address(alice));
        assertTokenBalance(address(usdc), alice, 2500e6, "Alice should receive tokens after stream withdrawal");

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
        vm.expectRevert(
            abi.encodeWithSelector(CapitalDistributorPlugin.MultipleClaimsNotAllowed.selector, campaignId, alice)
        );
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
}
