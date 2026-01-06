// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { CapitalDistributorPlugin } from "../../src/CapitalDistributorPlugin.sol";
import { ICapitalDistributorPlugin } from "../../src/interfaces/ICapitalDistributorPlugin.sol";
import { CapitalDistributorPluginSetup } from "../../src/CapitalDistributorPluginSetup.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { AllocatorStrategyFactory } from "../../src/factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../../src/factories/ActionEncoderFactory.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";
import { MerkleDistributorStrategy } from "../../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import {
    VotingEscrowLockPayoutActionEncoder
} from "../../src/payoutActionEncoders/VotingEscrowLockPayoutActionEncoder.sol";
import { IVotingEscrowIncreasing, IVotingEscrowCore } from "../../src/interfaces/IVotingEscrowIncreasing.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { console } from "forge-std/console.sol";

/// @notice Interface for the Dynamic Exit Queue contract
/// @dev Used to calculate the exit fee dynamically based on time elapsed and fee parameters
interface IDynamicExitQueue {
    /// @notice Calculate the absolute fee amount for exiting a specific token
    /// @param _tokenId The token ID to calculate fee for
    /// @return Fee amount in underlying token units
    function calculateFee(uint256 _tokenId) external view returns (uint256);
}
import { IPluginSetup } from "@aragon/commons/plugin/setup/IPluginSetup.sol";
import { IPermissionCondition } from "@aragon/commons/permission/condition/IPermissionCondition.sol";
import { PermissionLib } from "@aragon/commons/permission/PermissionLib.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IPayoutActionEncoder } from "../../src/interfaces/IPayoutActionEncoder.sol";

