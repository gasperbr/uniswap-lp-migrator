// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.6;

interface IUniV3DeployHelper {
    function deploy(address weth) external returns (address factory, address positionManager);
}
