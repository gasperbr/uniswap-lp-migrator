// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

/// @title Uniswap V4 Pool Interface
interface IUniV4Pool {
    /// @notice Returns the first token of the pool
    function token0() external view returns (address);

    /// @notice Returns the second token of the pool
    function token1() external view returns (address);

    /// @notice Returns the pool's fee in hundredths of a bip
    function fee() external view returns (uint24);

    /// @notice Returns the pool's tick spacing
    function tickSpacing() external view returns (int24);

    /// @notice Returns the pool's current state
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}
