// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {IPositions as IEkuboPositionManager} from "evm-contracts/src/interfaces/IPositions.sol";
import {
    PoolConfig as EkuboPoolConfig,
    concentratedTickSpacing as ekuboConcentratedTickSpacing,
    isConcentrated as ekuboIsConcentrated,
    stableswapActiveLiquidityTickRange as ekuboStableswapActiveLiquidityTickRange
} from "evm-contracts/src/types/poolConfig.sol";
import {PoolKey as EkuboPoolKey} from "evm-contracts/src/types/poolKey.sol";

import {ERC20} from "solady/tokens/ERC20.sol";
import {ERC721} from "solady/tokens/ERC721.sol";
import {SafeCastLib} from "lib/solady/src/utils/SafeCastLib.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";

import {INonfungiblePositionManager as IUniV3PositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {IUniToEkuboMigrator} from "./interfaces/IUniToEkuboMigrator.sol";
import {IUniswapV3Factory as IUniV3Factory} from "./interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool as IUniV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {IWeth as IWETH} from "./interfaces/IWeth.sol";

import {IPositionManager as IUniV4PositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {
    PositionInfo as UniV4PositionInfo,
    PositionInfoLibrary as UniV4PositionInfoLibrary
} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {Actions as UniV4Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IPoolManager as IUniV4PoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary as UniV4StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Currency as UniV4Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolIdLibrary as UniV4PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey as UniV4PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {uniswapTickToEkuboTick} from "./libraries/EkuboMath.sol";

/// @title Uniswap to Ekubo Position Migrator
/// @notice Migrates liquidity positions from Uniswap V3 or Uniswap V4 to Ekubo V3
contract UniToEkuboMigrator is IUniToEkuboMigrator {
    using UniV4PositionInfoLibrary for UniV4PositionInfo;
    using UniV4PoolIdLibrary for UniV4PoolKey;
    using UniV4StateLibrary for IUniV4PoolManager;

    IEkuboPositionManager public immutable ekuboPositionManager;
    IUniV3PositionManager public immutable uniV3PositionManager;
    IUniV4PositionManager public immutable uniV4PositionManager;
    IUniV3Factory public immutable uniV3PositionFactory;
    IWETH public immutable weth;

    /// @notice Constructs the migrator with Uniswap V3, Uniswap V4, and Ekubo position managers
    /// @param _uniV3PositionManager Address of Uniswap V3 NonfungiblePositionManager
    /// @param _uniV4PositionManager Address of Uniswap V4 PositionManager
    /// @param _ekuboPositionManager Address of Ekubo V3 position manager
    constructor(address _uniV3PositionManager, address payable _uniV4PositionManager, address _ekuboPositionManager) {
        ekuboPositionManager = IEkuboPositionManager(_ekuboPositionManager);
        uniV3PositionManager = IUniV3PositionManager(payable(_uniV3PositionManager));
        uniV4PositionManager = IUniV4PositionManager(_uniV4PositionManager);
        uniV3PositionFactory = IUniV3Factory(uniV3PositionManager.factory());
        weth = IWETH(payable(uniV3PositionManager.WETH9()));
    }

    modifier onlyUniV3TokenOwner(uint256 tokenId) {
        _requireUniV3TokenOwner(tokenId);
        _;
    }

    modifier onlyUniV4TokenOwner(uint256 tokenId) {
        _requireUniV4TokenOwner(tokenId);
        _;
    }

    /// @notice Migrates a single Uniswap V3 position to Ekubo.
    /// @param data Migration parameters for the source position and target Ekubo pool.
    /// @return ekuboPositionId The minted Ekubo position id.
    function migrateUniV3PositionToEkubo(MigrationData calldata data)
        external
        override
        returns (uint256 ekuboPositionId)
    {
        ekuboPositionId = _migrateUniV3PositionToEkubo(data);
    }

    /// @notice Migrates a single Uniswap V4 position to Ekubo.
    /// @param data Migration parameters for the source position and target Ekubo pool.
    /// @return ekuboPositionId The minted Ekubo position id.
    function migrateUniV4PositionToEkubo(MigrationData calldata data)
        external
        override
        returns (uint256 ekuboPositionId)
    {
        ekuboPositionId = _migrateUniV4PositionToEkubo(data);
    }

    /// @notice Migrates multiple Uniswap V3 positions to Ekubo.
    /// @param data Migration parameters per source position.
    /// @return ekuboPositionIds Minted Ekubo position ids in the same order as input.
    function migrateUniV3PositionsToEkubo(MigrationData[] calldata data)
        external
        override
        returns (uint256[] memory ekuboPositionIds)
    {
        uint256 length = data.length;
        ekuboPositionIds = new uint256[](length);
        for (uint256 i = 0; i < length;) {
            ekuboPositionIds[i] = _migrateUniV3PositionToEkubo(data[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Migrates multiple Uniswap V4 positions to Ekubo.
    /// @param data Migration parameters per source position.
    /// @return ekuboPositionIds Minted Ekubo position ids in the same order as input.
    function migrateUniV4PositionsToEkubo(MigrationData[] calldata data)
        external
        override
        returns (uint256[] memory ekuboPositionIds)
    {
        uint256 length = data.length;
        ekuboPositionIds = new uint256[](length);
        for (uint256 i = 0; i < length;) {
            ekuboPositionIds[i] = _migrateUniV4PositionToEkubo(data[i]);
            unchecked {
                ++i;
            }
        }
    }

    // Pulls UniV3 liquidity, normalizes token/native ordering, then mints and transfers Ekubo position.
    function _migrateUniV3PositionToEkubo(MigrationData calldata data)
        internal
        onlyUniV3TokenOwner(data.uniTokenId)
        returns (uint256 ekuboPositionId)
    {
        (address token0, address token1,, int24 tick, int24 tickLower, int24 tickUpper, uint128 liquidity) =
            _getUniV3PositionInfo(data.uniTokenId);
        if (liquidity == 0) revert ZeroLiquidity();

        (uint256 amount0, uint256 amount1) = _pullUniV3Liquidity(data.uniTokenId, liquidity);

        if (token0 == address(weth)) {
            weth.withdraw(amount0);
            token0 = address(0);
        } else if (token1 == address(weth)) {
            weth.withdraw(amount1);
            (token0, token1) = (address(0), token0);
            (amount0, amount1) = (amount1, amount0);
            (tickLower, tickUpper, tick) = (-tickUpper, -tickLower, -tick);
        }

        _approveTokenToEkubo(token0, amount0);
        _approveTokenToEkubo(token1, amount1);

        (ekuboPositionId,,) = _addEkuboLiquidity(
            token0, token1, data.ekuboPoolConfig, tick, tickLower, tickUpper, amount0, amount1, data.minLiquidity
        );

        ERC721(address(ekuboPositionManager)).safeTransferFrom(address(this), msg.sender, ekuboPositionId);
        _transferAllBalance(token0, msg.sender);
        _transferAllBalance(token1, msg.sender);

        emit MigrateUniV3(data.uniTokenId, ekuboPositionId);
    }

    // Pulls UniV4 liquidity, then mints and transfers the corresponding Ekubo position.
    function _migrateUniV4PositionToEkubo(MigrationData calldata data)
        internal
        onlyUniV4TokenOwner(data.uniTokenId)
        returns (uint256 ekuboPositionId)
    {
        UniswapV4PositionData memory pos = _getAndPullUniV4Position(data.uniTokenId);
        if (pos.liquidity == 0) revert ZeroLiquidity();

        if (pos.token1 == address(0)) {
            // Uniswap v4 native currency is always currency0 (address(0))
            revert InvalidTokenOrder();
        }

        _approveTokenToEkubo(pos.token0, pos.amount0);
        _approveTokenToEkubo(pos.token1, pos.amount1);

        (ekuboPositionId,,) = _addEkuboLiquidity(
            pos.token0,
            pos.token1,
            data.ekuboPoolConfig,
            pos.tick,
            pos.tickLower,
            pos.tickUpper,
            pos.amount0,
            pos.amount1,
            data.minLiquidity
        );

        ERC721(address(ekuboPositionManager)).safeTransferFrom(address(this), msg.sender, ekuboPositionId);
        _transferAllBalance(pos.token0, msg.sender);
        _transferAllBalance(pos.token1, msg.sender);

        emit MigrateUniV4(data.uniTokenId, ekuboPositionId);
    }

    // Initializes the destination pool if needed and deposits funds into the Ekubo position.
    // Concentrated pools use outward tick rounding; stableswap pools use their configured active range.
    function _addEkuboLiquidity(
        address token0,
        address token1,
        EkuboPoolConfig poolConfig,
        int24 uniCurrentTick,
        int24 uniTickLower,
        int24 uniTickUpper,
        uint256 amount0,
        uint256 amount1,
        uint128 minLiquidity
    ) internal returns (uint256 ekuboTokenId, uint128 depositedAmount0, uint128 depositedAmount1) {
        EkuboPoolKey memory poolKey = EkuboPoolKey(token0, token1, poolConfig);
        ekuboPositionManager.maybeInitializePool(poolKey, uniswapTickToEkuboTick(uniCurrentTick, 1, uniCurrentTick < 0));

        int32 ekuboTickLower;
        int32 ekuboTickUpper;
        if (ekuboIsConcentrated(poolConfig)) {
            uint32 tickSpacing = ekuboConcentratedTickSpacing(poolConfig);
            if (tickSpacing == 0) revert InvalidTickSpacing();
            // Round outwards so the Ekubo range is never narrower than the source range.
            ekuboTickLower = uniswapTickToEkuboTick(uniTickLower, tickSpacing, false);
            ekuboTickUpper = uniswapTickToEkuboTick(uniTickUpper, tickSpacing, true);
        } else {
            (ekuboTickLower, ekuboTickUpper) = ekuboStableswapActiveLiquidityTickRange(poolConfig);
        }

        uint256 value = token0 == address(0) ? amount0 : 0;
        (ekuboTokenId,, depositedAmount0, depositedAmount1) = ekuboPositionManager.mintAndDeposit{value: value}(
            poolKey,
            ekuboTickLower,
            ekuboTickUpper,
            SafeCastLib.toUint128(amount0),
            SafeCastLib.toUint128(amount1),
            minLiquidity
        );
    }

    // Reads UniV3 position parameters and current pool tick for migration math.
    function _getUniV3PositionInfo(uint256 uniTokenId)
        internal
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            int24 tick,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        )
    {
        (,, token0, token1, fee, tickLower, tickUpper, liquidity,,,,) = uniV3PositionManager.positions(uniTokenId);
        address pool = uniV3PositionFactory.getPool(token0, token1, fee);
        if (pool == address(0)) revert InvalidUniV3Pool();
        (, tick,,,,,) = IUniV3Pool(pool).slot0();
    }

    // Burns all UniV3 liquidity for a position and collects owed tokens to this contract.
    function _pullUniV3Liquidity(uint256 tokenId, uint128 liquidity)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        IUniV3PositionManager.DecreaseLiquidityParams memory
            decreaseLiqParams =
            IUniV3PositionManager.DecreaseLiquidityParams({
                tokenId: tokenId, liquidity: liquidity, amount0Min: 0, amount1Min: 0, deadline: block.timestamp
            });
        uniV3PositionManager.decreaseLiquidity(decreaseLiqParams);

        IUniV3PositionManager.CollectParams memory collectParams = IUniV3PositionManager.CollectParams({
            tokenId: tokenId, recipient: address(this), amount0Max: type(uint128).max, amount1Max: type(uint128).max
        });
        (amount0, amount1) = uniV3PositionManager.collect(collectParams);
    }

    // Reads UniV4 position metadata and pulls liquidity amounts into this contract.
    function _getAndPullUniV4Position(uint256 uniTokenId) internal returns (UniswapV4PositionData memory pos) {
        (UniV4PoolKey memory poolKey, UniV4PositionInfo info) = uniV4PositionManager.getPoolAndPositionInfo(uniTokenId);
        pos.liquidity = uniV4PositionManager.getPositionLiquidity(uniTokenId);

        pos.token0 = UniV4Currency.unwrap(poolKey.currency0);
        pos.token1 = UniV4Currency.unwrap(poolKey.currency1);
        pos.tickLower = info.tickLower();
        pos.tickUpper = info.tickUpper();
        (, pos.tick,,) = uniV4PositionManager.poolManager().getSlot0(poolKey.toId());

        if (pos.liquidity == 0) return pos;
        (pos.amount0, pos.amount1) = _pullUniV4Liquidity(uniTokenId, pos.token0, pos.token1, pos.liquidity);
    }

    // Executes UniV4 DECREASE_LIQUIDITY + TAKE_PAIR and returns funds now held by this contract.
    function _pullUniV4Liquidity(uint256 tokenId, address token0, address token1, uint128 liquidity)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        bytes memory actions = abi.encodePacked(uint8(UniV4Actions.DECREASE_LIQUIDITY), uint8(UniV4Actions.TAKE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, liquidity, uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(UniV4Currency.wrap(token0), UniV4Currency.wrap(token1), address(this));

        uniV4PositionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);

        amount0 = _getBalance(token0);
        amount1 = _getBalance(token1);
    }

    // Sets a max allowance to Ekubo once per token when allowance is zero.
    function _approveTokenToEkubo(address token, uint256 amount) internal {
        if (token == address(0) || amount == 0) return;
        if (ERC20(token).allowance(address(this), address(ekuboPositionManager)) == 0) {
            SafeTransferLib.safeApproveWithRetry(token, address(ekuboPositionManager), type(uint256).max);
        }
    }

    // Reverts unless msg.sender owns the UniV3 position token.
    function _requireUniV3TokenOwner(uint256 tokenId) internal view {
        address owner = uniV3PositionManager.ownerOf(tokenId);
        if (owner != msg.sender) revert NotNftOwner(msg.sender, owner, tokenId);
    }

    // Reverts unless msg.sender owns the UniV4 position token.
    function _requireUniV4TokenOwner(uint256 tokenId) internal view {
        address owner = ERC721(address(uniV4PositionManager)).ownerOf(tokenId);
        if (owner != msg.sender) revert NotNftOwner(msg.sender, owner, tokenId);
    }

    // Sweeps all remaining native/ERC20 balance for `token` back to the caller.
    function _transferAllBalance(address token, address to) internal {
        if (token == address(0)) {
            uint256 amount = address(this).balance;
            if (amount == 0) return;
            (bool success,) = to.call{value: amount}("");
            if (!success) {
                weth.deposit{value: amount}();
                SafeTransferLib.safeTransfer(address(weth), to, amount);
            }
        } else {
            uint256 amount = ERC20(token).balanceOf(address(this));
            if (amount == 0) return;
            SafeTransferLib.safeTransfer(token, to, amount);
        }
    }

    // Returns this contract balance for native token or ERC20 token.
    function _getBalance(address token) internal view returns (uint256) {
        if (token == address(0)) return address(this).balance;
        return ERC20(token).balanceOf(address(this));
    }

    receive() external payable {}
}
