// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.8;

/// @title RatioUtils
/// @author AragonX - 2025
/// @notice A library for handling ratio calculations with proper precision
/// @dev Provides utilities for applying ratios to values with explicit ceiling/flooring
library RatioUtils {
    /// @notice The base value for basis points calculations (100% = 10,000 basis points).
    uint256 public constant BASIS_POINTS_BASE = 10_000;

    /// @notice Thrown if a ratio value exceeds the maximal value.
    /// @param limit The maximal value.
    /// @param actual The actual value.
    error RatioOutOfBounds(uint256 limit, uint256 actual);

    /// @notice Applies basis points to a value and ceils the remainder.
    /// @param _value The value to which the basis points are applied.
    /// @param _basisPoints The basis points that must be in the interval `[0, BASIS_POINTS_BASE]`.
    /// @return result The resulting value.
    /// @custom:security-contact sirt@aragon.org
    function applyBasisPointsCeiled(uint256 _value, uint256 _basisPoints) internal pure returns (uint256 result) {
        if (_basisPoints > BASIS_POINTS_BASE) {
            revert RatioOutOfBounds({ limit: BASIS_POINTS_BASE, actual: _basisPoints });
        }

        _value = _value * _basisPoints;
        uint256 remainder = _value % BASIS_POINTS_BASE;
        result = _value / BASIS_POINTS_BASE;

        // Check if ceiling is needed
        if (remainder != 0) {
            ++result;
        }
    }
}
