// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { RatioUtils } from "../../src/utils/RatioUtils.sol";

/// Need to wrap to test reverts as otherwise too high up the callstack
contract WrappedLib {
    function applyBasisPointsCeiled(uint256 _value, uint256 _basisPoints) public pure returns (uint256 result) {
        result = RatioUtils.applyBasisPointsCeiled(_value, _basisPoints);
    }
}

/// @title RatioUtilsTest
/// @notice Test suite for the RatioUtils library
contract RatioUtilsTest is Test {
    using RatioUtils for uint256;
    /// @notice Test applyBasisPointsCeiled with standard cases

    function test_ApplyBasisPointsCeiled() public pure {
        // 10% of 1001 (should ceil)
        assertEq(RatioUtils.applyBasisPointsCeiled(1001, 1000), 101); // 100.1 -> 101

        // 2.5% of 1001 (should ceil)
        assertEq(RatioUtils.applyBasisPointsCeiled(1001, 250), 26); // 25.025 -> 26

        // Exact division (no ceiling needed)
        assertEq(RatioUtils.applyBasisPointsCeiled(1000, 1000), 100);
    }

    /// @notice Test applyBasisPointsCeiled reverts when ratio exceeds limit
    function test_ApplyBasisPointsCeiled_RevertWhenExceedsLimit() public {
        WrappedLib wrappedLib = new WrappedLib();
        vm.expectRevert(abi.encodeWithSelector(RatioUtils.RatioOutOfBounds.selector, 10_000, 15_000));
        wrappedLib.applyBasisPointsCeiled(1000, 15_000);
    }

    /// @notice Fuzz test for applyBasisPointsCeiled
    function testFuzz_ApplyBasisPointsCeiled(uint256 value, uint256 basisPoints) public pure {
        // Limit inputs to reasonable ranges to avoid overflows
        value = bound(value, 0, type(uint256).max / 10_000);
        basisPoints = bound(basisPoints, 0, 10_000);

        uint256 result = RatioUtils.applyBasisPointsCeiled(value, basisPoints);

        uint256 product = value * basisPoints;
        uint256 expectedFloor = product / 10_000;
        uint256 remainder = product % 10_000;
        uint256 expectedCeiled = remainder > 0 ? expectedFloor + 1 : expectedFloor;

        assertEq(result, expectedCeiled);
    }

    /// @notice Test ceiling behavior specifically
    function test_CeilingBehavior() public pure {
        // Test various remainders
        assertEq(RatioUtils.applyBasisPointsCeiled(10_001, 100), 101); // 100.01 -> 101
        assertEq(RatioUtils.applyBasisPointsCeiled(10_000, 100), 100); // 100.00 -> 100
        assertEq(RatioUtils.applyBasisPointsCeiled(9999, 100), 100); // 99.99 -> 100

        // Test with 1 wei remainder
        assertEq(RatioUtils.applyBasisPointsCeiled(100_001, 10), 101); // 100.001 -> 101
    }

    /// @notice Test constants are correctly defined
    function test_Constants() public pure {
        assertEq(RatioUtils.BASIS_POINTS_BASE, 10_000);
    }
}
