// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IUniV4DeployHelper {
    function deploy(address owner, address permit2, address weth) external returns (address poolManager, address posm);
}
