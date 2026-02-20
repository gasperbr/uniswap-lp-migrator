// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "solady/tokens/ERC20.sol";
import {ERC721} from "solady/tokens/ERC721.sol";
import {WETH} from "solady/tokens/WETH.sol";

import {Core} from "evm-contracts/src/Core.sol";
import {Positions} from "evm-contracts/src/Positions.sol";
import {PoolConfig} from "evm-contracts/src/types/poolConfig.sol";
import {TestToken} from "lib/evm-contracts/test/TestToken.sol";

import {IUniV3DeployHelper} from "../interfaces/IUniV3DeployHelper.sol";
import {IUniV4DeployHelper} from "../interfaces/IUniV4DeployHelper.sol";
import {
    INonfungiblePositionManager as IUniV3PositionManager
} from "../../src/interfaces/INonFungiblePositionManager.sol";
import {IUniswapV3Factory as IUniV3Factory} from "../../src/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool as IUniV3Pool} from "../../src/interfaces/IUniswapV3Pool.sol";
import {IUniToEkuboMigrator} from "../../src/interfaces/IUniToEkuboMigrator.sol";
import {UniToEkuboMigrator} from "../../src/UniToEkuboMigrator.sol";

import {IPositionManager as IUniV4PositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions as UniV4Actions} from "v4-periphery/src/libraries/Actions.sol";

import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";

