// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";

import {CrossChainLiquidityManager} from "../src/CrossChainLiquidityManager.sol";
import {MainnetLiquidityManagerProxy} from "../src/proxies/MainnetLiquidityManagerProxy.sol";
import {ArbLiquidityManagerProxy} from "../src/proxies/ArbLiquidityManagerProxy.sol";

import {IRouterClient} from "@ccip/interfaces/IRouterClient.sol";

contract LiquidityManagerForkTest is Test {
    MainnetLiquidityManagerProxy public managerEthProxy;
    ArbLiquidityManagerProxy public managerArbProxy;
    CrossChainLiquidityManager public managerEth;
    CrossChainLiquidityManager public managerArb;

    address public constant mainnetCCIPRouter = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
    address public constant arbCCIPRouter = 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;

    uint64 public constant mainnetChainSelector = 5009297550715157269;
    uint64 public constant arbChainSelector = 4949039107694359620;

    address public constant ethToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public constant owner = address(0x111);

    function setUp() public {
        vm.startPrank(owner);
        managerEthProxy = new MainnetLiquidityManagerProxy();
        managerArbProxy = new ArbLiquidityManagerProxy();

        managerEth = new CrossChainLiquidityManager(
            mainnetCCIPRouter,
            arbChainSelector,
            address(managerArbProxy)
        );

        managerArb = new CrossChainLiquidityManager(
            arbCCIPRouter,
            mainnetChainSelector,
            address(managerEthProxy)
        );

        managerEthProxy.initialize(
            address(managerEth),
            owner,
            hex""
        );

        managerArbProxy.initialize(
            address(managerArb),
            owner,
            hex""
        );

        managerEth = CrossChainLiquidityManager(payable(address(managerEthProxy)));
        managerArb = CrossChainLiquidityManager(payable(address(managerArbProxy)));

        managerEth.initialize(owner, 0.99 ether);
        managerArb.initialize(owner, 0.99 ether);
        vm.stopPrank();
    }

    function testArbToEth() external {
        bytes32 messageId = managerArb.swapExactTokensForTokens{ value: 1 ether }(
            ethToken,
            ethToken,
            1 ether,
            0.98 ether,
            address(0x122)
        );

        console.log("Message ID", vm.toString(messageId));
    }
}
