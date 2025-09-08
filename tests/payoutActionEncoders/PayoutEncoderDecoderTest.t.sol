// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { VaultDepositPayoutActionEncoder } from "../../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";

/// @title PayoutEncoderDecoderTest
/// @notice Comprehensive tests for encoder/decoder functions in payout action encoders
contract PayoutEncoderDecoderTest is Test {
    VaultDepositPayoutActionEncoder vaultEncoder;

    function setUp() public {
        vaultEncoder = new VaultDepositPayoutActionEncoder();
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
}
