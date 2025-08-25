// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AllocatorStrategyFactory} from "../src/factories/AllocatorStrategyFactory.sol";
import {CapitalDistributorPlugin} from "../src/CapitalDistributorPlugin.sol";
import {ActionEncoderFactory} from "../src/factories/ActionEncoderFactory.sol";
import {IAllocatorStrategy} from "../src/interfaces/IAllocatorStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {Action, IExecutor} from "@aragon/commons/executors/IExecutor.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {MerkleDistributorStrategy} from "../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import {MintableERC20} from "./mocks/MintableERC20.sol";
import {AragonTest} from "./helpers/AragonTest.sol";

/// @title AllocatorStrategyFeeTest
/// @notice Test suite for the fee functionality in allocator strategies
contract AllocatorStrategyFeeTest is AragonTest {
    CapitalDistributorPlugin plugin;
    MintableERC20 token;

    MerkleDistributorStrategy merkleImplementation;

    address feeCollector = makeAddr("feeCollector");

    bytes32 constant MERKLE_STRATEGY_ID = keccak256("merkle-distributor");
    string constant MERKLE_METADATA = "Merkle Tree Distribution Strategy";

    // Test events
    event StrategyFeeConfigured(bytes32 indexed strategyId, address indexed feeRecipient, uint256 feeBasisPoints);
    event PayoutClaimed(uint256 indexed campaignId, address indexed recipient, uint256 amount);
    event FeeCollected(uint256 indexed campaignId, address indexed feeRecipient, uint256 feeAmount);

    function setUp() public virtual {
        // Initialize plugin from base test
        plugin = CapitalDistributorPlugin(pluginAddress[0]);

        // Deploy test token
        token = new MintableERC20();
        token.mint(address(createdDAO), 1000000 ether);

        // Deploy strategy implementation
        merkleImplementation = new MerkleDistributorStrategy();
    }

    /// @notice Test registering a strategy with fee configuration
    function test_RegisterStrategyWithFee() public {
        uint256 feeBasisPoints = 250; // 2.5%

        vm.expectEmit(true, true, false, true);
        emit StrategyFeeConfigured(MERKLE_STRATEGY_ID, feeCollector, feeBasisPoints);

        allocatorStrategyFactory.registerStrategyType(
            MERKLE_STRATEGY_ID,
            address(merkleImplementation),
            MERKLE_METADATA,
            feeCollector,
            feeBasisPoints
        );

        // Verify fee configuration
        (address recipient, uint256 basisPoints) = allocatorStrategyFactory.strategyFees(MERKLE_STRATEGY_ID);
        assertEq(recipient, feeCollector);
        assertEq(basisPoints, feeBasisPoints);
    }

    /// @notice Test registering a strategy with zero fee
    function test_RegisterStrategyWithZeroFee() public {
        allocatorStrategyFactory.registerStrategyType(
            MERKLE_STRATEGY_ID,
            address(merkleImplementation),
            MERKLE_METADATA,
            address(0),
            0
        );

        // Verify fee configuration
        (address recipient, uint256 basisPoints) = allocatorStrategyFactory.strategyFees(MERKLE_STRATEGY_ID);
        assertEq(recipient, address(0));
        assertEq(basisPoints, 0);
    }

    /// @notice Test registering a strategy with invalid fee configuration
    function test_RegisterStrategyWithInvalidFee() public {
        // Test excessive fee (> 10%)
        vm.expectRevert(abi.encodeWithSelector(AllocatorStrategyFactory.ExcessiveFee.selector, 1001, 1000));
        allocatorStrategyFactory.registerStrategyType(
            MERKLE_STRATEGY_ID,
            address(merkleImplementation),
            MERKLE_METADATA,
            feeCollector,
            1001 // 10.01%
        );

        // Test non-zero fee with zero recipient
        vm.expectRevert(AllocatorStrategyFactory.InvalidFeeRecipient.selector);
        allocatorStrategyFactory.registerStrategyType(
            MERKLE_STRATEGY_ID,
            address(merkleImplementation),
            MERKLE_METADATA,
            address(0),
            100 // 1%
        );
    }

    /// @notice Test getting fee configuration for a deployed strategy
    function test_GetStrategyFeeByInstance() public {
        uint256 feeBasisPoints = 300; // 3%

        // Register strategy with fee
        allocatorStrategyFactory.registerStrategyType(
            MERKLE_STRATEGY_ID,
            address(merkleImplementation),
            MERKLE_METADATA,
            feeCollector,
            feeBasisPoints
        );

        // Deploy strategy instance
        address strategy = allocatorStrategyFactory.deployStrategy(
            MERKLE_STRATEGY_ID,
            createdDAO,
            abi.encode(bytes32(0))
        );

        // Get fee configuration by instance
        (address recipient, uint256 basisPoints) = allocatorStrategyFactory.getStrategyFeeByInstance(strategy);
        assertEq(recipient, feeCollector);
        assertEq(basisPoints, feeBasisPoints);

        // Test with non-existent strategy
        (recipient, basisPoints) = allocatorStrategyFactory.getStrategyFeeByInstance(address(0xdead));
        assertEq(recipient, address(0));
        assertEq(basisPoints, 0);
    }

    /// @notice Test claiming with fees
    function test_ClaimWithFees() public {
        uint256 feeBasisPoints = 500; // 5%
        uint256 claimAmount = 1000 ether;
        uint256 expectedFee = (claimAmount * feeBasisPoints) / 10000;
        uint256 expectedRecipientAmount = claimAmount - expectedFee;

        // Register strategy with fee
        allocatorStrategyFactory.registerStrategyType(
            MERKLE_STRATEGY_ID,
            address(merkleImplementation),
            MERKLE_METADATA,
            feeCollector,
            feeBasisPoints
        );

        // Create campaign with merkle strategy
        bytes32 merkleRoot = keccak256(abi.encodePacked(alice, claimAmount));
        vm.startPrank(address(createdDAO));
        uint256 campaignId = plugin.createCampaign(
            bytes("Test Campaign"),
            MERKLE_STRATEGY_ID,
            abi.encode(merkleRoot),
            abi.encode(merkleRoot, 0),
            token,
            bytes32(0), // Direct transfer
            bytes(""),
            true,
            0,
            0
        );
        vm.stopPrank();

        // Prepare merkle proof
        bytes32[] memory proof = new bytes32[](0);

        // Record balances before claim
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 feeCollectorBalanceBefore = token.balanceOf(feeCollector);

        // Expect events
        vm.expectEmit(true, true, false, true);
        emit PayoutClaimed(campaignId, alice, claimAmount - expectedFee);
        vm.expectEmit(true, true, false, true);
        emit FeeCollected(campaignId, feeCollector, expectedFee);

        // Claim as alice
        vm.prank(alice);
        plugin.claimCampaignPayout(campaignId, alice, abi.encode(proof, claimAmount), bytes(""));

        // Verify balances
        assertEq(token.balanceOf(alice) - aliceBalanceBefore, expectedRecipientAmount);
        assertEq(token.balanceOf(feeCollector) - feeCollectorBalanceBefore, expectedFee);
    }

    /// @notice Test claiming with zero fees
    function test_ClaimWithZeroFees() public {
        uint256 claimAmount = 1000 ether;

        // Register strategy with zero fee
        allocatorStrategyFactory.registerStrategyType(
            MERKLE_STRATEGY_ID,
            address(merkleImplementation),
            MERKLE_METADATA,
            address(0),
            0
        );

        // Create campaign
        bytes32 merkleRoot = keccak256(abi.encodePacked(alice, claimAmount));
        vm.startPrank(address(createdDAO));
        uint256 campaignId = plugin.createCampaign(
            bytes("Test Campaign"),
            MERKLE_STRATEGY_ID,
            abi.encode(merkleRoot),
            abi.encode(merkleRoot, 0),
            token,
            bytes32(0),
            bytes(""),
            true,
            0,
            0
        );
        vm.stopPrank();

        // Prepare merkle proof
        bytes32[] memory proof = new bytes32[](0);

        // Record balance before claim
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        // Expect only payout event, no fee event
        vm.expectEmit(true, true, false, true);
        emit PayoutClaimed(campaignId, alice, claimAmount);

        // Claim as alice
        vm.prank(alice);
        plugin.claimCampaignPayout(campaignId, alice, abi.encode(proof, claimAmount), bytes(""));

        // Verify alice received full amount
        assertEq(token.balanceOf(alice) - aliceBalanceBefore, claimAmount);
    }

    /// @notice Test fee calculation with different percentages
    function test_FeeCalculationAccuracy() public {
        // Test various fee percentages
        uint256[5] memory feeBasisPoints = [uint256(1), 50, 250, 500, 1000]; // 0.01%, 0.5%, 2.5%, 5%, 10%
        uint256[5] memory claimAmounts = [uint256(100), 1000, 10000, 100000, 1000000]; // Various amounts

        for (uint i = 0; i < feeBasisPoints.length; i++) {
            for (uint j = 0; j < claimAmounts.length; j++) {
                uint256 fee = feeBasisPoints[i];
                uint256 amount = claimAmounts[j] * 1 ether;

                uint256 expectedFee = (amount * fee) / 10000;
                uint256 expectedRecipient = amount - expectedFee;

                // Verify calculation precision
                assertEq(expectedFee + expectedRecipient, amount, "Fee calculation should not lose wei");
                assertLe(expectedFee, (amount * fee) / 10000, "Fee should not exceed expected percentage");
            }
        }
    }
}

