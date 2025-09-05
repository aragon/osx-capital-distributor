// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { GaugeDistributionStrategy } from "../../src/allocatorStrategies/GaugeDistributionStrategy.sol";
import { MerkleDistributorStrategy } from "../../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import { IAddressGaugeVoter } from "../../src/interfaces/helpers/IAddressGaugeVoter.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";

/// @title EncoderPatternExampleTest
/// @notice Demonstrates the usage of encoder/decoder functions in allocator strategies
/// @dev This test shows how consumers can use the encoder pattern instead of manual encoding
contract EncoderPatternExampleTest is Test {
    GaugeDistributionStrategy gaugeStrategy;
    MerkleDistributorStrategy merkleStrategy;
    
    address mockDAO = makeAddr("dao");
    address mockPlugin = makeAddr("plugin");
    address mockGaugeVoter = makeAddr("gaugeVoter");
    
    function setUp() public {
        gaugeStrategy = new GaugeDistributionStrategy();
        merkleStrategy = new MerkleDistributorStrategy();
    }
    
    /// @notice Example: Using encoders for GaugeDistributionStrategy initialization
    function test_GaugeStrategyEncoderUsage() public {
        // OLD WAY: Manual encoding
        bytes memory oldWayInitData = abi.encode(IAddressGaugeVoter(mockGaugeVoter));
        
        // NEW WAY: Using encoder function
        bytes memory newWayInitData = gaugeStrategy.encodeInitializationParams(IAddressGaugeVoter(mockGaugeVoter));
        
        // Both ways produce the same result
        assertEq(oldWayInitData, newWayInitData, "Encoder should produce same result as manual encoding");
        
        // Verify decoder works
        IAddressGaugeVoter decodedGaugeVoter = gaugeStrategy.decodeInitializationParams(newWayInitData);
        assertEq(address(decodedGaugeVoter), mockGaugeVoter, "Decoder should extract correct address");
    }
    
    /// @notice Example: Using encoders for campaign creation
    function test_GaugeStrategyCreationEncoderUsage() public {
        uint256 totalDistributionAmount = 1000 ether;
        
        // OLD WAY: Manual encoding
        bytes memory oldWayData = abi.encode(totalDistributionAmount);
        
        // NEW WAY: Using encoder function
        bytes memory newWayData = gaugeStrategy.encodeSetAllocationCampaignParams(totalDistributionAmount);
        
        // Both ways produce the same result
        assertEq(oldWayData, newWayData, "Encoder should produce same result as manual encoding");
        
        // Verify decoder works
        uint256 decodedAmount = gaugeStrategy.decodeSetAllocationCampaignParams(newWayData);
        assertEq(decodedAmount, totalDistributionAmount, "Decoder should extract correct amount");
    }
    
    /// @notice Example: Using encoders for MerkleDistributorStrategy
    function test_MerkleStrategyEncoderUsage() public {
        // Test creation params
        bytes32 merkleRoot = keccak256("test-merkle-root");
        
        // OLD WAY: Manual encoding
        bytes memory oldWayData = abi.encode(merkleRoot);
        
        // NEW WAY: Using encoder function
        bytes memory newWayData = merkleStrategy.encodeSetAllocationCampaignParams(merkleRoot);
        
        assertEq(oldWayData, newWayData, "Encoder should produce same result as manual encoding");
        
        // Test claim params
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = keccak256("proof1");
        proof[1] = keccak256("proof2");
        uint256 claimAmount = 100 ether;
        
        // OLD WAY: Manual encoding
        bytes memory oldWayClaimData = abi.encode(proof, claimAmount);
        
        // NEW WAY: Using encoder function
        bytes memory newWayClaimData = merkleStrategy.encodeClaimParams(proof, claimAmount);
        
        assertEq(oldWayClaimData, newWayClaimData, "Claim encoder should produce same result");
        
        // Verify decoder works
        (bytes32[] memory decodedProof, uint256 decodedAmount) = merkleStrategy.decodeClaimParams(newWayClaimData);
        assertEq(decodedProof.length, proof.length, "Decoded proof should have same length");
        assertEq(decodedProof[0], proof[0], "First proof element should match");
        assertEq(decodedProof[1], proof[1], "Second proof element should match");
        assertEq(decodedAmount, claimAmount, "Decoded amount should match");
    }
    
    /// @notice Example: Type safety benefits
    function test_TypeSafetyBenefits() public {
        // With encoders, you get compile-time type checking
        // This won't compile if you pass wrong types:
        // gaugeStrategy.encodeInitializationParams(123); // ERROR: Expected IAddressGaugeVoter
        
        // With manual encoding, this would compile but fail at runtime:
        // bytes memory wrongData = abi.encode(123); // Compiles, but wrong type
        
        // The encoder pattern provides better developer experience and safety
        assertTrue(true, "Type safety demonstration");
    }
    
    /// @notice Example: Integration with factory pattern
    function test_FactoryIntegrationExample() public {
        // When deploying through a factory, you can use encoders:
        
        // 1. Prepare initialization data
        bytes memory initData = gaugeStrategy.encodeInitializationParams(IAddressGaugeVoter(mockGaugeVoter));
        
        // 2. Deploy strategy (pseudo-code, actual factory would do this)
        // factory.deployStrategy(GAUGE_STRATEGY_ID, mockDAO, initData);
        
        // 3. Create campaign
        uint256 campaignId = 1;
        bytes memory campaignData = gaugeStrategy.encodeSetAllocationCampaignParams(1000 ether);
        
        // This shows how the encoder pattern provides a clean API for consumers
        assertTrue(true, "Factory integration demonstration");
    }
}