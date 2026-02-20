// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {ERC721} from "solady/tokens/ERC721.sol";

import {
    PoolConfig,
    concentratedTickSpacing,
    createConcentratedPoolConfig,
    createFullRangePoolConfig,
    createStableswapPoolConfig,
    isConcentrated,
    isFullRange,
    stableswapActiveLiquidityTickRange
} from "evm-contracts/src/types/poolConfig.sol";
import {PoolKey as EkuboPoolKey} from "evm-contracts/src/types/poolKey.sol";

import {IUniToEkuboMigrator} from "../../src/interfaces/IUniToEkuboMigrator.sol";
import {uniswapTickToEkuboTick} from "../../src/libraries/EkuboMath.sol";
import {UniToEkuboMigratorBase} from "./UniToEkuboMigratorBase.t.sol";
import {MigratorTestConstants as C} from "./constants.sol";

import {
    PositionInfo as UniV4PositionInfo,
    PositionInfoLibrary as UniV4PositionInfoLibrary
} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {IPoolManager as IUniV4PoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary as UniV4StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Currency as UniV4Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolIdLibrary as UniV4PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey as UniV4PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

contract UniV4ToEkuboMigratorLocalTest is UniToEkuboMigratorBase {
    using UniV4PositionInfoLibrary for UniV4PositionInfo;
    using UniV4PoolIdLibrary for UniV4PoolKey;
    using UniV4StateLibrary for IUniV4PoolManager;

    uint32 internal constant STABLE_MATCH_MAX_TICK_DELTA = 1_500;

    function setUp() public {
        _setUpV4LocalSuite();
    }

    struct ExpectedEkuboPosition {
        EkuboPoolKey poolKey;
        int32 tickLower;
        int32 tickUpper;
    }

    function testMigrateTokenToken_InRange_ToConcentrated() public {
        uint256 uniV4TokenId = uniV4ScenarioPositions.tokenTokenInRange;
        uint128 uniLiquidityBefore = _uniV4PositionLiquidity(uniV4TokenId);
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV4TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV4Position(uniV4TokenId, poolConfig);

        _assertTokenTokenPool(expected.poolKey);
        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenToken_BelowSpot_ToConcentrated() public {
        uint256 uniV4TokenId = uniV4ScenarioPositions.tokenTokenBelowSpot;
        uint128 uniLiquidityBefore = _uniV4PositionLiquidity(uniV4TokenId);
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV4TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV4Position(uniV4TokenId, poolConfig);

        _assertTokenTokenPool(expected.poolKey);
        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenToken_AboveSpot_ToConcentrated() public {
        uint256 uniV4TokenId = uniV4ScenarioPositions.tokenTokenAboveSpot;
        uint128 uniLiquidityBefore = _uniV4PositionLiquidity(uniV4TokenId);
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV4TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV4Position(uniV4TokenId, poolConfig);

        _assertTokenTokenPool(expected.poolKey);
        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenToken_FullRange_ToConcentrated() public {
        uint256 uniV4TokenId = uniV4ScenarioPositions.tokenTokenFullRange;
        uint128 uniLiquidityBefore = _uniV4PositionLiquidity(uniV4TokenId);
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV4TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV4Position(uniV4TokenId, poolConfig);

        _assertTokenTokenPool(expected.poolKey);
        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenToken_Concentrated_WhenEkuboPriceOutOfSync_RevertsOnMinLiquidity() public {
        uint256 uniV4TokenId = uniV4ScenarioPositions.tokenTokenInRange;
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        EkuboPoolKey memory poolKey = EkuboPoolKey({
            token0: UniV4Currency.unwrap(uniV4TokenTokenPool.currency0),
            token1: UniV4Currency.unwrap(uniV4TokenTokenPool.currency1),
            config: poolConfig
        });

        ekuboPositions.maybeInitializePool(poolKey, -C.EKUBO_OUT_OF_SYNC_TICK);
        IUniToEkuboMigrator.MigrationData memory data = _migrationDataForUniV4(uniV4TokenId, poolConfig);

        vm.expectRevert();
        migrator.migrateUniV4PositionToEkubo(data);
    }

    function testMigrateTokenToken_StableMatchedRange_ToStableSwap_UsesStableRangeAndKeepsLiquidity() public {
        uint256 uniV4TokenId = uniV4ScenarioPositions.tokenTokenStableRangeMatch;
        uint128 uniLiquidityBefore = _uniV4PositionLiquidity(uniV4TokenId);
        PoolConfig poolConfig = _ekuboStableswapFee5BpsActiveRangeConfig();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV4TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV4Position(uniV4TokenId, poolConfig);

        (int32 stableLower, int32 stableUpper) = stableswapActiveLiquidityTickRange(poolConfig);
        assertEq(expected.tickLower, stableLower);
        assertEq(expected.tickUpper, stableUpper);
        _assertTokenTokenPool(expected.poolKey);

        (int32 convertedUniLower, int32 convertedUniUpper) = _convertedUniV4Bounds(uniV4TokenId);
        _assertTickDeltaLe(convertedUniLower, stableLower, STABLE_MATCH_MAX_TICK_DELTA);
        _assertTickDeltaLe(convertedUniUpper, stableUpper, STABLE_MATCH_MAX_TICK_DELTA);

        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenToken_FullRange_ToStableSwap_UsesPoolDefinedRange() public {
        uint256 uniV4TokenId = uniV4ScenarioPositions.tokenTokenFullRange;
        uint128 uniLiquidityBefore = _uniV4PositionLiquidity(uniV4TokenId);
        PoolConfig poolConfig = _ekuboStableswapFee5BpsFullRangeConfig();
        assertTrue(isFullRange(poolConfig));
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV4TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV4Position(uniV4TokenId, poolConfig);

        (int32 stableLower, int32 stableUpper) = stableswapActiveLiquidityTickRange(poolConfig);
        assertEq(expected.tickLower, stableLower);
        assertEq(expected.tickUpper, stableUpper);
        _assertTokenTokenPool(expected.poolKey);

        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenToken_Batch_ToConcentrated() public {
        uint256 uniV4TokenId0 = uniV4ScenarioPositions.tokenTokenInRange;
        uint256 uniV4TokenId1 = uniV4ScenarioPositions.tokenTokenBelowSpot;

        uint128 uniLiquidityBefore0 = _uniV4PositionLiquidity(uniV4TokenId0);
        uint128 uniLiquidityBefore1 = _uniV4PositionLiquidity(uniV4TokenId1);

        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected0 = _expectedEkuboPosition(uniV4TokenId0, poolConfig);
        ExpectedEkuboPosition memory expected1 = _expectedEkuboPosition(uniV4TokenId1, poolConfig);

        IUniToEkuboMigrator.MigrationData[] memory data = new IUniToEkuboMigrator.MigrationData[](2);
        data[0] = _migrationDataForUniV4(uniV4TokenId0, poolConfig);
        data[1] = _migrationDataForUniV4(uniV4TokenId1, poolConfig);

        uint256[] memory ekuboTokenIds = migrator.migrateUniV4PositionsToEkubo(data);

        assertEq(ekuboTokenIds.length, 2);

        uint128 ekuboLiquidity0 = _assertEkuboPositionMintedWithLiquidity(ekuboTokenIds[0], expected0);
        uint128 ekuboLiquidity1 = _assertEkuboPositionMintedWithLiquidity(ekuboTokenIds[1], expected1);

        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore0, ekuboLiquidity0);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore1, ekuboLiquidity1);
        _assertMigratorNoDustV4();
    }

    function testMigrateTokenToken_NonOwnerSingle_Reverts() public {
        uint256 uniV4TokenId = uniV4ScenarioPositions.tokenTokenInRange;
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        IUniToEkuboMigrator.MigrationData memory data = _migrationDataForUniV4(uniV4TokenId, poolConfig);
        address attacker = makeAddr("v4-non-owner");

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(IUniToEkuboMigrator.NotNftOwner.selector, attacker, address(this), uniV4TokenId)
        );
        migrator.migrateUniV4PositionToEkubo(data);
    }

    function testMigrateTokenToken_NonOwnerBatch_Reverts() public {
        uint256 uniV4TokenId0 = uniV4ScenarioPositions.tokenTokenInRange;
        uint256 uniV4TokenId1 = uniV4ScenarioPositions.tokenTokenBelowSpot;
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        IUniToEkuboMigrator.MigrationData[] memory data = new IUniToEkuboMigrator.MigrationData[](2);
        data[0] = _migrationDataForUniV4(uniV4TokenId0, poolConfig);
        data[1] = _migrationDataForUniV4(uniV4TokenId1, poolConfig);
        address attacker = makeAddr("v4-batch-non-owner");

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(IUniToEkuboMigrator.NotNftOwner.selector, attacker, address(this), uniV4TokenId0)
        );
        migrator.migrateUniV4PositionsToEkubo(data);
    }

    function _expectedEkuboPosition(uint256 uniV4TokenId, PoolConfig poolConfig)
        internal
        view
        returns (ExpectedEkuboPosition memory expected)
    {
        (UniV4PoolKey memory uniPoolKey, UniV4PositionInfo info) =
            uniV4PositionManager.getPoolAndPositionInfo(uniV4TokenId);

        if (isConcentrated(poolConfig)) {
            uint32 spacing = concentratedTickSpacing(poolConfig);
            expected.tickLower = uniswapTickToEkuboTick(info.tickLower(), spacing, false);
            expected.tickUpper = uniswapTickToEkuboTick(info.tickUpper(), spacing, true);
        } else {
            (expected.tickLower, expected.tickUpper) = stableswapActiveLiquidityTickRange(poolConfig);
        }

        expected.poolKey = EkuboPoolKey({
            token0: UniV4Currency.unwrap(uniPoolKey.currency0),
            token1: UniV4Currency.unwrap(uniPoolKey.currency1),
            config: poolConfig
        });
    }

    function _assertEkuboPositionMintedWithLiquidity(uint256 ekuboTokenId, ExpectedEkuboPosition memory expected)
        internal
        view
        returns (uint128 liquidity)
    {
        assertEq(ERC721(address(ekuboPositions)).ownerOf(ekuboTokenId), address(this));
        (liquidity,,,,) = ekuboPositions.getPositionFeesAndLiquidity(
            ekuboTokenId, expected.poolKey, expected.tickLower, expected.tickUpper
        );
        assertGt(liquidity, 0);
    }

    function _uniV4PositionLiquidity(uint256 uniV4TokenId) internal view returns (uint128 liquidity) {
        liquidity = uniV4PositionManager.getPositionLiquidity(uniV4TokenId);
        assertGt(liquidity, 0);
    }

    function _convertedUniV4Bounds(uint256 uniV4TokenId) internal view returns (int32 lower, int32 upper) {
        (, UniV4PositionInfo info) = uniV4PositionManager.getPoolAndPositionInfo(uniV4TokenId);
        lower = uniswapTickToEkuboTick(info.tickLower(), 1, false);
        upper = uniswapTickToEkuboTick(info.tickUpper(), 1, true);
    }

    function _assertTokenTokenPool(EkuboPoolKey memory poolKey) internal view {
        assertEq(poolKey.token0, UniV4Currency.unwrap(uniV4TokenTokenPool.currency0));
        assertEq(poolKey.token1, UniV4Currency.unwrap(uniV4TokenTokenPool.currency1));
    }

    function _assertTickDeltaLe(int32 lhs, int32 rhs, uint32 maxDelta) internal pure {
        uint256 delta = lhs >= rhs ? uint256(uint32(lhs - rhs)) : uint256(uint32(rhs - lhs));
        assertLe(delta, maxDelta);
    }

    function _assertLiquidityRetentionWithinOnePercent(uint128 sourceLiquidity, uint128 ekuboLiquidity) internal pure {
        uint256 source = uint256(sourceLiquidity);
        uint256 ekubo = uint256(ekuboLiquidity);

        // Require at least 99% retention using exact integer math.
        assertGe(ekubo * 100, source * 99, "ekubo liquidity below 99% retention floor");
        // Floor division intentionally tolerates tiny >100% rounding artifacts.
        assertLe((ekubo * 100) / source, 100, "ekubo liquidity above 100% retention ceiling");
    }

    function _ekuboConcentratedFee5BpsSpacing100Config() internal pure returns (PoolConfig) {
        return createConcentratedPoolConfig(C.EKUBO_FEE, C.EKUBO_TICK_SPACING, address(0));
    }

    function _ekuboStableswapFee5BpsActiveRangeConfig() internal pure returns (PoolConfig) {
        return createStableswapPoolConfig(
            C.EKUBO_FEE, C.EKUBO_STABLE_ACTIVE_RANGE_AMP, C.EKUBO_STABLE_ACTIVE_RANGE_CENTER_TICK, address(0)
        );
    }

    function _ekuboStableswapFee5BpsFullRangeConfig() internal pure returns (PoolConfig) {
        return createFullRangePoolConfig(C.EKUBO_FEE, address(0));
    }
}