import {Currency as UniV4Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks as IUniV4Hooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager as IUniV4PoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey as UniV4PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {MigratorTestConstants as C} from "./constants.sol";

abstract contract UniToEkuboMigratorBase is Test, DeployPermit2 {
    error InvalidSwapCallback();
    error PoolNotInitialized();
    error UnableToFindTokenAddressRelativeToWeth(bool shouldBeLessThanWeth);

    Core internal ekuboCore;
    Positions internal ekuboPositions;
    UniToEkuboMigrator internal migrator;

    WETH internal weth;
    IUniV3Factory internal uniV3Factory;
    IUniV3PositionManager internal uniV3PositionManager;

    TestToken internal baseToken;
    TestToken internal quoteToken;
    TestToken internal tokenBelowWeth;
    TestToken internal tokenAboveWeth;

    C.ScenarioPools internal scenarioPools;
    C.ScenarioPositions internal scenarioPositions;

    IUniV4PositionManager internal uniV4PositionManager;
    IUniV4PoolManager internal uniV4PoolManager;
    IAllowanceTransfer internal uniV4Permit2;
    UniV4PoolKey internal uniV4TokenTokenPool;
    TestToken internal uniV4Token0;
    TestToken internal uniV4Token1;
    C.UniV4ScenarioPositions internal uniV4ScenarioPositions;

    uint160 internal constant UNI_V4_SQRT_PRICE_1_1 = 79228162514264337593543950336;

    struct UniV4PositionConfig {
        UniV4PoolKey poolKey;
        int24 tickLower;
        int24 tickUpper;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _setUpV3LocalSuite() internal {
        _deployEkubo();
        _deployUniV3Stack();
        _deployUniV3Migrator();
        _deployV3TestTokens();
        _seedV3Balances();
        _approveUniV3Spender();
        _createV3ScenarioPools();
        _mintV3ScenarioPositions();
    }

    function _setUpV4LocalSuite() internal {
        _deployEkubo();
        _deployUniV3Stack();
        _deployUniV4Stack();
        _mintV4ScenarioPositions();
    }

    function _deployEkubo() internal {
        ekuboCore = new Core();
        ekuboPositions = new Positions(ekuboCore, address(this), 0, 1);
    }

    function _deployUniV3Stack() internal {
        weth = new WETH();

        address helper = deployCode("out/UniV3DeployHelper.sol/UniV3DeployHelper.json");
        (address factoryAddress, address positionManagerAddress) = IUniV3DeployHelper(helper).deploy(address(weth));
        uniV3Factory = IUniV3Factory(factoryAddress);
        uniV3PositionManager = IUniV3PositionManager(payable(positionManagerAddress));
    }

    function _deployUniV3Migrator() internal {
        migrator = new UniToEkuboMigrator(address(uniV3PositionManager), payable(address(0)), address(ekuboPositions));
        uniV3PositionManager.setApprovalForAll(address(migrator), true);
    }

    function _deployV3TestTokens() internal {
        TestToken tokenA = new TestToken(address(this));
        TestToken tokenB = new TestToken(address(this));
        (baseToken, quoteToken) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        tokenBelowWeth = _deployTokenRelativeToWeth(true);
        tokenAboveWeth = _deployTokenRelativeToWeth(false);
    }

    function _deployTokenRelativeToWeth(bool shouldBeLessThanWeth) internal returns (TestToken token) {
        for (uint256 i = 0; i < 64; ++i) {
            token = new TestToken(address(this));
            if ((address(token) < address(weth)) == shouldBeLessThanWeth) return token;
        }

        revert UnableToFindTokenAddressRelativeToWeth(shouldBeLessThanWeth);
    }

    function _seedV3Balances() internal {
        vm.deal(address(this), 2_000 ether);
        weth.deposit{value: 1_000 ether}();
    }

    function _approveUniV3Spender() internal {
        ERC20(address(baseToken)).approve(address(uniV3PositionManager), type(uint256).max);
        ERC20(address(quoteToken)).approve(address(uniV3PositionManager), type(uint256).max);
        ERC20(address(tokenBelowWeth)).approve(address(uniV3PositionManager), type(uint256).max);
        ERC20(address(tokenAboveWeth)).approve(address(uniV3PositionManager), type(uint256).max);
        ERC20(address(weth)).approve(address(uniV3PositionManager), type(uint256).max);
    }

    function _createV3ScenarioPools() internal {
        scenarioPools.tokenToken = _createAndInitializeUniV3Pool(address(baseToken), address(quoteToken));
        scenarioPools.wethToken = _createAndInitializeUniV3Pool(address(weth), address(tokenAboveWeth));
        scenarioPools.tokenWeth = _createAndInitializeUniV3Pool(address(tokenBelowWeth), address(weth));
        scenarioPools.ethToken = _createAndInitializeUniV3Pool(address(weth), address(quoteToken));
    }

    function _mintV3ScenarioPositions() internal {
        scenarioPositions.tokenTokenInRange = _mintUniV3Position(
            address(baseToken), address(quoteToken), C.UNI_V3_TICK_LOWER_ACTIVE, C.UNI_V3_TICK_UPPER_ACTIVE
        );
        scenarioPositions.tokenTokenBelowSpot = _mintUniV3Position(
            address(baseToken), address(quoteToken), C.UNI_V3_TICK_LOWER_BELOW_SPOT, C.UNI_V3_TICK_UPPER_BELOW_SPOT
        );
        scenarioPositions.tokenTokenAboveSpot = _mintUniV3Position(
            address(baseToken), address(quoteToken), C.UNI_V3_TICK_LOWER_ABOVE_SPOT, C.UNI_V3_TICK_UPPER_ABOVE_SPOT
        );
        scenarioPositions.tokenTokenFullRange = _mintUniV3Position(
            address(baseToken), address(quoteToken), C.UNI_V3_TICK_LOWER_FULL_RANGE, C.UNI_V3_TICK_UPPER_FULL_RANGE
        );
        scenarioPositions.tokenTokenStableRangeMatch = _mintUniV3Position(
            address(baseToken), address(quoteToken), C.UNI_V3_TICK_LOWER_STABLE_MATCH, C.UNI_V3_TICK_UPPER_STABLE_MATCH
        );

        scenarioPositions.tokenTokenInRangeWithFees = _mintUniV3Position(
            address(baseToken), address(quoteToken), C.UNI_V3_TICK_LOWER_ACTIVE, C.UNI_V3_TICK_UPPER_ACTIVE
        );
        _accrueFees(scenarioPools.tokenToken);

        scenarioPositions.wethTokenInRangeWithFees = _mintUniV3Position(
            address(weth), address(tokenAboveWeth), C.UNI_V3_TICK_LOWER_ACTIVE, C.UNI_V3_TICK_UPPER_ACTIVE
        );
        _accrueFees(scenarioPools.wethToken);

        scenarioPositions.tokenWethInRangeWithFees = _mintUniV3Position(
            address(tokenBelowWeth), address(weth), C.UNI_V3_TICK_LOWER_ACTIVE, C.UNI_V3_TICK_UPPER_ACTIVE
        );
        _accrueFees(scenarioPools.tokenWeth);

        scenarioPositions.ethTokenInRangeWithFees = _mintUniV3Position(
            address(weth), address(quoteToken), C.UNI_V3_TICK_LOWER_ACTIVE, C.UNI_V3_TICK_UPPER_ACTIVE
        );
        _accrueFees(scenarioPools.ethToken);
    }

    function _createAndInitializeUniV3Pool(address tokenA, address tokenB) internal returns (address pool) {
        pool = uniV3Factory.getPool(tokenA, tokenB, C.UNI_V3_FEE);
        if (pool == address(0)) {
            pool = uniV3Factory.createPool(tokenA, tokenB, C.UNI_V3_FEE);
            IUniV3Pool(pool).initialize(C.UNI_V3_INITIAL_SQRT_PRICE_X96);
        }
    }

    function _mintUniV3Position(address tokenA, address tokenB, int24 tickLower, int24 tickUpper)
        internal
        returns (uint256 tokenId)
    {
        (address sortedToken0, address sortedToken1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        _createAndInitializeUniV3Pool(sortedToken0, sortedToken1);

        IUniV3PositionManager.MintParams memory params = IUniV3PositionManager.MintParams({
            token0: sortedToken0,
            token1: sortedToken1,
            fee: C.UNI_V3_FEE,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: C.UNI_V3_POSITION_AMOUNT,
            amount1Desired: C.UNI_V3_POSITION_AMOUNT,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (tokenId,,,) = uniV3PositionManager.mint(params);
    }

    function _migrateUniV3Position(uint256 uniV3TokenId, PoolConfig poolConfig)
        internal
        returns (uint256 ekuboPositionId)
    {
        ekuboPositionId = migrator.migrateUniV3PositionToEkubo(_migrationDataForUniV3(uniV3TokenId, poolConfig));
        _assertMigratorNoDustV3();
    }

    function _migrationDataForUniV3(uint256 uniV3TokenId, PoolConfig poolConfig)
        internal
        view
        returns (IUniToEkuboMigrator.MigrationData memory data)
    {
        (,,,,,,, uint128 liquidity,,,,) = uniV3PositionManager.positions(uniV3TokenId);
        data = IUniToEkuboMigrator.MigrationData({
            uniTokenId: uniV3TokenId, ekuboPoolConfig: poolConfig, minLiquidity: _minLiquidityFloor(liquidity)
        });
    }

    function _accrueFees(address uniV3Pool) internal {
        _swapToAccrueFees(uniV3Pool, true, C.UNI_V3_FEE_ACCRUAL_SWAP_AMOUNT);
        _swapToAccrueFees(uniV3Pool, false, C.UNI_V3_FEE_ACCRUAL_SWAP_AMOUNT);
    }

    function _swapToAccrueFees(address uniV3Pool, bool zeroForOne, uint256 amountIn) internal {
        IUniV3Pool(uniV3Pool)
            .swap(
                address(this),
                zeroForOne,
                int256(amountIn),
                zeroForOne ? C.UNI_V3_MIN_SQRT_RATIO_PLUS_ONE : C.UNI_V3_MAX_SQRT_RATIO_MINUS_ONE,
                bytes("")
            );
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        address token0 = IUniV3Pool(msg.sender).token0();
        address token1 = IUniV3Pool(msg.sender).token1();
        if (uniV3Factory.getPool(token0, token1, C.UNI_V3_FEE) != msg.sender) revert InvalidSwapCallback();

        if (amount0Delta > 0) ERC20(token0).transfer(msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0) ERC20(token1).transfer(msg.sender, uint256(amount1Delta));
    }

    function _deployUniV4Stack() internal {
        uniV4Permit2 = IAllowanceTransfer(deployPermit2());
        address helper = deployCode("out/UniV4DeployHelper.sol/UniV4DeployHelper.json");
        (address poolManagerAddress, address posmAddress) =
            IUniV4DeployHelper(helper).deploy(address(this), address(uniV4Permit2), address(weth));
        uniV4PoolManager = IUniV4PoolManager(poolManagerAddress);
        uniV4PositionManager = IUniV4PositionManager(payable(posmAddress));

        _deployUniV4TestTokens();
        _createAndInitializeUniV4Pool();

        _approveUniV4CurrencyForPosm(uniV4TokenTokenPool.currency0);
        _approveUniV4CurrencyForPosm(uniV4TokenTokenPool.currency1);

        migrator = new UniToEkuboMigrator(
            address(uniV3PositionManager), payable(address(uniV4PositionManager)), address(ekuboPositions)
        );

        ERC721(address(uniV4PositionManager)).setApprovalForAll(address(migrator), true);
    }

    function _deployUniV4TestTokens() internal {
        TestToken tokenA = new TestToken(address(this));
        TestToken tokenB = new TestToken(address(this));
        (uniV4Token0, uniV4Token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function _createAndInitializeUniV4Pool() internal {
        uniV4TokenTokenPool = UniV4PoolKey({
            currency0: UniV4Currency.wrap(address(uniV4Token0)),
            currency1: UniV4Currency.wrap(address(uniV4Token1)),
            fee: C.UNI_V4_FEE,
            tickSpacing: int24(int256(uint256(C.UNI_V4_FEE / 100 * 2))),
            hooks: IUniV4Hooks(address(0))
        });

        uniV4PoolManager.initialize(uniV4TokenTokenPool, UNI_V4_SQRT_PRICE_1_1);
    }

    function _approveUniV4CurrencyForPosm(UniV4Currency currency) internal {
        address token = UniV4Currency.unwrap(currency);
        ERC20(token).approve(address(uniV4Permit2), type(uint256).max);
        uniV4Permit2.approve(token, address(uniV4PositionManager), type(uint160).max, type(uint48).max);
    }

    function _mintV4ScenarioPositions() internal {
        uniV4ScenarioPositions.tokenTokenInRange =
            _mintUniV4Position(C.UNI_V3_TICK_LOWER_ACTIVE, C.UNI_V3_TICK_UPPER_ACTIVE);
        uniV4ScenarioPositions.tokenTokenBelowSpot =
            _mintUniV4Position(C.UNI_V3_TICK_LOWER_BELOW_SPOT, C.UNI_V3_TICK_UPPER_BELOW_SPOT);
        uniV4ScenarioPositions.tokenTokenAboveSpot =
            _mintUniV4Position(C.UNI_V3_TICK_LOWER_ABOVE_SPOT, C.UNI_V3_TICK_UPPER_ABOVE_SPOT);
        uniV4ScenarioPositions.tokenTokenFullRange =
            _mintUniV4Position(C.UNI_V3_TICK_LOWER_FULL_RANGE, C.UNI_V3_TICK_UPPER_FULL_RANGE);
        uniV4ScenarioPositions.tokenTokenStableRangeMatch =
            _mintUniV4Position(C.UNI_V3_TICK_LOWER_STABLE_MATCH, C.UNI_V3_TICK_UPPER_STABLE_MATCH);
    }

    function _mintUniV4Position(int24 tickLower, int24 tickUpper) internal returns (uint256 tokenId) {
        tokenId = uniV4PositionManager.nextTokenId();

        UniV4PositionConfig memory config =
            UniV4PositionConfig({poolKey: uniV4TokenTokenPool, tickLower: tickLower, tickUpper: tickUpper});

        bytes memory calls = _getUniV4MintEncoded(config, C.UNI_V4_POSITION_LIQUIDITY, address(this), bytes(""));
        uniV4PositionManager.modifyLiquidities(calls, block.timestamp + 1);
    }

    function _getUniV4MintEncoded(
        UniV4PositionConfig memory config,
        uint256 liquidity,
        address recipient,
        bytes memory hookData
    ) internal pure returns (bytes memory) {
        bytes memory actions = abi.encodePacked(
            uint8(UniV4Actions.MINT_POSITION), uint8(UniV4Actions.CLOSE_CURRENCY), uint8(UniV4Actions.CLOSE_CURRENCY)
        );

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            config.poolKey,
            config.tickLower,
            config.tickUpper,
            liquidity,
            type(uint128).max,
            type(uint128).max,
            recipient,
            hookData
        );
        params[1] = abi.encode(config.poolKey.currency0);
        params[2] = abi.encode(config.poolKey.currency1);

        return abi.encode(actions, params);
    }

    function _migrateUniV4Position(uint256 uniV4TokenId, PoolConfig poolConfig)
        internal
        returns (uint256 ekuboPositionId)
    {
        IUniToEkuboMigrator.MigrationData memory data = _migrationDataForUniV4(uniV4TokenId, poolConfig);

        ekuboPositionId = migrator.migrateUniV4PositionToEkubo(data);
        _assertMigratorNoDustV4();
    }

    function _assertMigratorNoDustV3() internal view {
        _assertNoTokenDust(address(baseToken));
        _assertNoTokenDust(address(quoteToken));
        _assertNoTokenDust(address(tokenBelowWeth));
        _assertNoTokenDust(address(tokenAboveWeth));
        _assertNoTokenDust(address(weth));
        assertEq(address(migrator).balance, 0, "migrator native dust");
    }

    function _assertMigratorNoDustV4() internal view {
        _assertNoTokenDust(UniV4Currency.unwrap(uniV4TokenTokenPool.currency0));
        _assertNoTokenDust(UniV4Currency.unwrap(uniV4TokenTokenPool.currency1));
        assertEq(address(migrator).balance, 0, "migrator native dust");
    }

    function _assertNoTokenDust(address token) internal view {
        assertEq(ERC20(token).balanceOf(address(migrator)), 0, "migrator token dust");
    }

    function _migrationDataForUniV4(uint256 uniV4TokenId, PoolConfig poolConfig)
        internal
        view
        returns (IUniToEkuboMigrator.MigrationData memory data)
    {
        uint128 liquidity = uniV4PositionManager.getPositionLiquidity(uniV4TokenId);
        data = IUniToEkuboMigrator.MigrationData({
            uniTokenId: uniV4TokenId, ekuboPoolConfig: poolConfig, minLiquidity: _minLiquidityFloor(liquidity)
        });
    }

    function _minLiquidityFloor(uint128 sourceLiquidity) internal pure returns (uint128) {
        return uint128((uint256(sourceLiquidity) * 99) / 100);
    }
}
