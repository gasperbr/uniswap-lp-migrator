// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {ERC721} from "solady/tokens/ERC721.sol";

import {NATIVE_TOKEN_ADDRESS} from "evm-contracts/src/math/constants.sol";
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
import {PoolKey} from "evm-contracts/src/types/poolKey.sol";

import {IUniToEkuboMigrator} from "../../src/interfaces/IUniToEkuboMigrator.sol";
import {uniswapTickToEkuboTick} from "../../src/libraries/EkuboMath.sol";
import {UniToEkuboMigratorBase} from "./UniToEkuboMigratorBase.t.sol";
import {MigratorTestConstants as C} from "./constants.sol";

contract UniV3ToEkuboMigratorLocalTest is UniToEkuboMigratorBase {
    uint32 internal constant STABLE_MATCH_MAX_TICK_DELTA = 1_500;

    function setUp() public {
        _setUpV3LocalSuite();
    }

    struct ExpectedEkuboPosition {
        PoolKey poolKey;
        int32 tickLower;
        int32 tickUpper;
    }

    function testMigrateTokenToken_InRange_ToConcentrated() public {
        uint256 uniV3TokenId = scenarioPositions.tokenTokenInRange;
        uint128 uniLiquidityBefore = _uniV3PositionLiquidity(uniV3TokenId);
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV3TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV3Position(uniV3TokenId, poolConfig);

        assertEq(expected.poolKey.token0, address(baseToken));
        assertEq(expected.poolKey.token1, address(quoteToken));
        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenToken_BelowSpot_ToConcentrated() public {
        uint256 uniV3TokenId = scenarioPositions.tokenTokenBelowSpot;
        uint128 uniLiquidityBefore = _uniV3PositionLiquidity(uniV3TokenId);
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV3TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV3Position(uniV3TokenId, poolConfig);

        assertEq(expected.poolKey.token0, address(baseToken));
        assertEq(expected.poolKey.token1, address(quoteToken));
        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenToken_AboveSpot_ToConcentrated() public {
        uint256 uniV3TokenId = scenarioPositions.tokenTokenAboveSpot;
        uint128 uniLiquidityBefore = _uniV3PositionLiquidity(uniV3TokenId);
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV3TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV3Position(uniV3TokenId, poolConfig);

        assertEq(expected.poolKey.token0, address(baseToken));
        assertEq(expected.poolKey.token1, address(quoteToken));
        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenToken_FullRange_ToConcentrated() public {
        uint256 uniV3TokenId = scenarioPositions.tokenTokenFullRange;
        uint128 uniLiquidityBefore = _uniV3PositionLiquidity(uniV3TokenId);
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV3TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV3Position(uniV3TokenId, poolConfig);

        assertEq(expected.poolKey.token0, address(baseToken));
        assertEq(expected.poolKey.token1, address(quoteToken));
        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenToken_Batch_ToConcentrated() public {
        uint256 uniV3TokenId0 = scenarioPositions.tokenTokenInRange;
        uint256 uniV3TokenId1 = scenarioPositions.tokenTokenBelowSpot;

        uint128 uniLiquidityBefore0 = _uniV3PositionLiquidity(uniV3TokenId0);
        uint128 uniLiquidityBefore1 = _uniV3PositionLiquidity(uniV3TokenId1);

        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected0 = _expectedEkuboPosition(uniV3TokenId0, poolConfig);
        ExpectedEkuboPosition memory expected1 = _expectedEkuboPosition(uniV3TokenId1, poolConfig);

        IUniToEkuboMigrator.MigrationData[] memory data = new IUniToEkuboMigrator.MigrationData[](2);
        data[0] = _migrationDataForUniV3(uniV3TokenId0, poolConfig);
        data[1] = _migrationDataForUniV3(uniV3TokenId1, poolConfig);

        uint256[] memory ekuboTokenIds = migrator.migrateUniV3PositionsToEkubo(data);

        assertEq(ekuboTokenIds.length, 2);

        uint128 ekuboLiquidity0 = _assertEkuboPositionMintedWithLiquidity(ekuboTokenIds[0], expected0);
        uint128 ekuboLiquidity1 = _assertEkuboPositionMintedWithLiquidity(ekuboTokenIds[1], expected1);

        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore0, ekuboLiquidity0);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore1, ekuboLiquidity1);
        _assertMigratorNoDustV3();
    }

    function testMigrateTokenToken_NonOwnerSingle_Reverts() public {
        uint256 uniV3TokenId = scenarioPositions.tokenTokenInRange;
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        IUniToEkuboMigrator.MigrationData memory data = _migrationDataForUniV3(uniV3TokenId, poolConfig);
        address attacker = makeAddr("v3-non-owner");

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(IUniToEkuboMigrator.NotNftOwner.selector, attacker, address(this), uniV3TokenId)
        );
        migrator.migrateUniV3PositionToEkubo(data);
    }

    function testMigrateTokenToken_NonOwnerBatch_Reverts() public {
        uint256 uniV3TokenId0 = scenarioPositions.tokenTokenInRange;
        uint256 uniV3TokenId1 = scenarioPositions.tokenTokenBelowSpot;
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        IUniToEkuboMigrator.MigrationData[] memory data = new IUniToEkuboMigrator.MigrationData[](2);
        data[0] = _migrationDataForUniV3(uniV3TokenId0, poolConfig);
        data[1] = _migrationDataForUniV3(uniV3TokenId1, poolConfig);
        address attacker = makeAddr("v3-batch-non-owner");

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(IUniToEkuboMigrator.NotNftOwner.selector, attacker, address(this), uniV3TokenId0)
        );
        migrator.migrateUniV3PositionsToEkubo(data);
    }

    function testMigrateTokenToken_StableMatchedRange_ToStableSwap_UsesStableRangeAndKeepsLiquidity() public {
        uint256 uniV3TokenId = scenarioPositions.tokenTokenStableRangeMatch;
        uint128 uniLiquidityBefore = _uniV3PositionLiquidity(uniV3TokenId);
        PoolConfig poolConfig = _ekuboStableswapFee5BpsActiveRangeConfig();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV3TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV3Position(uniV3TokenId, poolConfig);

        (int32 stableLower, int32 stableUpper) = stableswapActiveLiquidityTickRange(poolConfig);
        assertEq(expected.tickLower, stableLower);
        assertEq(expected.tickUpper, stableUpper);
        assertEq(expected.poolKey.token0, address(baseToken));
        assertEq(expected.poolKey.token1, address(quoteToken));

        (int32 convertedUniLower, int32 convertedUniUpper) = _convertedUniV3Bounds(uniV3TokenId);
        _assertTickDeltaLe(convertedUniLower, stableLower, STABLE_MATCH_MAX_TICK_DELTA);
        _assertTickDeltaLe(convertedUniUpper, stableUpper, STABLE_MATCH_MAX_TICK_DELTA);

        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenToken_FullRange_ToStableSwap_UsesPoolDefinedRange() public {
        uint256 uniV3TokenId = scenarioPositions.tokenTokenFullRange;
        uint128 uniLiquidityBefore = _uniV3PositionLiquidity(uniV3TokenId);
        PoolConfig poolConfig = _ekuboStableswapFee5BpsFullRangeConfig();
        assertTrue(isFullRange(poolConfig));
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV3TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV3Position(uniV3TokenId, poolConfig);

        (int32 stableLower, int32 stableUpper) = stableswapActiveLiquidityTickRange(poolConfig);
        assertEq(expected.tickLower, stableLower);
        assertEq(expected.tickUpper, stableUpper);
        assertEq(expected.poolKey.token0, address(baseToken));
        assertEq(expected.poolKey.token1, address(quoteToken));

        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenToken_WithAccruedFees_ToConcentrated() public {
        uint256 uniV3TokenId = scenarioPositions.tokenTokenInRangeWithFees;
        uint128 uniLiquidityBefore = _uniV3PositionLiquidity(uniV3TokenId);
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV3TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV3Position(uniV3TokenId, poolConfig);

        assertEq(expected.poolKey.token0, address(baseToken));
        assertEq(expected.poolKey.token1, address(quoteToken));
        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenToken_Concentrated_WhenEkuboPriceOutOfSync_RevertsOnMinLiquidity() public {
        uint256 uniV3TokenId = scenarioPositions.tokenTokenInRange;
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        PoolKey memory poolKey = PoolKey({token0: address(baseToken), token1: address(quoteToken), config: poolConfig});

        ekuboPositions.maybeInitializePool(poolKey, -C.EKUBO_OUT_OF_SYNC_TICK);
        IUniToEkuboMigrator.MigrationData memory data = _migrationDataForUniV3(uniV3TokenId, poolConfig);

        vm.expectRevert();
        migrator.migrateUniV3PositionToEkubo(data);
    }

    function testMigrateWethToken_WithAccruedFees_MapsToNativePair() public {
        uint256 uniV3TokenId = scenarioPositions.wethTokenInRangeWithFees;
        uint128 uniLiquidityBefore = _uniV3PositionLiquidity(uniV3TokenId);
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV3TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV3Position(uniV3TokenId, poolConfig);

        assertEq(expected.poolKey.token0, NATIVE_TOKEN_ADDRESS);
        assertEq(expected.poolKey.token1, address(tokenAboveWeth));
        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateTokenWeth_WithAccruedFees_MapsToNativePair() public {
        uint256 uniV3TokenId = scenarioPositions.tokenWethInRangeWithFees;
        uint128 uniLiquidityBefore = _uniV3PositionLiquidity(uniV3TokenId);
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV3TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV3Position(uniV3TokenId, poolConfig);

        assertEq(expected.poolKey.token0, NATIVE_TOKEN_ADDRESS);
        assertEq(expected.poolKey.token1, address(tokenBelowWeth));
        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function testMigrateEthToken_WithAccruedFees_MapsToNativePair() public {
        uint256 uniV3TokenId = scenarioPositions.ethTokenInRangeWithFees;
        uint128 uniLiquidityBefore = _uniV3PositionLiquidity(uniV3TokenId);
        PoolConfig poolConfig = _ekuboConcentratedFee5BpsSpacing100Config();
        ExpectedEkuboPosition memory expected = _expectedEkuboPosition(uniV3TokenId, poolConfig);

        uint256 ekuboTokenId = _migrateUniV3Position(uniV3TokenId, poolConfig);

        assertEq(expected.poolKey.token0, NATIVE_TOKEN_ADDRESS);
        assertEq(expected.poolKey.token1, address(quoteToken));
        uint128 ekuboLiquidity = _assertEkuboPositionMintedWithLiquidity(ekuboTokenId, expected);
        _assertLiquidityRetentionWithinOnePercent(uniLiquidityBefore, ekuboLiquidity);
    }

    function _expectedEkuboPosition(uint256 uniV3TokenId, PoolConfig poolConfig)
        internal
        view
        returns (ExpectedEkuboPosition memory expected)
    {
        (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper,,,,,) =
            uniV3PositionManager.positions(uniV3TokenId);

        address uniPool = uniV3Factory.getPool(token0, token1, fee);
        if (uniPool == address(0)) revert PoolNotInitialized();

        if (token0 == address(weth)) {
            token0 = NATIVE_TOKEN_ADDRESS;
        } else if (token1 == address(weth)) {
            token1 = token0;
            token0 = NATIVE_TOKEN_ADDRESS;
            (tickLower, tickUpper) = (-tickUpper, -tickLower);
        }

        if (isConcentrated(poolConfig)) {
            uint32 spacing = concentratedTickSpacing(poolConfig);
            expected.tickLower = uniswapTickToEkuboTick(tickLower, spacing, false);
            expected.tickUpper = uniswapTickToEkuboTick(tickUpper, spacing, true);
        } else {
            (expected.tickLower, expected.tickUpper) = stableswapActiveLiquidityTickRange(poolConfig);
        }

        expected.poolKey = PoolKey({token0: token0, token1: token1, config: poolConfig});
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

    function _uniV3PositionLiquidity(uint256 uniV3TokenId) internal view returns (uint128 liquidity) {
        (,,,,,,, liquidity,,,,) = uniV3PositionManager.positions(uniV3TokenId);
        assertGt(liquidity, 0);
    }

    function _convertedUniV3Bounds(uint256 uniV3TokenId) internal view returns (int32 lower, int32 upper) {
        (,, address token0, address token1,, int24 tickLower, int24 tickUpper,,,,,) =
            uniV3PositionManager.positions(uniV3TokenId);

        if (token1 == address(weth) && token0 != address(weth)) {
            (tickLower, tickUpper) = (-tickUpper, -tickLower);
        }

        lower = uniswapTickToEkuboTick(tickLower, 1, false);
        upper = uniswapTickToEkuboTick(tickUpper, 1, true);
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
