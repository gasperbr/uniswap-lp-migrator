// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import {UniswapV3Factory} from "v3-core/contracts/UniswapV3Factory.sol";
import {NonfungiblePositionManager} from "v3-periphery/NonfungiblePositionManager.sol";

/// @notice Local helper to deploy real Uniswap V3 factory + position manager for tests.
contract UniV3DeployHelper {
    function deploy(address weth) external returns (address factory, address positionManager) {
        factory = address(new UniswapV3Factory());
        positionManager = address(new NonfungiblePositionManager(factory, weth, address(0)));
    }
}
