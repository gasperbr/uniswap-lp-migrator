// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

/// @notice Utilities for mathematical conversions between Uniswap V3 and Ekubo V3
/// @notice Converts a Uniswap V3 tick to an Ekubo V3 tick
/// @dev Uniswap V3 ticks use 1.0001 as base, Ekubo V3 ticks use 1.000001 as base
/// @param uniswapTick The Uniswap V3 tick to convert
/// @param ekuboTickSpacing The Ekubo tick spacing to round to
/// @param roundUp Whether to round up (toward +infinity) or down (toward -infinity) by spacing
/// @return The converted Ekubo tick, rounded by spacing according to `roundUp`
function uniswapTickToEkuboTick(int24 uniswapTick, uint32 ekuboTickSpacing, bool roundUp) pure returns (int32) {
    // Convert from 1.0001 base to 1.000001 base using: tick_ekubo ≈ tick_uni * 99.995.
    // Keep conversion truncation toward zero; configurable rounding is applied by tick spacing below.
    int32 ekuboTick = int32(int256(uniswapTick) * 99995 / 1000);

    int32 spacing = int32(ekuboTickSpacing);
    int32 remainder = ekuboTick % spacing;
    if (remainder == 0) return ekuboTick;

    int32 towardZero = ekuboTick - remainder;
    if (roundUp) {
        // ceil to the next valid tick for the configured tick spacing
        return remainder > 0 ? towardZero + spacing : towardZero;
    }
    // floor to the previous valid tick for the configured tick spacing
    return remainder > 0 ? towardZero : towardZero - spacing;
}