/// @title VotingEscrowLockIntegrationTest
/// @notice Integration test for the complete flow of Katana DAO creating voting escrow locks
///         for users as part of a long-term aligned airdrop using MerkleDistributorStrategy
/// @dev Tests the real flow:
///      1. DAO creates merkle tree internally and creates campaign with merkle root
///      2. DAO automatically distributes locks to all eligible users (DAO calls claimCampaignPayout)
///      3. Plugin executes actions through DAO executor -> Locks created for users
///      4. Users receive veNFTs representing their locked positions
///      Note: After locks expire, users can claim their rewards (separate flow, not tested here)
contract VotingEscrowLockPayoutTest is Test {
    // =============================================================================
    // Fork Configuration
    // =============================================================================
    uint256 internal fork;

    // =============================================================================
    // Katana Chain Addresses (from gist)
    // =============================================================================
    address internal constant KATANA_DAO = 0x545A4657eefb4E5e3C3D016e5b4ff2E18b17C042;
    address internal constant VOTING_ESCROW = 0x33fb4429d67b2d022B9d40751d44A9DA9A84d02b;
    // address internal constant TOKEN = 0x7F1f4b4b29f5058fA32CC7a97141b8D7e5ABDC2d;
    address internal constant TOKEN = 0xC194b4424123275745547B1b7D7203C29A886733;

    // User addresses from gist delegation structure
    address internal constant USER_0 = 0xfcffC2ac94d461b4C7A334DD1b7F7197f73e2a8f;
    address internal constant USER_1 = 0x29E3b139f4393aDda86303fcdAa35F60Bb7092bF;
    address internal constant USER_2 = 0x537C8f3d3E18dF5517a58B3fB9D9143697996802;
    address internal constant USER_3 = 0xc0A55e2205B289a967823662B841Bd67Aa362Aec;
    address internal constant USER_4 = 0x90561e5Cd8025FA6F52d849e8867C14A77C94BA0;

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
    IVotingEscrowIncreasing internal votingEscrow;
    IERC20 internal token;

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

    /// @dev Set up fork and deploy plugin on Katana DAO
    /// @notice Creates fork first, then sets up plugin similar to ExecuteConditionIntegrationTest
    function setUp() public {
        // vm.setEvmVersion("london");
        // Create fork of Katana chain FIRST - before any contract deployments
        fork = vm.createSelectFork(vm.envString("KATANA_RPC_URL"));

        // Use the Katana DAO from the fork
        dao = DAO(payable(KATANA_DAO));

        // Initialize contract interfaces for fork
        votingEscrow = IVotingEscrowIncreasing(VOTING_ESCROW);
        token = IERC20(TOKEN);

        // Deploy factories
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

        // Deploy plugin using setup (similar to ExecuteConditionIntegrationTest)
        CapitalDistributorPluginSetup setup = new CapitalDistributorPluginSetup();
        bytes memory installParams = abi.encode(address(strategyFactory), address(encoderFactory));

        IPluginSetup.PreparedSetupData memory preparedSetupData;
        address pluginAddr;
        (pluginAddr, preparedSetupData) = setup.prepareInstallation(address(dao), installParams);

        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddr);
        condition = ExecuteSelectorCondition(preparedSetupData.helpers[0]);

        // Apply permissions (simulate PluginSetupProcessor)
        // Note: This requires the DAO to have ROOT permission on itself
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
        // This mirrors the pattern from CapitalDistributorPluginTestBasic.t.sol
        ExecuteSelectorCondition.SelectorTarget memory tokenApprove =
            ExecuteSelectorCondition.SelectorTarget({ where: address(token), selectors: new bytes4[](1) });
        tokenApprove.selectors[0] = IERC20.approve.selector;
        condition.allowSelectors(tokenApprove);

        // Allow voting escrow createLockFor selector
        // Use the function signature to compute selector: createLockFor(uint256,address)
        ExecuteSelectorCondition.SelectorTarget memory createLockFor =
            ExecuteSelectorCondition.SelectorTarget({ where: VOTING_ESCROW, selectors: new bytes4[](1) });
        createLockFor.selectors[0] = IVotingEscrowCore.createLockFor.selector;
        // bytes4(keccak256("createLockFor(uint256,address)"));
        condition.allowSelectors(createLockFor);

        vm.stopPrank();

        // Verify condition allows the selectors we need
        // Note: We can't check hasPermission with condition in setUp because ExecuteSelectorCondition
        // requires action data to verify selectors, which we don't have yet
        require(condition.allowedSelectors(address(token), IERC20.approve.selector), "Approve selector not allowed");
        bytes4 createLockForSelector = bytes4(keccak256("createLockFor(uint256,address)"));
        require(condition.allowedSelectors(VOTING_ESCROW, createLockForSelector), "createLockFor selector not allowed");

        // Setup merkle tree with users from delegation structure
        setupMerkleTree();
    }

    /// @notice Setup merkle tree with users and their claimable amounts
    function setupMerkleTree() internal {
        // Create recipients array with users from delegation structure
        // Push elements to storage array (can't assign memory array to storage)
        recipients.push(Recipient({ account: USER_0, amount: 100e18 }));
        recipients.push(Recipient({ account: USER_1, amount: 200e18 }));
        recipients.push(Recipient({ account: USER_2, amount: 300e18 }));
        recipients.push(Recipient({ account: USER_3, amount: 400e18 }));
        recipients.push(Recipient({ account: USER_4, amount: 500e18 }));

        // Generate merkle tree data manually
        // Create leaves
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

    /// @notice Test the complete flow: DAO creates campaign with merkle tree, automatically distributes locks to users
    /// @dev This simulates the real flow where Katana DAO creates the merkle tree internally
    ///      and automatically creates locks for all eligible users as a long-term aligned airdrop
    function test_Fork_DAOCreatesLocksForUsers() public {
        // Calculate total amount needed
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            totalAmount += recipients[i].amount;
        }

        // Fund DAO with tokens
        deal(address(token), address(dao), totalAmount);

        // DAO creates campaign with MerkleDistributorStrategy and VotingEscrowLockPayoutActionEncoder
        // The merkle root is created internally by the DAO based on the distribution it wants to make
        vm.startPrank(address(dao));

        // Setup encoder campaign (this sets the voting escrow address for the campaign)
        bytes memory encoderInitData = votingEscrowEncoder.encodeSetupCampaignParams(VOTING_ESCROW);

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://katana-long-term-aligned-airdrop",
            ICapitalDistributorPlugin.StrategyConfig({
                strategyId: toBytes32("merkle-distributor-strategy"),
                strategyParams: "",
                initData: abi.encode(merkleRoot) // DAO creates merkle root internally
            }),
            ICapitalDistributorPlugin.PayoutConfig({
                actionEncoderId: toBytes32("voting-escrow-lock-encoder"),
                actionEncoderInitData: encoderInitData,
                token: token
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

        // users claim their locks
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            uint256 amount = claimAmounts[user];
            bytes32[] memory proof = merkleProofs[user];

            // Encode claim params for merkle strategy (DAO knows the proofs internally)
            bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(proof, amount);

            // DAO executes the claim on behalf of the user to create the lock
            // initiated by the user
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

        // Note: After locks expire, users can claim their rewards (this would be a separate test)
        // Users would need to provide merkle proofs at that time to verify their eligibility
    }

    /// @notice Test the complete flow: DAO creates campaign with merkle tree, automatically distributes locks to users
    /// @dev This simulates the real flow where Katana DAO creates the merkle tree internally
    ///      and automatically creates locks for all eligible users as a long-term aligned airdrop
    function test_Fork_DAOCreatesLocksForUsers_WithDelegatedClaims() public {
        // Calculate total amount needed
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            totalAmount += recipients[i].amount;
        }

        // Fund DAO with tokens
        deal(address(token), address(dao), totalAmount);

        // DAO creates campaign with MerkleDistributorStrategy and VotingEscrowLockPayoutActionEncoder
        // The merkle root is created internally by the DAO based on the distribution it wants to make
        vm.startPrank(address(dao));

        // Setup encoder campaign (this sets the voting escrow address for the campaign)
        bytes memory encoderInitData = votingEscrowEncoder.encodeSetupCampaignParams(VOTING_ESCROW);

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://katana-long-term-aligned-airdrop",
            ICapitalDistributorPlugin.StrategyConfig({
                strategyId: toBytes32("merkle-distributor-strategy"),
                strategyParams: "",
                initData: abi.encode(merkleRoot) // DAO creates merkle root internally
            }),
            ICapitalDistributorPlugin.PayoutConfig({
                actionEncoderId: toBytes32("voting-escrow-lock-encoder"),
                actionEncoderInitData: encoderInitData,
                token: token
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

        address caller = address(0x123);

        // delegated claims not allowed by default
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            uint256 amount = claimAmounts[user];
            bytes32[] memory proof = merkleProofs[user];

            // Encode claim params for merkle strategy (DAO knows the proofs internally)
            bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(proof, amount);

            // DAO executes the claim on behalf of the user to create the lock
            // initiated by different user (caller)
            vm.expectRevert(
                abi.encodeWithSelector(
                    VotingEscrowLockPayoutActionEncoder.DelegatedClaimsNotAllowed.selector, caller, user
                )
            );
            vm.prank(caller);
            capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");
        }

        // set allow delegated claims to true
        IPayoutActionEncoder actionEncoder = campaign.actionEncoder;
        VotingEscrowLockPayoutActionEncoder veEncoder =
            VotingEscrowLockPayoutActionEncoder(payable(address(actionEncoder)));
        vm.prank(veEncoder.owner());
        veEncoder.setAllowDelegatedClaims(true);

        // locks claimed by users who don't own the locks, for those who do
        // note that locks are still created for the users who own the locks i.e. who
        // were supposed to receive the airdrop
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            uint256 amount = claimAmounts[user];
            bytes32[] memory proof = merkleProofs[user];

            // Encode claim params for merkle strategy (DAO knows the proofs internally)
            bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(proof, amount);

            // DAO executes the claim on behalf of the user to create the lock
            // initiated by a different user
            vm.prank(caller);
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

        // Note: After locks expire, users can claim their rewards (this would be a separate test)
        // Users would need to provide merkle proofs at that time to verify their eligibility
    }

    /// @notice Test that DAO can distribute locks to users at different times
    function test_Fork_DAODistributesLocksAtDifferentTimes() public {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            totalAmount += recipients[i].amount;
        }

        deal(address(token), address(dao), totalAmount);

        vm.startPrank(address(dao));
        bytes memory encoderInitData = votingEscrowEncoder.encodeSetupCampaignParams(VOTING_ESCROW);

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://katana-staggered-claims",
            ICapitalDistributorPlugin.StrategyConfig({
                strategyId: toBytes32("merkle-distributor-strategy"),
                strategyParams: "",
                initData: abi.encode(merkleRoot)
            }),
            ICapitalDistributorPlugin.PayoutConfig({
                actionEncoderId: toBytes32("voting-escrow-lock-encoder"),
                actionEncoderInitData: encoderInitData,
                token: token
            }),
            ICapitalDistributorPlugin.CampaignSettings({ startTime: 0, endTime: 0 })
        );
        vm.stopPrank();

        uint256 totalLockedBefore = votingEscrow.totalLocked();

        // DAO distributes lock for user 0 first
        address user0 = recipients[0].account;
        bytes32[] memory proof0 = merkleProofs[user0];
        bytes memory strategyAuxData0 = merkleStrategy.encodeClaimParams(proof0, claimAmounts[user0]);

        vm.prank(user0);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, user0, strategyAuxData0, "");

        uint256 totalLockedAfter0 = votingEscrow.totalLocked();
        assertGe(totalLockedAfter0, totalLockedBefore + claimAmounts[user0], "Lock created for user 0");

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 10);

        // DAO distributes lock for user 2 second (skipping user 1)
        address user2 = recipients[2].account;
        bytes32[] memory proof2 = merkleProofs[user2];
        bytes memory strategyAuxData2 = merkleStrategy.encodeClaimParams(proof2, claimAmounts[user2]);

        vm.prank(user2);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, user2, strategyAuxData2, "");

        uint256 totalLockedAfter2 = votingEscrow.totalLocked();
        assertGe(totalLockedAfter2, totalLockedAfter0 + claimAmounts[user2], "Lock created for user 2");

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 10);

        // DAO distributes lock for user 1 third
        address user1 = recipients[1].account;
        bytes32[] memory proof1 = merkleProofs[user1];
        bytes memory strategyAuxData1 = merkleStrategy.encodeClaimParams(proof1, claimAmounts[user1]);

        vm.prank(user1);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, user1, strategyAuxData1, "");

        uint256 totalLockedAfter1 = votingEscrow.totalLocked();
        assertGe(totalLockedAfter1, totalLockedAfter2 + claimAmounts[user1], "Lock created for user 1");
    }

    /// @notice Test that invalid merkle proofs are rejected when DAO tries to distribute
    function test_Fork_InvalidMerkleProofReverts() public {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            totalAmount += recipients[i].amount;
        }

        deal(address(token), address(dao), totalAmount);

        vm.startPrank(address(dao));
        bytes memory encoderInitData = votingEscrowEncoder.encodeSetupCampaignParams(VOTING_ESCROW);

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://katana-invalid-proof-test",
            ICapitalDistributorPlugin.StrategyConfig({
                strategyId: toBytes32("merkle-distributor-strategy"),
                strategyParams: "",
                initData: abi.encode(merkleRoot)
            }),
            ICapitalDistributorPlugin.PayoutConfig({
                actionEncoderId: toBytes32("voting-escrow-lock-encoder"),
                actionEncoderInitData: encoderInitData,
                token: token
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

    /// @notice Test that users can claim their KAT rewards after their ve locks expire
    /// @dev This tests the second part of the flow:
    ///      1. DAO creates locks for users through the plugin (capturing tokenIds from events)
    ///      2. Time passes and locks expire
    ///      3. Users withdraw their tokens directly from the Voting Escrow contract, after calling beginWithdrawal()
    ///         and waiting for the withdrawal queue cooldown
    ///      4. Verify users received their tokens and locks are cleared
    function test_Fork_UsersClaimRewardsAfterLocksExpire() public {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            totalAmount += recipients[i].amount;
        }

        // Capture initial total locked before creating locks (since we're on a fork, there may be existing locks)
        uint256 initialTotalLocked = votingEscrow.totalLocked();

        deal(address(token), address(dao), totalAmount);

        // Create campaign and distribute locks
        vm.startPrank(address(dao));
        bytes memory encoderInitData = votingEscrowEncoder.encodeSetupCampaignParams(VOTING_ESCROW);

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://katana-rewards-after-expiry",
            ICapitalDistributorPlugin.StrategyConfig({
                strategyId: toBytes32("merkle-distributor-strategy"),
                strategyParams: "",
                initData: abi.encode(merkleRoot)
            }),
            ICapitalDistributorPlugin.PayoutConfig({
                actionEncoderId: toBytes32("voting-escrow-lock-encoder"),
                actionEncoderInitData: encoderInitData,
                token: token
            }),
            ICapitalDistributorPlugin.CampaignSettings({ startTime: 0, endTime: 0 })
        );
        vm.stopPrank();

        // Track tokenIds for each user as locks are created through the plugin
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
            // Event: Deposit(address indexed depositor, uint256 indexed tokenId, uint256 indexed startTs, uint256
            // value, uint256 newTotalLocked)
            Vm.Log[] memory logs = vm.getRecordedLogs();

            // Find Deposit event from Voting Escrow
            bytes32 depositTopic = keccak256("Deposit(address,uint256,uint256,uint256,uint256)");
            for (uint256 j = 0; j < logs.length; j++) {
                if (logs[j].topics[0] == depositTopic && logs[j].emitter == VOTING_ESCROW) {
                    // tokenId is the second indexed parameter (topics[2])
                    tokenIds[i] = uint256(logs[j].topics[2]);
                    break;
                }
            }

            // Verify tokenId was captured
            assertGt(tokenIds[i], 0, "TokenId should be captured from event");
        }

        // Verify locks were created
        for (uint256 i = 0; i < recipients.length; i++) {
            IVotingEscrowIncreasing.LockedBalance memory lock = votingEscrow.locked(tokenIds[i]);
            assertEq(lock.amount, claimAmounts[recipients[i].account], "Lock amount should match");
        }

        // Fast forward time to when locks expire
        // minLock = 0, so we warp to 1 day after the current block timestamp
        uint256 lockDuration = 0;
        vm.warp(block.timestamp + lockDuration + 1 days);

        // Now users can withdraw their tokens from the Voting Escrow
        // Note: The withdrawal queue contract deducts a dynamic exit fee during withdrawal
        // The fee is calculated by the DynamicExitQueue contract's calculateFee() function
        // which considers:
        // - The locked amount (underlying balance)
        // - Time elapsed since the ticket was queued
        // - Fee parameters (feePercent, minFeePercent, cooldown, minCooldown, slope)
        // The fee can be fixed, tiered, or dynamic (linear decay) based on configuration

        // Get the withdrawal queue contract address
        address queueAddress = votingEscrow.queue();
        IDynamicExitQueue exitQueue = IDynamicExitQueue(queueAddress);

        // Store user balances before withdrawals for verification (using array indexed by recipient index)
        uint256[] memory userBalancesBefore = new uint256[](recipients.length);
        address lockNFT = votingEscrow.lockNFT();

        // First loop: All users approve and begin withdrawal to enter the withdrawal queue
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            uint256 tokenId = tokenIds[i];

            // Get user's balance before withdrawal
            userBalancesBefore[i] = token.balanceOf(user);

            // User must approve the voting escrow contract to transfer their NFT
            // This is required for beginWithdrawal() to transfer the NFT to the withdrawal queue
            vm.prank(user);
            IERC721(lockNFT).approve(VOTING_ESCROW, tokenId);

            // First, user must begin withdrawal to enter the withdrawal queue
            vm.prank(user);
            votingEscrow.beginWithdrawal(tokenId);
        }

        // Wait for the withdrawal queue cooldown period (all users wait together)
        vm.warp(block.timestamp + 2 weeks);

        // Second loop: All users calculate fees, withdraw, and verify
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            uint256 tokenId = tokenIds[i];
            uint256 lockedAmount = claimAmounts[user];

            // Calculate the exit fee dynamically using the queue contract
            // This calculates the fee based on:
            // - Locked amount (underlying balance)
            // - Time elapsed since queued
            // - Fee parameters (feePercent, minFeePercent, cooldown, minCooldown, slope)
            uint256 exitFee = exitQueue.calculateFee(tokenId);

            // Calculate expected amount after withdrawal fee deduction
            // The withdrawal queue contract deducts the calculated fee from the locked amount
            uint256 expectedAmountAfterFee = lockedAmount - exitFee;

            // Then, user can withdraw their tokens from Voting Escrow
            vm.prank(user);
            votingEscrow.withdraw(tokenId);

            // Verify user received their tokens after exit fee deduction
            uint256 userBalanceAfter = token.balanceOf(user);
            assertEq(
                userBalanceAfter,
                userBalancesBefore[i] + expectedAmountAfterFee,
                "User should receive their tokens after withdrawal minus dynamically calculated exit fee"
            );

            // Verify lock is cleared
            IVotingEscrowIncreasing.LockedBalance memory lockAfter = votingEscrow.locked(tokenId);
            assertEq(lockAfter.amount, 0, "Lock should be cleared after withdrawal");
        }

        // Verify total locked decreased after withdrawals
        // Since we're on a fork, there may be existing locks before our test
        // When we withdraw, the full locked amount is removed from totalLocked
        // (the exit fee is deducted from user payout but doesn't affect totalLocked)
        uint256 finalTotalLocked = votingEscrow.totalLocked();

        assertEq(
            finalTotalLocked,
            initialTotalLocked,
            "Total locked should be back to initial value after withdrawing all our locks"
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
