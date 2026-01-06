// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

// Capital Distributor imports
import { CapitalDistributorPlugin } from "../../src/CapitalDistributorPlugin.sol";
import { ICapitalDistributorPlugin } from "../../src/interfaces/ICapitalDistributorPlugin.sol";
import { CapitalDistributorPluginSetup } from "../../src/CapitalDistributorPluginSetup.sol";
import { AllocatorStrategyFactory } from "../../src/factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../../src/factories/ActionEncoderFactory.sol";
import { MerkleDistributorStrategy } from "../../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import {
    VotingEscrowLockPayoutActionEncoder
} from "../../src/payoutActionEncoders/VotingEscrowLockPayoutActionEncoder.sol";
import { IPayoutActionEncoder } from "../../src/interfaces/IPayoutActionEncoder.sol";

// VE Governance imports
import { SetupVe, VeDeployment, VeDeploymentParams } from "./SetupVe.sol";
import { VotingEscrowV1_2_0 as VotingEscrow } from "@ve/escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { DynamicExitQueue as ExitQueue } from "@ve/queue/DynamicExitQueue.sol";

// Aragon/OSx imports
import { ProtocolFactoryBuilder } from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";
import { ProtocolFactory } from "@aragon/protocol-factory/src/ProtocolFactory.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { IPluginSetup } from "@aragon/commons/plugin/setup/IPluginSetup.sol";
import { IPermissionCondition } from "@aragon/commons/permission/condition/IPermissionCondition.sol";
import { PermissionLib } from "@aragon/commons/permission/PermissionLib.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";

// OpenZeppelin imports
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Test utilities
import { MintableERC20 } from "../../tests/mocks/MintableERC20.sol";
import { IVotingEscrowIncreasing, IVotingEscrowCore } from "../interfaces/IVotingEscrowIncreasing.sol";

/// @notice Interface for the Dynamic Exit Queue contract
interface IDynamicExitQueue {
    /// @notice Calculate the absolute fee amount for exiting a specific token
    function calculateFee(uint256 _tokenId) external view returns (uint256);
}

