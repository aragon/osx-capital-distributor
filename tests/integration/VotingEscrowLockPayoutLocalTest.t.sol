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
    function test_Local_DelegatedClaims_AllowAllDelegates() public {
        address user = recipients[0].account;
        uint256 amount = recipients[0].amount;
        bytes32 singleRecipientRoot = keccak256(abi.encodePacked(user, amount));

        token.mint(address(dao), amount);
        uint256 campaignId = _createCampaignWithRoot(singleRecipientRoot);

        VotingEscrowLockPayoutActionEncoder veEncoder = _getVeEncoder(campaignId);
        bytes memory strategyAuxData = merkleStrategy.encodeClaimParams(new bytes32[](0), amount);

        // Initially, delegated claims should fail for random caller
        vm.expectRevert(
            abi.encodeWithSelector(
                VotingEscrowLockPayoutActionEncoder.DelegatedClaimsNotAllowed.selector, address(0xCAFE), user
            )
        );
        vm.prank(address(0xCAFE));
        capitalDistributorPlugin.claimCampaignPayout(campaignId, user, strategyAuxData, "");

        // Enable ANY_ADDR - allows ALL addresses to make delegated claims
        address owner = veEncoder.owner();
        address anyAddr = veEncoder.ANY_ADDR();
        vm.prank(owner);
        veEncoder.setAllowedDelegate(anyAddr, true);

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
        _fundDao();
        uint256 campaignId = _createCampaign();
        uint256 totalLockedBefore = votingEscrow.totalLocked();

        // User 0 claims first
        _claimFor(campaignId, recipients[0].account);
        uint256 expected0 = totalLockedBefore + claimAmounts[recipients[0].account];
        assertGe(votingEscrow.totalLocked(), expected0, "Lock created for user 0");

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 10);

        // User 2 claims second (skipping user 1)
        uint256 lockedAfterUser0 = votingEscrow.totalLocked();
        _claimFor(campaignId, recipients[2].account);
        uint256 expected2 = lockedAfterUser0 + claimAmounts[recipients[2].account];
        assertGe(votingEscrow.totalLocked(), expected2, "Lock created for user 2");

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 10);

        // User 1 claims third
        uint256 lockedAfterUser2 = votingEscrow.totalLocked();
        _claimFor(campaignId, recipients[1].account);
        uint256 expected1 = lockedAfterUser2 + claimAmounts[recipients[1].account];
        assertGe(votingEscrow.totalLocked(), expected1, "Lock created for user 1");
    }

    /// @notice Test that invalid merkle proofs are rejected
    function test_Local_InvalidMerkleProofReverts() public {
        _fundDao();
        uint256 campaignId = _createCampaign();

        address user = recipients[0].account;
        bytes32[] memory invalidProof = new bytes32[](2);
        invalidProof[0] = bytes32(uint256(12_345));
        invalidProof[1] = bytes32(uint256(67_890));

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

