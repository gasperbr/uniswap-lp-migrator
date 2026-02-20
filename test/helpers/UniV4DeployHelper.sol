// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";

import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IPositionDescriptor} from "v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

/// @notice Local helper to deploy real Uniswap v4 pool manager + position manager for tests.
contract UniV4DeployHelper {
    function deploy(address owner, address permit2, address weth) external returns (address poolManager, address posm) {
        PoolManager manager = new PoolManager(owner);
        PositionManager positionManager = new PositionManager(
            manager, IAllowanceTransfer(permit2), 100_000, IPositionDescriptor(address(0)), IWETH9(weth)
        );

        poolManager = address(manager);
        posm = address(positionManager);
    }
}
