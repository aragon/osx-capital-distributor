// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { VaultDepositPayoutActionEncoder } from "../../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";
import { SablierLinearPayoutActionEncoder } from "../../src/payoutActionEncoders/SablierLinearPayoutActionEncoder.sol";

/// @title PayoutEncoderDecoderTest
/// @notice Comprehensive tests for encoder/decoder functions in payout action encoders
contract PayoutEncoderDecoderTest is Test {
    VaultDepositPayoutActionEncoder vaultEncoder;
    SablierLinearPayoutActionEncoder sablierEncoder;
    
    function setUp() public {
        vaultEncoder = new VaultDepositPayoutActionEncoder();
        sablierEncoder = new SablierLinearPayoutActionEncoder();
    }
    
    // ============================================
    // VaultDepositPayoutActionEncoder Tests
    // ============================================
    
    /// @notice Test encoding/decoding of vault address for setup campaign
    function test_VaultEncoder_SetupCampaignParams() public {
        address vaultAddress = makeAddr("vault");
        
        // Encode
        bytes memory encoded = vaultEncoder.encodeSetupCampaignParams(vaultAddress);
        
        // Decode
        address decoded = vaultEncoder.decodeSetupCampaignParams(encoded);
        
        assertEq(decoded, vaultAddress, "Decoded vault address should match original");
    }
    
    /// @notice Test that zero address encodes/decodes correctly
    function test_VaultEncoder_ZeroAddress() public {
        address zeroAddr = address(0);
        
        bytes memory encoded = vaultEncoder.encodeSetupCampaignParams(zeroAddr);
        address decoded = vaultEncoder.decodeSetupCampaignParams(encoded);
        
        assertEq(decoded, zeroAddr, "Zero address should encode/decode correctly");
    }
    
    /// @notice Fuzz test for vault encoder
    function testFuzz_VaultEncoder_SetupCampaignParams(address vaultAddress) public {
        bytes memory encoded = vaultEncoder.encodeSetupCampaignParams(vaultAddress);
        address decoded = vaultEncoder.decodeSetupCampaignParams(encoded);
        
        assertEq(decoded, vaultAddress, "Fuzz: decoded address should match original");
    }
    
    // ============================================
    // SablierLinearPayoutActionEncoder Tests  
    // ============================================
    
    /// @notice Test encoding/decoding of stream config
    function test_SablierEncoder_SetupCampaignParams() public {
        SablierLinearPayoutActionEncoder.StreamConfig memory config = SablierLinearPayoutActionEncoder.StreamConfig({
            sablierContract: makeAddr("sablier"),
            streamDuration: 30 days,
            cliffDuration: 7 days,
            unlockAmountAtStart: 100 ether,
            unlockAmountAtCliff: 200 ether,
            cancelable: true,
            transferable: false,
            brokerAccount: makeAddr("broker"),
            brokerFee: 250 // 2.5%
        });
        
        // Encode
        bytes memory encoded = sablierEncoder.encodeSetupCampaignParams(config);
        
        // Decode
        SablierLinearPayoutActionEncoder.StreamConfig memory decoded = 
            sablierEncoder.decodeSetupCampaignParams(encoded);
        
        // Verify all fields
        assertEq(decoded.sablierContract, config.sablierContract, "Sablier contract should match");
        assertEq(decoded.streamDuration, config.streamDuration, "Stream duration should match");
        assertEq(decoded.cliffDuration, config.cliffDuration, "Cliff duration should match");
        assertEq(decoded.unlockAmountAtStart, config.unlockAmountAtStart, "Start unlock should match");
        assertEq(decoded.unlockAmountAtCliff, config.unlockAmountAtCliff, "Cliff unlock should match");
        assertEq(decoded.cancelable, config.cancelable, "Cancelable flag should match");
        assertEq(decoded.transferable, config.transferable, "Transferable flag should match");
        assertEq(decoded.brokerAccount, config.brokerAccount, "Broker account should match");
        assertEq(decoded.brokerFee, config.brokerFee, "Broker fee should match");
    }
    
    /// @notice Test edge cases for stream config
    function test_SablierEncoder_EdgeCases() public {
        // Test with all zero/false values
        SablierLinearPayoutActionEncoder.StreamConfig memory zeroConfig = SablierLinearPayoutActionEncoder.StreamConfig({
            sablierContract: address(0),
            streamDuration: 0,
            cliffDuration: 0,
            unlockAmountAtStart: 0,
            unlockAmountAtCliff: 0,
            cancelable: false,
            transferable: false,
            brokerAccount: address(0),
            brokerFee: 0
        });
        
        bytes memory encoded = sablierEncoder.encodeSetupCampaignParams(zeroConfig);
        SablierLinearPayoutActionEncoder.StreamConfig memory decoded = 
            sablierEncoder.decodeSetupCampaignParams(encoded);
        
        assertEq(decoded.sablierContract, address(0), "Zero address should work");
        assertEq(decoded.streamDuration, 0, "Zero duration should work");
        assertEq(decoded.brokerFee, 0, "Zero fee should work");
    }
    
    /// @notice Test with maximum values
    function test_SablierEncoder_MaxValues() public {
        SablierLinearPayoutActionEncoder.StreamConfig memory maxConfig = SablierLinearPayoutActionEncoder.StreamConfig({
            sablierContract: address(type(uint160).max),
            streamDuration: type(uint40).max,
            cliffDuration: type(uint40).max,
            unlockAmountAtStart: type(uint128).max,
            unlockAmountAtCliff: type(uint128).max,
            cancelable: true,
            transferable: true,
            brokerAccount: address(type(uint160).max),
            brokerFee: type(uint256).max
        });
        
        bytes memory encoded = sablierEncoder.encodeSetupCampaignParams(maxConfig);
        SablierLinearPayoutActionEncoder.StreamConfig memory decoded = 
            sablierEncoder.decodeSetupCampaignParams(encoded);
        
        assertEq(decoded.streamDuration, type(uint40).max, "Max duration should work");
        assertEq(decoded.unlockAmountAtStart, type(uint128).max, "Max unlock amount should work");
        assertEq(decoded.brokerFee, type(uint256).max, "Max fee should work");
    }
    
    /// @notice Fuzz test for stream config
    function testFuzz_SablierEncoder_SetupCampaignParams(
        address sablierContract,
        uint40 streamDuration,
        uint40 cliffDuration,
        uint128 unlockStart,
        uint128 unlockCliff,
        bool cancelable,
        bool transferable,
        address broker,
        uint256 fee
    ) public {
        SablierLinearPayoutActionEncoder.StreamConfig memory config = SablierLinearPayoutActionEncoder.StreamConfig({
            sablierContract: sablierContract,
            streamDuration: streamDuration,
            cliffDuration: cliffDuration,
            unlockAmountAtStart: unlockStart,
            unlockAmountAtCliff: unlockCliff,
            cancelable: cancelable,
            transferable: transferable,
            brokerAccount: broker,
            brokerFee: fee
        });
        
        bytes memory encoded = sablierEncoder.encodeSetupCampaignParams(config);
        SablierLinearPayoutActionEncoder.StreamConfig memory decoded = 
            sablierEncoder.decodeSetupCampaignParams(encoded);
        
        assertEq(decoded.sablierContract, config.sablierContract, "Fuzz: sablier contract");
        assertEq(decoded.streamDuration, config.streamDuration, "Fuzz: stream duration");
        assertEq(decoded.cliffDuration, config.cliffDuration, "Fuzz: cliff duration");
        assertEq(decoded.unlockAmountAtStart, config.unlockAmountAtStart, "Fuzz: start unlock");
        assertEq(decoded.unlockAmountAtCliff, config.unlockAmountAtCliff, "Fuzz: cliff unlock");
        assertEq(decoded.cancelable, config.cancelable, "Fuzz: cancelable");
        assertEq(decoded.transferable, config.transferable, "Fuzz: transferable");
        assertEq(decoded.brokerAccount, config.brokerAccount, "Fuzz: broker");
        assertEq(decoded.brokerFee, config.brokerFee, "Fuzz: fee");
    }
    
    // ============================================
    // Cross-compatibility Tests
    // ============================================
    
    /// @notice Test that manual encoding produces same result as encoder functions
    function test_ManualEncodingCompatibility() public {
        // Test VaultDepositPayoutActionEncoder
        address vault = makeAddr("compat-vault");
        bytes memory manualEncoded = abi.encode(vault);
        bytes memory functionEncoded = vaultEncoder.encodeSetupCampaignParams(vault);
        assertEq(manualEncoded, functionEncoded, "Manual and function encoding should match for vault");
        
        // Test SablierLinearPayoutActionEncoder
        SablierLinearPayoutActionEncoder.StreamConfig memory config = SablierLinearPayoutActionEncoder.StreamConfig({
            sablierContract: makeAddr("sablier-compat"),
            streamDuration: 100,
            cliffDuration: 10,
            unlockAmountAtStart: 50,
            unlockAmountAtCliff: 150,
            cancelable: true,
            transferable: false,
            brokerAccount: makeAddr("broker-compat"),
            brokerFee: 100
        });
        
        manualEncoded = abi.encode(config);
        functionEncoded = sablierEncoder.encodeSetupCampaignParams(config);
        assertEq(manualEncoded, functionEncoded, "Manual and function encoding should match for sablier");
    }
}