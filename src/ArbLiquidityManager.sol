// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {CrossChainLiquidityManager} from "./CrossChainLiquidityManager.sol";
import {IArbSys} from "./Interfaces.sol";

contract ArbLiquidityManager is CrossChainLiquidityManager {
    IArbSys public constant arbSys = IArbSys(address(0x64));

    constructor(address _l2Router, uint64 _otherChainSelector, address _otherChainLiquidityManager)
        CrossChainLiquidityManager(_l2Router, _otherChainSelector, _otherChainLiquidityManager)
    {}

    function redeemEth(uint256 amount) external onlyOwner {
        arbSys.withdrawEth{value: amount}(otherChainLiquidityManager);
    }
}
