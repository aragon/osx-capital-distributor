// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

// CDP Deployer utility (handles OSx, VE, and CDP deployment)
import { CDPDeployer, FullStackParams, FullStackDeployment } from "../../src/deploy/CDPDeployer.sol";

// Capital Distributor imports
import { CapitalDistributorPlugin } from "../../src/CapitalDistributorPlugin.sol";
import { ICapitalDistributorPlugin } from "../../src/interfaces/ICapitalDistributorPlugin.sol";
import { MerkleDistributorStrategy } from "../../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import {
    VotingEscrowLockPayoutActionEncoder
} from "../../src/payoutActionEncoders/VotingEscrowLockPayoutActionEncoder.sol";

// VE Governance imports
import { VotingEscrowV1_2_0 as VotingEscrow } from "@ve/escrow/VotingEscrowIncreasing_v1_2_0.sol";
import { DynamicExitQueue as ExitQueue } from "@ve/queue/DynamicExitQueue.sol";
import { IClockV1_2_0 } from "@ve/clock/IClock_v1_2_0.sol";
import { IEscrowCurveIncreasingV1_2_0 as IEscrowCurve } from "@ve/curve/IEscrowCurveIncreasing_v1_2_0.sol";

// Aragon/OSx imports
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";

// OpenZeppelin imports
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// Test utilities
import { MintableERC20 } from "../mocks/MintableERC20.sol";
import { IVotingEscrowIncreasing } from "@escrow/IVotingEscrowIncreasing.sol";
import { MerkleTreeBuilder } from "../utils/MerkleTreeBuilder.sol";

/// @notice Interface for the Dynamic Exit Queue contract
interface IDynamicExitQueue {
    /// @notice Calculate the absolute fee amount for exiting a specific token
    function calculateFee(uint256 _tokenId) external view returns (uint256);
}

