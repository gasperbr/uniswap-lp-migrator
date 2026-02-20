// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {UniToEkuboMigrator} from "../src/UniToEkuboMigrator.sol";

contract DeployUniV3ToEkuboMigrator is Script {
    // Ethereum mainnet addresses
    address constant UNIV3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address payable constant UNIV4_POSITION_MANAGER = payable(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
    address constant EKUBO_POSITION_MANAGER = 0x02D9876A21AF7545f8632C3af76eC90b5ad4b66D;

    function run() external returns (UniToEkuboMigrator) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        UniToEkuboMigrator migrator =
            new UniToEkuboMigrator(UNIV3_POSITION_MANAGER, UNIV4_POSITION_MANAGER, EKUBO_POSITION_MANAGER);

        console.log("UniToEkuboMigrator deployed at:", address(migrator));
        console.log("UniV3 Position Manager:", UNIV3_POSITION_MANAGER);
        console.log("UniV4 Position Manager:", UNIV4_POSITION_MANAGER);
        console.log("Ekubo Position Manager:", EKUBO_POSITION_MANAGER);

        vm.stopBroadcast();

        return migrator;
    }
}
