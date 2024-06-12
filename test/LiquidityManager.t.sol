// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";

import {CrossChainLiquidityManager} from "../src/CrossChainLiquidityManager.sol";
import {MainnetLiquidityManagerProxy} from "../src/proxies/MainnetLiquidityManagerProxy.sol";
import {ArbLiquidityManagerProxy} from "../src/proxies/ArbLiquidityManagerProxy.sol";
import {MockCCIPRouter} from "../src/mocks/MockCCIPRouter.sol";
import {IRouterClient} from "@ccip/interfaces/IRouterClient.sol";

contract LiquidityManagerTest is Test {
    MainnetLiquidityManagerProxy public managerEthProxy;
    ArbLiquidityManagerProxy public managerArbProxy;
    CrossChainLiquidityManager public managerEth;
    CrossChainLiquidityManager public managerArb;

    MockCCIPRouter public mockRouter;

    uint64 public constant mainnetChainSelector = 5009297550715157269;
    uint64 public constant arbChainSelector = 4949039107694359620;

    address public constant ethToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public constant owner = address(0x111);

    function setUp() public {
        vm.startPrank(owner);
        mockRouter = new MockCCIPRouter();

        managerEthProxy = new MainnetLiquidityManagerProxy();
        managerArbProxy = new ArbLiquidityManagerProxy();

        managerEth = new CrossChainLiquidityManager(
            address(mockRouter),
            arbChainSelector,
            address(managerArbProxy)
        );

        managerArb = new CrossChainLiquidityManager(
            address(mockRouter),
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

        vm.deal(address(managerEth), 100 ether);
        vm.deal(address(managerArb), 100 ether);

        console.log("ETH Liquidity", address(managerEth).balance);
        console.log("ARB Liquidity", address(managerArb).balance);

        mockRouter.setForwardRequests(true);

        vm.stopPrank();
    }

    function testArbToEth() external {
        mockRouter.setNextSourceChainSelector(arbChainSelector);

        console.log("Balance Before", address(0x122).balance);

        bytes32 messageId = managerArb.swapExactTokensForTokens{ value: 1 ether }(
            ethToken,
            ethToken,
            1 ether,
            0.98 ether,
            address(0x122)
        );

        console.log("Message ID", vm.toString(messageId));
        console.log("Balance After", address(0x122).balance);
        console.log("Pending Balance After", managerEth.pendingUserBalance(address(0x122)));
    }
}
