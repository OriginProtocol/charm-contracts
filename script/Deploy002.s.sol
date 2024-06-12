// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";

import {CrossChainLiquidityManager} from "../src/CrossChainLiquidityManager.sol";
import {MainnetLiquidityManagerProxy} from "../src/proxies/MainnetLiquidityManagerProxy.sol";
import {ArbLiquidityManagerProxy} from "../src/proxies/ArbLiquidityManagerProxy.sol";

contract Deploy002Script is Script {
    MainnetLiquidityManagerProxy public managerEthProxy;
    ArbLiquidityManagerProxy public managerArbProxy;
    CrossChainLiquidityManager public managerEth;
    CrossChainLiquidityManager public managerArb;

    address public constant mainnetCCIPRouter = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
    address public constant arbCCIPRouter = 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;

    uint64 public constant mainnetChainSelector = 5009297550715157269;
    uint64 public constant arbChainSelector = 4949039107694359620;

    address public constant ethToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public constant deployer = 0x58890A9cB27586E83Cb51d2d26bbE18a1a647245;

    function setUp() public {
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        managerEthProxy = MainnetLiquidityManagerProxy(payable(0xd2Ce34cc70ffdc707934BD0035fC1B4450936d63));
        managerArbProxy = ArbLiquidityManagerProxy(payable(0xa6774B8A0C61e724BDA845b22b0ACB42c4f5c100));

        if (block.chainid == 1) {
            managerEth = new CrossChainLiquidityManager(
                mainnetCCIPRouter,
                arbChainSelector,
                address(managerArbProxy)
            );

            managerEthProxy.initialize(
                address(managerEth),
                deployer,
                hex""
            );

            managerEth = CrossChainLiquidityManager(payable(address(managerEthProxy)));
        } else {
            managerArb = new CrossChainLiquidityManager(
                arbCCIPRouter,
                mainnetChainSelector,
                address(managerEthProxy)
            );

            managerArbProxy.initialize(
                address(managerArb),
                deployer,
                hex""
            );

            managerArb = CrossChainLiquidityManager(payable(address(managerArbProxy)));
        }


        vm.stopBroadcast();
    }
}