/// @title VotingEscrowLockPayoutLocalTest
/// @notice Integration test for the complete flow of DAO creating voting escrow locks
///         for users using a locally deployed ve-governance system (no fork required)
/// @dev Tests the real flow:
///      1. Deploy OSx infrastructure locally
///      2. Deploy ve-governance system locally
///      3. Deploy Capital Distributor Plugin and configure for VE locks
///      4. DAO creates merkle tree internally and creates campaign with merkle root
///      5. Users claim locks, receiving veNFTs representing their locked positions
///      6. After locks expire, users can withdraw their tokens
contract VotingEscrowLockPayoutLocalTest is Test {
    // =============================================================================
    // Test Actors
    // =============================================================================
    address immutable alice = makeAddr("alice");
    address immutable bob = makeAddr("bob");
    address immutable carol = makeAddr("carol");
    address immutable david = makeAddr("david");
    address immutable eve = makeAddr("eve");
    address immutable admin = makeAddr("admin");

    // =============================================================================
    // Protocol Contracts
    // =============================================================================
    DAO internal dao;
    CapitalDistributorPlugin internal capitalDistributorPlugin;
    ExecuteSelectorCondition internal condition;
    AllocatorStrategyFactory internal strategyFactory;
    ActionEncoderFactory internal encoderFactory;
    MerkleDistributorStrategy internal merkleStrategy;
    VotingEscrowLockPayoutActionEncoder internal votingEscrowEncoder;

    // =============================================================================
    // VE Governance Contracts
    // =============================================================================
    VotingEscrow internal votingEscrow;
    ExitQueue internal exitQueue;
    MintableERC20 internal token;

    // =============================================================================
    // Deployment Infrastructure
    // =============================================================================
    ProtocolFactory.Deployment internal osxDeployment;
    VeDeployment internal veDeployment;

    // =============================================================================
    // Merkle Tree Data
    // =============================================================================
    struct Recipient {
        address account;
        uint256 amount;
    }

    Recipient[] internal recipients;
    bytes32 internal merkleRoot;
    mapping(address => bytes32[]) internal merkleProofs;
    mapping(address => uint256) internal claimAmounts;

    /// @dev Set up local deployment of OSx, ve-governance, and Capital Distributor Plugin
    function setUp() public {
        // Deploy underlying token
        token = new MintableERC20();

        // Deploy OSx infrastructure locally
        ProtocolFactory factory = new ProtocolFactoryBuilder().build();
        factory.deployOnce();
        osxDeployment = factory.getDeployment();

        // Deploy ve-governance system locally
        SetupVe setupVe = new SetupVe();
        veDeployment =
            setupVe.deploy(VeDeploymentParams({ admin: admin, token: address(token), osxDeployment: osxDeployment }));

        // Extract the DAO and VE contracts from deployment
        dao = veDeployment.dao;
        votingEscrow = VotingEscrow(address(veDeployment.pluginSet.votingEscrow));
        exitQueue = ExitQueue(address(veDeployment.pluginSet.exitQueue));

        // Deploy Capital Distributor Plugin factories
        strategyFactory = new AllocatorStrategyFactory();
        encoderFactory = new ActionEncoderFactory();

        // Deploy and register merkle strategy
        merkleStrategy = new MerkleDistributorStrategy();
        strategyFactory.registerStrategyType(
            toBytes32("merkle-distributor-strategy"), address(merkleStrategy), "", address(0), 0
        );

        // Deploy and register voting escrow encoder
        votingEscrowEncoder = new VotingEscrowLockPayoutActionEncoder();
        encoderFactory.registerActionEncoder(toBytes32("voting-escrow-lock-encoder"), address(votingEscrowEncoder), "");

        // Deploy Capital Distributor Plugin using setup
        CapitalDistributorPluginSetup setup = new CapitalDistributorPluginSetup();
        bytes memory installParams = abi.encode(address(strategyFactory), address(encoderFactory));

        IPluginSetup.PreparedSetupData memory preparedSetupData;
        address pluginAddr;
        (pluginAddr, preparedSetupData) = setup.prepareInstallation(address(dao), installParams);

        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddr);
        condition = ExecuteSelectorCondition(preparedSetupData.helpers[0]);

        // Apply permissions (simulate PluginSetupProcessor)
        vm.startPrank(address(dao));
        for (uint256 i = 0; i < preparedSetupData.permissions.length; i++) {
            PermissionLib.MultiTargetPermission memory perm = preparedSetupData.permissions[i];

            if (perm.operation == PermissionLib.Operation.Grant) {
                dao.grant(perm.where, perm.who, perm.permissionId);
            } else if (perm.operation == PermissionLib.Operation.GrantWithCondition) {
                dao.grantWithCondition(perm.where, perm.who, perm.permissionId, IPermissionCondition(perm.condition));
            }
        }

        // Setup execute condition to allow token approve and voting escrow createLockFor
        ExecuteSelectorCondition.SelectorTarget memory tokenApprove =
            ExecuteSelectorCondition.SelectorTarget({ where: address(token), selectors: new bytes4[](1) });
        tokenApprove.selectors[0] = IERC20.approve.selector;
        condition.allowSelectors(tokenApprove);

        // Allow voting escrow createLockFor selector
        ExecuteSelectorCondition.SelectorTarget memory createLockFor =
            ExecuteSelectorCondition.SelectorTarget({ where: address(votingEscrow), selectors: new bytes4[](1) });
        createLockFor.selectors[0] = IVotingEscrowCore.createLockFor.selector;
        condition.allowSelectors(createLockFor);

        vm.stopPrank();

        // Verify condition allows the selectors we need
        require(condition.allowedSelectors(address(token), IERC20.approve.selector), "Approve selector not allowed");
        bytes4 createLockForSelector = bytes4(keccak256("createLockFor(uint256,address)"));
        require(
            condition.allowedSelectors(address(votingEscrow), createLockForSelector),
            "createLockFor selector not allowed"
        );

        // Setup merkle tree with test users
        setupMerkleTree();
    }

    /// @notice Setup merkle tree with users and their claimable amounts
    function setupMerkleTree() internal {
        // Create recipients array with test users
        recipients.push(Recipient({ account: alice, amount: 100e18 }));
        recipients.push(Recipient({ account: bob, amount: 200e18 }));
        recipients.push(Recipient({ account: carol, amount: 300e18 }));
        recipients.push(Recipient({ account: david, amount: 400e18 }));
        recipients.push(Recipient({ account: eve, amount: 500e18 }));

        // Generate merkle tree data manually
        bytes32[] memory leaves = new bytes32[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(recipients[i].account, recipients[i].amount));
        }

        // Build merkle root
        merkleRoot = buildMerkleRoot(leaves);

        // Generate proofs for each recipient
        for (uint256 i = 0; i < recipients.length; i++) {
            merkleProofs[recipients[i].account] = generateMerkleProof(leaves, i);
            claimAmounts[recipients[i].account] = recipients[i].amount;
        }
    }

    // =============================================================================
    // Core Integration Tests
    // =============================================================================

    /// @notice Test the complete flow: DAO creates campaign, users claim locks, receive veNFTs
    function test_Local_DAOCreatesLocksForUsers() public {
        // Calculate total amount needed
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            totalAmount += recipients[i].amount;
        }

        // Fund DAO with tokens
        token.mint(address(dao), totalAmount);

        // DAO creates campaign with MerkleDistributorStrategy and VotingEscrowLockPayoutActionEncoder
        vm.startPrank(address(dao));

        // Setup encoder campaign (this sets the voting escrow address for the campaign)
        bytes memory encoderInitData = votingEscrowEncoder.encodeSetupCampaignParams(address(votingEscrow));

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://test-ve-lock-airdrop",
            ICapitalDistributorPlugin.StrategyConfig({
                strategyId: toBytes32("merkle-distributor-strategy"),
                strategyParams: "",
                initData: abi.encode(merkleRoot) // DAO creates merkle root internally
            }),
            ICapitalDistributorPlugin.PayoutConfig({
                actionEncoderId: toBytes32("voting-escrow-lock-encoder"),
                actionEncoderInitData: encoderInitData,
                token: IERC20(address(token))
            }),
            ICapitalDistributorPlugin.CampaignSettings({ startTime: 0, endTime: 0 })
        );

        vm.stopPrank();

        // Verify campaign was created
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(address(campaign.allocationStrategy) != address(0), "Strategy should be deployed");
        assertTrue(address(campaign.actionEncoder) != address(0), "Encoder should be deployed");
        assertEq(address(campaign.token), address(token), "Token should match");

        // Get initial total locked amount
        uint256 totalLockedBefore = votingEscrow.totalLocked();

        // Users claim their locks
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            uint256 amount = claimAmounts[user];
            bytes32[] memory proof = merkleProofs[user];

            // Encode claim params for merkle strategy
            bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(proof, amount);

            // User claims to create the lock
            vm.prank(user);
            uint256 amountSent = capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");

            assertEq(amountSent, amount, "Lock should be created for correct amount");

            // Verify lock was created by checking total locked increased
            uint256 totalLockedAfter = votingEscrow.totalLocked();
            assertGe(totalLockedAfter, totalLockedBefore + amount, "Total locked should increase");
            totalLockedBefore = totalLockedAfter;
        }

        // Verify final state - all tokens are locked
        uint256 finalTotalLocked = votingEscrow.totalLocked();
        assertGe(finalTotalLocked, totalAmount, "All tokens should be locked");
    }

    /// @notice Test delegated claims - caller claims on behalf of recipient
    function test_Local_DAOCreatesLocksForUsers_WithDelegatedClaims() public {
        // Calculate total amount needed
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            totalAmount += recipients[i].amount;
        }

        // Fund DAO with tokens
        token.mint(address(dao), totalAmount);

        // DAO creates campaign
        vm.startPrank(address(dao));

        bytes memory encoderInitData = votingEscrowEncoder.encodeSetupCampaignParams(address(votingEscrow));

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://test-delegated-claims",
            ICapitalDistributorPlugin.StrategyConfig({
                strategyId: toBytes32("merkle-distributor-strategy"),
                strategyParams: "",
                initData: abi.encode(merkleRoot)
            }),
            ICapitalDistributorPlugin.PayoutConfig({
                actionEncoderId: toBytes32("voting-escrow-lock-encoder"),
                actionEncoderInitData: encoderInitData,
                token: IERC20(address(token))
            }),
            ICapitalDistributorPlugin.CampaignSettings({ startTime: 0, endTime: 0 })
        );

        vm.stopPrank();

        // Verify campaign was created
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(address(campaign.allocationStrategy) != address(0), "Strategy should be deployed");

        uint256 totalLockedBefore = votingEscrow.totalLocked();

        address caller = address(0x123);

        // Delegated claims not allowed by default
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            uint256 amount = claimAmounts[user];
            bytes32[] memory proof = merkleProofs[user];

            bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(proof, amount);

            // Should revert because delegated claims not allowed
            vm.expectRevert(
                abi.encodeWithSelector(
                    VotingEscrowLockPayoutActionEncoder.DelegatedClaimsNotAllowed.selector, caller, user
                )
            );
            vm.prank(caller);
            capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");
        }

        // Set caller as allowed delegate for delegated claims
        IPayoutActionEncoder actionEncoder = campaign.actionEncoder;
        VotingEscrowLockPayoutActionEncoder veEncoder =
            VotingEscrowLockPayoutActionEncoder(payable(address(actionEncoder)));
        vm.prank(veEncoder.owner());
        veEncoder.setAllowedDelegate(caller, true);

        // Now delegated claims should work
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            uint256 amount = claimAmounts[user];
            bytes32[] memory proof = merkleProofs[user];

            bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(proof, amount);

            // Caller claims on behalf of user
            vm.prank(caller);
            uint256 amountSent = capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");

            assertEq(amountSent, amount, "Lock should be created for correct amount");

            // Verify lock was created
            uint256 totalLockedAfter = votingEscrow.totalLocked();
            assertGe(totalLockedAfter, totalLockedBefore + amount, "Total locked should increase");
            totalLockedBefore = totalLockedAfter;
        }

        // Verify final state
        uint256 finalTotalLocked = votingEscrow.totalLocked();
        assertGe(finalTotalLocked, totalAmount, "All tokens should be locked");
    }

    /// @notice Test delegated claims with ANY_ADDR allowing all addresses
    function test_Local_DelegatedClaims_AllowAllDelegates() public {
        // Use only first recipient for this test
        address user = recipients[0].account;
        uint256 amount = recipients[0].amount;

        // Build merkle tree with single recipient (single leaf is its own root)
        bytes32 singleRecipientRoot = keccak256(abi.encodePacked(user, amount));

        // Fund DAO with tokens
        token.mint(address(dao), amount);

        // DAO creates campaign
        vm.startPrank(address(dao));

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://test-any-delegate",
            ICapitalDistributorPlugin.StrategyConfig({
                strategyId: toBytes32("merkle-distributor-strategy"),
                strategyParams: "",
                initData: abi.encode(singleRecipientRoot)
            }),
            ICapitalDistributorPlugin.PayoutConfig({
                actionEncoderId: toBytes32("voting-escrow-lock-encoder"),
                actionEncoderInitData: votingEscrowEncoder.encodeSetupCampaignParams(address(votingEscrow)),
                token: IERC20(address(token))
            }),
            ICapitalDistributorPlugin.CampaignSettings({ startTime: 0, endTime: 0 })
        );

        vm.stopPrank();

        // Get campaign encoder
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        VotingEscrowLockPayoutActionEncoder veEncoder =
            VotingEscrowLockPayoutActionEncoder(payable(address(campaign.actionEncoder)));

        // Encode claim params (empty proof for single-leaf tree)
        bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(new bytes32[](0), amount);

        // Initially, delegated claims should fail for random caller
        vm.expectRevert(
            abi.encodeWithSelector(
                VotingEscrowLockPayoutActionEncoder.DelegatedClaimsNotAllowed.selector, address(0xCAFE), user
            )
        );
        vm.prank(address(0xCAFE));
        capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");

        // Enable ANY_ADDR - this allows ALL addresses to make delegated claims
        address anyAddr = veEncoder.ANY_ADDR();
        vm.prank(veEncoder.owner());
        veEncoder.setAllowedDelegate(anyAddr, true);

        // Verify ANY_ADDR enables all delegates
        assertTrue(veEncoder.canDelegate(address(0xCAFE)), "Random caller should now be able to delegate");
        assertTrue(veEncoder.canDelegate(address(0xBEEF)), "Another random caller should also be able to delegate");

        // Now any address can claim on behalf of the user
        uint256 totalLockedBefore = votingEscrow.totalLocked();
        vm.prank(address(0xCAFE));
        uint256 amountSent = capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");

        assertEq(amountSent, amount, "Lock should be created for correct amount");
        assertGe(votingEscrow.totalLocked(), totalLockedBefore + amount, "Total locked should increase");
    }

    /// @notice Test that DAO can distribute locks to users at different times
    function test_Local_DAODistributesLocksAtDifferentTimes() public {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            totalAmount += recipients[i].amount;
        }

        token.mint(address(dao), totalAmount);

        vm.startPrank(address(dao));
        bytes memory encoderInitData = votingEscrowEncoder.encodeSetupCampaignParams(address(votingEscrow));

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://staggered-claims",
            ICapitalDistributorPlugin.StrategyConfig({
                strategyId: toBytes32("merkle-distributor-strategy"),
                strategyParams: "",
                initData: abi.encode(merkleRoot)
            }),
            ICapitalDistributorPlugin.PayoutConfig({
                actionEncoderId: toBytes32("voting-escrow-lock-encoder"),
                actionEncoderInitData: encoderInitData,
                token: IERC20(address(token))
            }),
            ICapitalDistributorPlugin.CampaignSettings({ startTime: 0, endTime: 0 })
        );
        vm.stopPrank();

        uint256 totalLockedBefore = votingEscrow.totalLocked();

        // User 0 claims first
        address user0 = recipients[0].account;
        bytes32[] memory proof0 = merkleProofs[user0];
        bytes memory strategyAuxData0 = merkleStrategy.encodeClaimParams(proof0, claimAmounts[user0]);

        vm.prank(user0);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, user0, strategyAuxData0, "");

        uint256 totalLockedAfter0 = votingEscrow.totalLocked();
        assertGe(totalLockedAfter0, totalLockedBefore + claimAmounts[user0], "Lock created for user 0");

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 10);

        // User 2 claims second (skipping user 1)
        address user2 = recipients[2].account;
        bytes32[] memory proof2 = merkleProofs[user2];
        bytes memory strategyAuxData2 = merkleStrategy.encodeClaimParams(proof2, claimAmounts[user2]);

        vm.prank(user2);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, user2, strategyAuxData2, "");

        uint256 totalLockedAfter2 = votingEscrow.totalLocked();
        assertGe(totalLockedAfter2, totalLockedAfter0 + claimAmounts[user2], "Lock created for user 2");

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 10);

        // User 1 claims third
        address user1 = recipients[1].account;
        bytes32[] memory proof1 = merkleProofs[user1];
        bytes memory strategyAuxData1 = merkleStrategy.encodeClaimParams(proof1, claimAmounts[user1]);

        vm.prank(user1);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, user1, strategyAuxData1, "");

        uint256 totalLockedAfter1 = votingEscrow.totalLocked();
        assertGe(totalLockedAfter1, totalLockedAfter2 + claimAmounts[user1], "Lock created for user 1");
    }

    /// @notice Test that invalid merkle proofs are rejected
    function test_Local_InvalidMerkleProofReverts() public {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            totalAmount += recipients[i].amount;
        }

        token.mint(address(dao), totalAmount);

        vm.startPrank(address(dao));
        bytes memory encoderInitData = votingEscrowEncoder.encodeSetupCampaignParams(address(votingEscrow));

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://invalid-proof-test",
            ICapitalDistributorPlugin.StrategyConfig({
                strategyId: toBytes32("merkle-distributor-strategy"),
                strategyParams: "",
                initData: abi.encode(merkleRoot)
            }),
            ICapitalDistributorPlugin.PayoutConfig({
                actionEncoderId: toBytes32("voting-escrow-lock-encoder"),
                actionEncoderInitData: encoderInitData,
                token: IERC20(address(token))
            }),
            ICapitalDistributorPlugin.CampaignSettings({ startTime: 0, endTime: 0 })
        );
        vm.stopPrank();

        // Try to claim with invalid proof
        address user = recipients[0].account;
        bytes32[] memory invalidProof = new bytes32[](2);
        invalidProof[0] = bytes32(uint256(12_345));
        invalidProof[1] = bytes32(uint256(67_890));

        bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(invalidProof, claimAmounts[user]);

        vm.prank(user);
        vm.expectRevert(); // Should revert due to invalid merkle proof
        capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");
    }

    /// @notice Test that users can withdraw their tokens after locks expire
    function test_Local_UsersClaimRewardsAfterLocksExpire() public {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            totalAmount += recipients[i].amount;
        }

        // Capture initial total locked
        uint256 initialTotalLocked = votingEscrow.totalLocked();

        token.mint(address(dao), totalAmount);

        // Create campaign and distribute locks
        vm.startPrank(address(dao));
        bytes memory encoderInitData = votingEscrowEncoder.encodeSetupCampaignParams(address(votingEscrow));

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://rewards-after-expiry",
            ICapitalDistributorPlugin.StrategyConfig({
                strategyId: toBytes32("merkle-distributor-strategy"),
                strategyParams: "",
                initData: abi.encode(merkleRoot)
            }),
            ICapitalDistributorPlugin.PayoutConfig({
                actionEncoderId: toBytes32("voting-escrow-lock-encoder"),
                actionEncoderInitData: encoderInitData,
                token: IERC20(address(token))
            }),
            ICapitalDistributorPlugin.CampaignSettings({ startTime: 0, endTime: 0 })
        );
        vm.stopPrank();

        // Track tokenIds for each user as locks are created
        uint256[] memory tokenIds = new uint256[](recipients.length);

        // Create locks for users and capture tokenIds from Deposit events
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            bytes32[] memory proof = merkleProofs[user];
            bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(proof, claimAmounts[user]);

            // Record logs to capture tokenId from Deposit event
            vm.recordLogs();
            vm.prank(user);
            capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");

            // Extract tokenId from Deposit event
            Vm.Log[] memory logs = vm.getRecordedLogs();

            bytes32 depositTopic = keccak256("Deposit(address,uint256,uint256,uint256,uint256)");
            for (uint256 j = 0; j < logs.length; j++) {
                if (logs[j].topics[0] == depositTopic && logs[j].emitter == address(votingEscrow)) {
                    tokenIds[i] = uint256(logs[j].topics[2]);
                    break;
                }
            }

            // Verify tokenId was captured
            assertGt(tokenIds[i], 0, "TokenId should be captured from event");
        }

        // Verify locks were created
        for (uint256 i = 0; i < recipients.length; i++) {
            IVotingEscrowIncreasing.LockedBalance memory lock =
                IVotingEscrowIncreasing(address(votingEscrow)).locked(tokenIds[i]);
            assertEq(lock.amount, claimAmounts[recipients[i].account], "Lock amount should match");
        }

        // Fast forward time to when locks expire (minLock = 0, so minimal wait)
        vm.warp(block.timestamp + 1 days);

        // Store user balances before withdrawals
        uint256[] memory userBalancesBefore = new uint256[](recipients.length);
        address lockNFT = votingEscrow.lockNFT();

        // First loop: All users approve and begin withdrawal
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            uint256 tokenId = tokenIds[i];

            userBalancesBefore[i] = token.balanceOf(user);

            // User must approve the voting escrow contract to transfer their NFT
            vm.prank(user);
            IERC721(lockNFT).approve(address(votingEscrow), tokenId);

            // Begin withdrawal to enter the withdrawal queue
            vm.prank(user);
            votingEscrow.beginWithdrawal(tokenId);
        }

        // Wait for the withdrawal queue cooldown period (1 day based on our setup)
        vm.warp(block.timestamp + 2 days);

        // Second loop: All users withdraw
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            uint256 tokenId = tokenIds[i];
            uint256 lockedAmount = claimAmounts[user];

            // Calculate the exit fee dynamically
            uint256 exitFee = IDynamicExitQueue(address(exitQueue)).calculateFee(tokenId);

            // Calculate expected amount after withdrawal fee deduction
            uint256 expectedAmountAfterFee = lockedAmount - exitFee;

            // Withdraw tokens
            vm.prank(user);
            votingEscrow.withdraw(tokenId);

            // Verify user received their tokens after exit fee deduction
            uint256 userBalanceAfter = token.balanceOf(user);
            assertEq(
                userBalanceAfter,
                userBalancesBefore[i] + expectedAmountAfterFee,
                "User should receive their tokens after withdrawal minus exit fee"
            );

            // Verify lock is cleared
            IVotingEscrowIncreasing.LockedBalance memory lockAfter =
                IVotingEscrowIncreasing(address(votingEscrow)).locked(tokenId);
            assertEq(lockAfter.amount, 0, "Lock should be cleared after withdrawal");
        }

        // Verify total locked decreased after withdrawals
        uint256 finalTotalLocked = votingEscrow.totalLocked();

        assertEq(
            finalTotalLocked,
            initialTotalLocked,
            "Total locked should be back to initial value after withdrawing all locks"
        );
    }

    // =============================================================================
    // Helper Functions
    // =============================================================================

    /// @notice Convert string to bytes32
    function toBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        require(temp.length <= 32, "String too long");

        assembly ("memory-safe") {
            result := mload(add(temp, 32))
        }
    }

    /// @notice Build merkle root from leaves
    function buildMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        require(leaves.length > 0, "No leaves provided");

        if (leaves.length == 1) {
            return leaves[0];
        }

        bytes32[] memory currentLevel = leaves;

        while (currentLevel.length > 1) {
            bytes32[] memory nextLevel = new bytes32[]((currentLevel.length + 1) / 2);

            for (uint256 i = 0; i < nextLevel.length; i++) {
                bytes32 left = currentLevel[i * 2];

                if (i * 2 + 1 < currentLevel.length) {
                    bytes32 right = currentLevel[i * 2 + 1];
                    nextLevel[i] = left < right
                        ? keccak256(abi.encodePacked(left, right))
                        : keccak256(abi.encodePacked(right, left));
                } else {
                    nextLevel[i] = left;
                }
            }

            currentLevel = nextLevel;
        }

        return currentLevel[0];
    }

    /// @notice Generate merkle proof for a leaf at given index
    function generateMerkleProof(bytes32[] memory leaves, uint256 index) internal pure returns (bytes32[] memory) {
        require(index < leaves.length, "Index out of bounds");

        uint256 proofLength = 0;
        uint256 temp = leaves.length;
        while (temp > 1) {
            proofLength++;
            temp = (temp + 1) / 2;
        }

        bytes32[] memory proof = new bytes32[](proofLength);
        bytes32[] memory currentLevel = leaves;
        uint256 currentIndex = index;
        uint256 proofIndex = 0;

        while (currentLevel.length > 1) {
            uint256 pairIndex = currentIndex % 2 == 0 ? currentIndex + 1 : currentIndex - 1;

            if (pairIndex < currentLevel.length) {
                proof[proofIndex] = currentLevel[pairIndex];
                proofIndex++;
            }

            // Build next level
            bytes32[] memory nextLevel = new bytes32[]((currentLevel.length + 1) / 2);
            for (uint256 i = 0; i < nextLevel.length; i++) {
                bytes32 left = currentLevel[i * 2];
                if (i * 2 + 1 < currentLevel.length) {
                    bytes32 right = currentLevel[i * 2 + 1];
                    nextLevel[i] = left < right
                        ? keccak256(abi.encodePacked(left, right))
                        : keccak256(abi.encodePacked(right, left));
                } else {
                    nextLevel[i] = left;
                }
            }

            currentLevel = nextLevel;
            currentIndex = currentIndex / 2;
        }

        // Resize proof array
        bytes32[] memory resizedProof = new bytes32[](proofIndex);
        for (uint256 i = 0; i < proofIndex; i++) {
            resizedProof[i] = proof[i];
        }

        return resizedProof;
    }
}

