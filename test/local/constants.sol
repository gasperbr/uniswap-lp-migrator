// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

library MigratorTestConstants {
    uint24 internal constant UNI_V3_FEE = 3_000;
    uint160 internal constant UNI_V3_INITIAL_SQRT_PRICE_X96 = 79228162514264337593543950336;
    uint160 internal constant UNI_V3_MIN_SQRT_RATIO_PLUS_ONE = 4295128740;
    uint160 internal constant UNI_V3_MAX_SQRT_RATIO_MINUS_ONE = 1461446703485210103287273052203988822378723970341;

    int24 internal constant UNI_V3_TICK_LOWER_ACTIVE = -600;
    int24 internal constant UNI_V3_TICK_UPPER_ACTIVE = 600;
    int24 internal constant UNI_V3_TICK_LOWER_BELOW_SPOT = -1200;
    int24 internal constant UNI_V3_TICK_UPPER_BELOW_SPOT = -600;
    int24 internal constant UNI_V3_TICK_LOWER_ABOVE_SPOT = 600;
    int24 internal constant UNI_V3_TICK_UPPER_ABOVE_SPOT = 1200;
    int24 internal constant UNI_V3_TICK_LOWER_FULL_RANGE = -887220;
    int24 internal constant UNI_V3_TICK_UPPER_FULL_RANGE = 887220;
    int24 internal constant UNI_V3_TICK_LOWER_STABLE_MATCH = -60;
    int24 internal constant UNI_V3_TICK_UPPER_STABLE_MATCH = 60;

    uint256 internal constant UNI_V3_POSITION_AMOUNT = 10 ether;
    uint256 internal constant UNI_V3_FEE_ACCRUAL_SWAP_AMOUNT = 1e16;
    uint24 internal constant UNI_V4_FEE = 3_000;
    uint128 internal constant UNI_V4_POSITION_LIQUIDITY = 1_000 ether;

    uint64 internal constant EKUBO_FEE = uint64(9223372036854775); // 0.05%
    uint32 internal constant EKUBO_TICK_SPACING = 100;
    uint8 internal constant EKUBO_STABLE_ACTIVE_RANGE_AMP = 14;
    int32 internal constant EKUBO_STABLE_ACTIVE_RANGE_CENTER_TICK = 592;
    int32 internal constant EKUBO_OUT_OF_SYNC_TICK = 10_000_000;

    struct ScenarioPools {
        address tokenToken;
        address wethToken;
        address tokenWeth;
        address ethToken;
    }

    struct ScenarioPositions {
        uint256 tokenTokenInRange;
        uint256 tokenTokenBelowSpot;
        uint256 tokenTokenAboveSpot;
        uint256 tokenTokenFullRange;
        uint256 tokenTokenStableRangeMatch;
        uint256 tokenTokenInRangeWithFees;
        uint256 wethTokenInRangeWithFees;
        uint256 tokenWethInRangeWithFees;
        uint256 ethTokenInRangeWithFees;
    }

    struct UniV4ScenarioPositions {
        uint256 tokenTokenInRange;
        uint256 tokenTokenBelowSpot;
        uint256 tokenTokenAboveSpot;
        uint256 tokenTokenFullRange;
        uint256 tokenTokenStableRangeMatch;
    }
}
