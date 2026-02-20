// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {Script, console2} from "forge-std/Script.sol";
import {UniToEkuboMigrator} from "../src/UniToEkuboMigrator.sol";

contract DeployUniToEkuboMigratorEthereum is Script {
    error InvalidChainId(uint256 chainId);
    error ZeroAddress(string key);
    error AddressHasNoCode(string key, address value);

    uint256 internal constant ETHEREUM_MAINNET_CHAIN_ID = 1;

    address internal constant DEFAULT_UNI_V3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address payable internal constant DEFAULT_UNI_V4_POSITION_MANAGER =
        payable(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
    address internal constant DEFAULT_EKUBO_POSITION_MANAGER = 0x02D9876A21AF7545f8632C3af76eC90b5ad4b66D;

    struct DeployConfig {
        address uniV3PositionManager;
        address payable uniV4PositionManager;
        address ekuboPositionManager;
    }

    function run() external returns (UniToEkuboMigrator migrator) {
        if (block.chainid != ETHEREUM_MAINNET_CHAIN_ID) revert InvalidChainId(block.chainid);

        DeployConfig memory cfg = _loadConfig();
        _validateConfig(cfg);

        vm.startBroadcast();
        migrator = new UniToEkuboMigrator(cfg.uniV3PositionManager, cfg.uniV4PositionManager, cfg.ekuboPositionManager);
        vm.stopBroadcast();

        console2.log("UniToEkuboMigrator deployed:", address(migrator));
        console2.log("UniV3 Position Manager:", cfg.uniV3PositionManager);
        console2.log("UniV4 Position Manager:", cfg.uniV4PositionManager);
        console2.log("Ekubo Position Manager:", cfg.ekuboPositionManager);
    }

    function _loadConfig() internal view returns (DeployConfig memory cfg) {
        cfg.uniV3PositionManager = vm.envOr("UNI_V3_POSITION_MANAGER", DEFAULT_UNI_V3_POSITION_MANAGER);
        cfg.uniV4PositionManager =
            payable(vm.envOr("UNI_V4_POSITION_MANAGER", address(DEFAULT_UNI_V4_POSITION_MANAGER)));
        cfg.ekuboPositionManager = vm.envOr("EKUBO_POSITION_MANAGER", DEFAULT_EKUBO_POSITION_MANAGER);
    }

    function _validateConfig(DeployConfig memory cfg) internal view {
        if (cfg.uniV3PositionManager == address(0)) revert ZeroAddress("UNI_V3_POSITION_MANAGER");
        if (cfg.uniV4PositionManager == address(0)) revert ZeroAddress("UNI_V4_POSITION_MANAGER");
        if (cfg.ekuboPositionManager == address(0)) revert ZeroAddress("EKUBO_POSITION_MANAGER");

        if (cfg.uniV3PositionManager.code.length == 0) {
            revert AddressHasNoCode("UNI_V3_POSITION_MANAGER", cfg.uniV3PositionManager);
        }
        if (cfg.uniV4PositionManager.code.length == 0) {
            revert AddressHasNoCode("UNI_V4_POSITION_MANAGER", cfg.uniV4PositionManager);
        }
        if (cfg.ekuboPositionManager.code.length == 0) {
            revert AddressHasNoCode("EKUBO_POSITION_MANAGER", cfg.ekuboPositionManager);
        }
    }
}
