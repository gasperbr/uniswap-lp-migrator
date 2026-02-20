// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {PoolConfig as EkuboPoolConfig} from "evm-contracts/src/types/poolConfig.sol";

interface IUniToEkuboMigrator {
    error NotNftOwner(address caller, address owner, uint256 tokenId);
    error InvalidUniV3Pool();
    error InvalidTickSpacing();
    error ZeroLiquidity();
    error InvalidTokenOrder();

    event MigrateUniV3(uint256 uniV3TokenId, uint256 ekuboTokenId);
    event MigrateUniV4(uint256 uniV4TokenId, uint256 ekuboTokenId);

    struct MigrationData {
        uint256 uniTokenId;
        EkuboPoolConfig ekuboPoolConfig;
        uint128 minLiquidity;
    }

    struct UniswapV4PositionData {
        address token0;
        address token1;
        int24 tick;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
    }

    function migrateUniV3PositionToEkubo(MigrationData calldata data) external returns (uint256 ekuboPositionId);

    function migrateUniV4PositionToEkubo(MigrationData calldata data) external returns (uint256 ekuboPositionId);

    function migrateUniV3PositionsToEkubo(MigrationData[] calldata data)
        external
        returns (uint256[] memory ekuboPositionIds);

    function migrateUniV4PositionsToEkubo(MigrationData[] calldata data)
        external
        returns (uint256[] memory ekuboPositionIds);
}
