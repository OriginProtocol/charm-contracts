// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";

import {CrossChainLiquidityManager} from "../src/CrossChainLiquidityManager.sol";
import {MainnetLiquidityManagerProxy} from "../src/proxies/MainnetLiquidityManagerProxy.sol";
import {ArbLiquidityManagerProxy} from "../src/proxies/ArbLiquidityManagerProxy.sol";

contract Deploy001Script is Script {
    MainnetLiquidityManagerProxy public managerEthProxy;
    ArbLiquidityManagerProxy public managerArbProxy;

    address public constant deployer = 0x58890A9cB27586E83Cb51d2d26bbE18a1a647245;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy proxies
        if (block.chainid == 1) {
            managerEthProxy = new MainnetLiquidityManagerProxy();
            console.log("Mainnet Manager Proxy", address(managerEthProxy));
        } else {
            managerArbProxy = new ArbLiquidityManagerProxy();
            console.log("Arbitrum Manager Proxy", address(managerArbProxy));
        }

        vm.stopBroadcast();
    }
}
