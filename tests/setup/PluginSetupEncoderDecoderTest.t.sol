// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { CapitalDistributorPluginSetup } from "../../src/CapitalDistributorPluginSetup.sol";
import { AllocatorStrategyFactory } from "../../src/factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../../src/factories/ActionEncoderFactory.sol";

/// @title PluginSetupEncoderDecoderTest
/// @notice Tests for encoder/decoder functions in CapitalDistributorPluginSetup
contract PluginSetupEncoderDecoderTest is Test {
    CapitalDistributorPluginSetup pluginSetup;

    address mockStrategyFactory;
    address mockEncoderFactory;

    function setUp() public {
        pluginSetup = new CapitalDistributorPluginSetup();
        mockStrategyFactory = makeAddr("strategyFactory");
        mockEncoderFactory = makeAddr("encoderFactory");
    }

    /// @notice Test encoding/decoding of installation parameters
    function test_InstallationParams() public {
        // Encode
        bytes memory encoded = pluginSetup.encodeInstallationParams(mockStrategyFactory, mockEncoderFactory);

        // Decode
        (AllocatorStrategyFactory strategies, ActionEncoderFactory encoders) =
            pluginSetup.decodeInstallationParams(encoded);

        assertEq(address(strategies), mockStrategyFactory, "Strategy factory should match");
        assertEq(address(encoders), mockEncoderFactory, "Encoder factory should match");
    }

    /// @notice Test with zero addresses
    function test_InstallationParams_ZeroAddresses() public {
        // Test with both zero
        bytes memory encoded = pluginSetup.encodeInstallationParams(address(0), address(0));
        (AllocatorStrategyFactory strategies, ActionEncoderFactory encoders) =
            pluginSetup.decodeInstallationParams(encoded);

        assertEq(address(strategies), address(0), "Zero strategy factory should decode");
        assertEq(address(encoders), address(0), "Zero encoder factory should decode");

        // Test with one zero
        encoded = pluginSetup.encodeInstallationParams(mockStrategyFactory, address(0));
        (strategies, encoders) = pluginSetup.decodeInstallationParams(encoded);

        assertEq(address(strategies), mockStrategyFactory, "Non-zero strategy factory should decode");
        assertEq(address(encoders), address(0), "Zero encoder factory should decode");
    }

    /// @notice Fuzz test for installation parameters
    function testFuzz_InstallationParams(address strategyFactory, address encoderFactory) public {
        bytes memory encoded = pluginSetup.encodeInstallationParams(strategyFactory, encoderFactory);
        (AllocatorStrategyFactory strategies, ActionEncoderFactory encoders) =
            pluginSetup.decodeInstallationParams(encoded);

        assertEq(address(strategies), strategyFactory, "Fuzz: strategy factory should match");
        assertEq(address(encoders), encoderFactory, "Fuzz: encoder factory should match");
    }

    /// @notice Test that manual encoding produces same result
    function test_ManualEncodingCompatibility() public {
        bytes memory manualEncoded = abi.encode(mockStrategyFactory, mockEncoderFactory);
        bytes memory functionEncoded = pluginSetup.encodeInstallationParams(mockStrategyFactory, mockEncoderFactory);

        assertEq(manualEncoded, functionEncoded, "Manual and function encoding should match");
    }

    /// @notice Test edge case with max addresses
    function test_MaxAddresses() public {
        address maxAddr = address(type(uint160).max);

        bytes memory encoded = pluginSetup.encodeInstallationParams(maxAddr, maxAddr);
        (AllocatorStrategyFactory strategies, ActionEncoderFactory encoders) =
            pluginSetup.decodeInstallationParams(encoded);

        assertEq(address(strategies), maxAddr, "Max address should encode/decode for strategies");
        assertEq(address(encoders), maxAddr, "Max address should encode/decode for encoders");
    }
}