/// @title VotingEscrowLockPayoutLocalTest
/// @notice Integration test for the complete flow of DAO creating voting escrow locks
///         for users using a locally deployed ve-governance system (no fork required)
/// @dev Tests the real flow:
///      1. CDPDeployer deploys everything: OSx, VE governance, and CDP plugin
///      2. DAO creates merkle tree internally and creates campaign with merkle root
///      3. Users claim locks, receiving veNFTs representing their locked positions
///      4. After locks expire, users can withdraw their tokens
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
    // Deployment
    // =============================================================================
    FullStackDeployment internal deployment;
    MintableERC20 internal token;

    // Convenience aliases (set in setUp)
    DAO internal dao;
    CapitalDistributorPlugin internal capitalDistributorPlugin;
    ExecuteSelectorCondition internal condition;
    MerkleDistributorStrategy internal merkleStrategy;
    VotingEscrowLockPayoutActionEncoder internal votingEscrowEncoder;
    VotingEscrow internal votingEscrow;
    ExitQueue internal exitQueue;

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

    /// @dev Set up local deployment using CDPDeployer.deployFullStack()
    function setUp() public {
        // Deploy token first (CDPDeployer requires an existing token)
        token = new MintableERC20();

        // Deploy everything using CDPDeployer
        CDPDeployer deployer = new CDPDeployer();
        deployment = deployer.deployFullStack(
            FullStackParams({
                admin: admin,
                token: address(token),
                feeRecipient: address(0),
                feeBasisPoints: 0,
                pluginRepoSubdomain: "capital-distributor"
            })
        );

        // Set convenience aliases
        dao = deployment.dao;
        capitalDistributorPlugin = deployment.capitalDistributorPlugin;
        condition = deployment.condition;
        merkleStrategy = deployment.cdpInfra.merkleStrategy;
        votingEscrowEncoder = deployment.cdpInfra.votingEscrowEncoder;
        votingEscrow = deployment.votingEscrow;
        exitQueue = deployment.exitQueue;

        // Verify condition is configured correctly
        require(condition.allowedSelectors(address(token), IERC20.approve.selector), "Approve selector not allowed");
        require(
            condition.allowedSelectors(address(votingEscrow), bytes4(keccak256("createLockFor(uint256,address)"))),
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
        merkleRoot = MerkleTreeBuilder.buildMerkleRoot(leaves);

        // Generate proofs for each recipient
        for (uint256 i = 0; i < recipients.length; i++) {
            merkleProofs[recipients[i].account] = MerkleTreeBuilder.generateMerkleProof(leaves, i);
            claimAmounts[recipients[i].account] = recipients[i].amount;
        }
    }

    // =============================================================================
    // Campaign Setup Helpers
    // =============================================================================

    /// @dev Creates a campaign with default settings using the standard merkle root
    function _createCampaign() internal returns (uint256 campaignId) {
        return _createCampaignWithRoot(merkleRoot);
    }

    /// @dev Creates a campaign with a custom merkle root
    function _createCampaignWithRoot(bytes32 root) internal returns (uint256 campaignId) {
        vm.startPrank(address(dao));
        campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://test-campaign",
            ICapitalDistributorPlugin.StrategyConfig({
                strategyId: toBytes32("merkle-distributor-strategy"), strategyParams: "", initData: abi.encode(root)
            }),
            ICapitalDistributorPlugin.PayoutConfig({
                actionEncoderId: toBytes32("voting-escrow-lock-encoder"),
                actionEncoderInitData: votingEscrowEncoder.encodeSetupCampaignParams(address(votingEscrow)),
                token: IERC20(address(token))
            }),
            ICapitalDistributorPlugin.CampaignSettings({ startTime: 0, endTime: 0 })
        );
        vm.stopPrank();
    }

    /// @dev Calculates total amount from all recipients
    function _totalAmount() internal view returns (uint256 total) {
        for (uint256 i = 0; i < recipients.length; i++) {
            total += recipients[i].amount;
        }
    }

    /// @dev Funds DAO with total amount needed for all recipients
    function _fundDao() internal {
        token.mint(address(dao), _totalAmount());
    }

    /// @dev Gets the VotingEscrowLockPayoutActionEncoder for a campaign
    function _getVeEncoder(uint256 campaignId) internal view returns (VotingEscrowLockPayoutActionEncoder) {
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        return VotingEscrowLockPayoutActionEncoder(payable(address(campaign.actionEncoder)));
    }

    /// @dev Claims payout for a user with their merkle proof
    function _claimFor(uint256 campaignId, address user) internal returns (uint256 amountSent) {
        bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(merkleProofs[user], claimAmounts[user]);
        vm.prank(user);
        return capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");
    }

    /// @dev Claims for a user initiated by a different caller (delegated claim)
    function _claimForBy(uint256 campaignId, address user, address caller) internal returns (uint256 amountSent) {
        bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(merkleProofs[user], claimAmounts[user]);
        vm.prank(caller);
        return capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");
    }

    /// @dev Claims for all recipients and returns the token IDs of created locks
    function _claimForAllAndGetTokenIds(uint256 campaignId) internal returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](recipients.length);
        bytes32 depositTopic = keccak256("Deposit(address,uint256,uint256,uint256,uint256)");

        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;

            vm.recordLogs();
            _claimFor(campaignId, user);

            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j = 0; j < logs.length; j++) {
                if (logs[j].topics[0] == depositTopic && logs[j].emitter == address(votingEscrow)) {
                    tokenIds[i] = uint256(logs[j].topics[2]);
                    break;
                }
            }
        }
    }

    // =============================================================================
    // Core Integration Tests
    // =============================================================================

    /// @notice Test the complete flow: DAO creates campaign, users claim locks, receive veNFTs
    function test_Local_DAOCreatesLocksForUsers() public {
        _fundDao();
        uint256 campaignId = _createCampaign();
        uint256 totalLockedBefore = votingEscrow.totalLocked();

        // Users claim their locks
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            uint256 amount = claimAmounts[user];

            uint256 amountSent = _claimFor(campaignId, user);

            assertEq(amountSent, amount, "Lock should be created for correct amount");
            assertGe(votingEscrow.totalLocked(), totalLockedBefore + amount, "Total locked should increase");
            totalLockedBefore = votingEscrow.totalLocked();
        }

        assertGe(votingEscrow.totalLocked(), _totalAmount(), "All tokens should be locked");
    }

    /// @notice Test delegated claims - caller claims on behalf of recipient
    function test_Local_DAOCreatesLocksForUsers_WithDelegatedClaims() public {
        _fundDao();
        uint256 campaignId = _createCampaign();
        address caller = address(0x123);

        // Delegated claims not allowed by default
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(merkleProofs[user], claimAmounts[user]);

            vm.expectRevert(
                abi.encodeWithSelector(
                    VotingEscrowLockPayoutActionEncoder.DelegatedClaimsNotAllowed.selector, caller, user
                )
            );
            vm.prank(caller);
            capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");
        }

        // Enable caller as allowed delegate
        VotingEscrowLockPayoutActionEncoder veEncoder = _getVeEncoder(campaignId);
        vm.prank(veEncoder.owner());
        veEncoder.setAllowedDelegate(caller, true);

        // Now delegated claims succeed - locks created for intended recipients
        uint256 totalLockedBefore = votingEscrow.totalLocked();
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            uint256 amount = claimAmounts[user];

            uint256 amountSent = _claimForBy(campaignId, user, caller);

            assertEq(amountSent, amount, "Lock should be created for correct amount");
            assertGe(votingEscrow.totalLocked(), totalLockedBefore + amount, "Total locked should increase");
            totalLockedBefore = votingEscrow.totalLocked();
        }

        assertGe(votingEscrow.totalLocked(), _totalAmount(), "All tokens should be locked");
    }

    /// @notice Test delegated claims with ANY_ADDR allowing all addresses
    function test_Local_DelegatedClaims_AllowAllDelegates(address caller) public {
        address user = recipients[0].account;
        uint256 amount = recipients[0].amount;
        bytes32 singleRecipientRoot = keccak256(abi.encodePacked(user, amount));

        token.mint(address(dao), amount);
        uint256 campaignId = _createCampaignWithRoot(singleRecipientRoot);

        VotingEscrowLockPayoutActionEncoder veEncoder = _getVeEncoder(campaignId);
        bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(new bytes32[](0), amount);

        // Enable ANY_ADDR - allows ALL addresses to make delegated claims
        address owner = veEncoder.owner();
        address anyAddr = veEncoder.ANY_ADDR();
        vm.prank(owner);
        veEncoder.setAllowedDelegate(anyAddr, true);

        assertTrue(veEncoder.canDelegate(caller), "Caller should now be able to delegate");

        // Now any address can claim on behalf of the user
        uint256 totalLockedBefore = votingEscrow.totalLocked();
        vm.prank(address(0xCAFE));
        uint256 amountSent = capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");

        assertEq(amountSent, amount, "Lock should be created for correct amount");
        assertGe(votingEscrow.totalLocked(), totalLockedBefore + amount, "Total locked should increase");
    }

    /// @notice Test Scenario 1: Base case - first lock in an interval
    function test_Local_BaseCase_FirstLockInInterval() public {
        _fundDao();
        uint256 campaignId = _createCampaign();

        // Record the checkpoint interval start
        uint256 checkpointStart = IClockV1_2_0(votingEscrow.clock()).epochPrevCheckpointTs();

        // User claims - this is the base case
        _claimFor(campaignId, recipients[0].account);

        // Verify the lock's start matches the checkpoint boundary
        uint256 tokenId = votingEscrow.lastLockId();
        IVotingEscrowIncreasing.LockedBalance memory lock = votingEscrow.locked(tokenId);
        assertEq(lock.start, checkpointStart, "Lock start should match checkpoint boundary");

        // Get token point from curve to verify writtenTs equals checkpointStart (base case)
        IEscrowCurve curve = IEscrowCurve(votingEscrow.curve());
        IEscrowCurve.TokenPoint memory point = curve.tokenPointHistory(tokenId, 1);

        // In base case with no time manipulation, writtenTs should be >= checkpointStart
        assertGe(point.writtenTs, checkpointStart, "writtenTs should be >= checkpointStart in base case");
    }

    /// @notice Test Scenario 2: Same Deposit Interval - different writtenTs but same lock.start
    function test_Local_SameDepositInterval_DifferentWrittenTs() public {
        _fundDao();
        uint256 campaignId = _createCampaign();

        // Record the checkpoint interval start
        uint256 checkpointStart = IClockV1_2_0(votingEscrow.clock()).epochPrevCheckpointTs();

        // User 0 claims first
        _claimFor(campaignId, recipients[0].account);
        uint256 tokenId0 = votingEscrow.lastLockId();

        // Advance time by 1 day (still within same 1-week checkpoint interval)
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 10);

        // User 1 claims second - same checkpoint interval, different writtenTs
        _claimFor(campaignId, recipients[1].account);
        uint256 tokenId1 = votingEscrow.lastLockId();

        // Both locks should have the SAME start (same checkpoint boundary)
        IVotingEscrowIncreasing.LockedBalance memory lock0 = votingEscrow.locked(tokenId0);
        IVotingEscrowIncreasing.LockedBalance memory lock1 = votingEscrow.locked(tokenId1);

        assertEq(lock0.start, checkpointStart, "Lock 0 start should match checkpoint boundary");
        assertEq(lock1.start, checkpointStart, "Lock 1 start should match checkpoint boundary");
        assertEq(lock0.start, lock1.start, "Both locks should have same start (same interval)");

        // Get token points from curve to verify writtenTs is different
        IEscrowCurve curve = IEscrowCurve(votingEscrow.curve());
        IEscrowCurve.TokenPoint memory point0 = curve.tokenPointHistory(tokenId0, 1);
        IEscrowCurve.TokenPoint memory point1 = curve.tokenPointHistory(tokenId1, 1);

        // writtenTs should be different (actual block.timestamp when checkpoint was written)
        assertGt(point1.writtenTs, point0.writtenTs, "writtenTs should be different (point1 > point0)");
        // checkpointTs should be the same (both normalized to same interval boundary)
        assertEq(point0.checkpointTs, point1.checkpointTs, "checkpointTs should be same for both locks");
    }

    /// @notice Test Scenario 3: New Deposit Interval - different checkpoint interval
    function test_Local_NewDepositInterval_DifferentLockStart() public {
        _fundDao();
        uint256 campaignId = _createCampaign();

        // Record the FIRST checkpoint interval start
        uint256 firstCheckpointStart = IClockV1_2_0(votingEscrow.clock()).epochPrevCheckpointTs();

        // User 0 claims in first interval
        _claimFor(campaignId, recipients[0].account);
        uint256 tokenId0 = votingEscrow.lastLockId();

        // Advance time by MORE THAN 1 week to enter a NEW checkpoint interval
        vm.warp(block.timestamp + 1 weeks + 1);
        vm.roll(block.number + 100);

        // Record the SECOND checkpoint interval start (should be different!)
        uint256 secondCheckpointStart = IClockV1_2_0(votingEscrow.clock()).epochPrevCheckpointTs();
        assertGt(secondCheckpointStart, firstCheckpointStart, "Should be in new checkpoint interval");

        // User 1 claims in second interval - DIFFERENT lock.start
        _claimFor(campaignId, recipients[1].account);
        uint256 tokenId1 = votingEscrow.lastLockId();

        // Locks should have DIFFERENT start times
        IVotingEscrowIncreasing.LockedBalance memory lock0 = votingEscrow.locked(tokenId0);
        IVotingEscrowIncreasing.LockedBalance memory lock1 = votingEscrow.locked(tokenId1);

        assertEq(lock0.start, firstCheckpointStart, "Lock 0 start should match first checkpoint");
        assertEq(lock1.start, secondCheckpointStart, "Lock 1 start should match second checkpoint");
        assertGt(lock1.start, lock0.start, "Lock 1 should have later start (different interval)");

        // Get token points from curve to verify both writtenTs and checkpointTs are different
        IEscrowCurve curve = IEscrowCurve(votingEscrow.curve());
        IEscrowCurve.TokenPoint memory point0 = curve.tokenPointHistory(tokenId0, 1);
        IEscrowCurve.TokenPoint memory point1 = curve.tokenPointHistory(tokenId1, 1);

        // writtenTs should be different (actual block.timestamp when checkpoint was written)
        assertGt(point1.writtenTs, point0.writtenTs, "writtenTs should be different (point1 > point0)");
        // checkpointTs should ALSO be different (different interval boundaries)
        assertGt(point1.checkpointTs, point0.checkpointTs, "checkpointTs should be different (new interval)");
    }

    /// @notice Test that invalid merkle proofs are rejected
    function test_Local_InvalidMerkleProofReverts(uint256 proof1, uint256 proof2) public {
        _fundDao();
        uint256 campaignId = _createCampaign();

        address user = recipients[0].account;
        bytes32[] memory invalidProof = new bytes32[](2);
        invalidProof[0] = bytes32(proof1);
        invalidProof[1] = bytes32(proof2);

        bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(invalidProof, claimAmounts[user]);

        vm.prank(user);
        vm.expectRevert();
        capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");
    }

    /// @notice Test that users can claim their KAT rewards after their ve locks expire
    /// @dev Tests the flow: create locks → time passes → users withdraw via exit queue
    function test_Local_UsersClaimRewardsAfterLocksExpire() public {
        uint256 initialTotalLocked = votingEscrow.totalLocked();
        _fundDao();
        uint256 campaignId = _createCampaign();

        // Create locks for all users and capture token IDs
        uint256[] memory tokenIds = _claimForAllAndGetTokenIds(campaignId);

        // Verify locks were created
        for (uint256 i = 0; i < recipients.length; i++) {
            assertGt(tokenIds[i], 0, "TokenId should be captured from event");
            IVotingEscrowIncreasing.LockedBalance memory lock =
                IVotingEscrowIncreasing(address(votingEscrow)).locked(tokenIds[i]);
            assertEq(lock.amount, claimAmounts[recipients[i].account], "Lock amount should match");
        }

        // Fast forward past min lock period
        vm.warp(block.timestamp + 1 days);

        // All users begin withdrawal
        address lockNFT = votingEscrow.lockNFT();
        uint256[] memory userBalancesBefore = new uint256[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            userBalancesBefore[i] = token.balanceOf(user);

            vm.prank(user);
            IERC721(lockNFT).approve(address(votingEscrow), tokenIds[i]);
            vm.prank(user);
            votingEscrow.beginWithdrawal(tokenIds[i]);
        }

        // Wait for cooldown period
        vm.warp(block.timestamp + 2 days);

        // All users withdraw
        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i].account;
            uint256 tokenId = tokenIds[i];
            uint256 lockedAmount = claimAmounts[user];
            uint256 exitFee = IDynamicExitQueue(address(exitQueue)).calculateFee(tokenId);

            vm.prank(user);
            votingEscrow.withdraw(tokenId);

            assertEq(
                token.balanceOf(user),
                userBalancesBefore[i] + lockedAmount - exitFee,
                "User should receive tokens minus exit fee"
            );

            IVotingEscrowIncreasing.LockedBalance memory lockAfter =
                IVotingEscrowIncreasing(address(votingEscrow)).locked(tokenId);
            assertEq(lockAfter.amount, 0, "Lock should be cleared after withdrawal");
        }

        assertEq(votingEscrow.totalLocked(), initialTotalLocked, "Total locked should be back to initial value");
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
}
