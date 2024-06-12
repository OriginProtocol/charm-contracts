// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableOperable} from "./ownership/OwnableOperable.sol";

import {CCIPReceiver} from "@ccip/applications/CCIPReceiver.sol";
import {Client} from "@ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/interfaces/IRouterClient.sol";
import {IARM} from "@ccip/interfaces/IARM.sol";

import {IERC20, ICCIPRouter} from "./Interfaces.sol";

contract CrossChainLiquidityManager is OwnableOperable, CCIPReceiver {
    uint256 public traderate;

    uint256 public pendingFee;
    address public feeRecipient;

    bool internal initialized;

    mapping(bytes32 => bool) public messageProcessed;

    mapping(address => uint256) public pendingUserBalance;

    uint256 public additionalLiquidityNeeded;

    uint64 public immutable otherChainSelector;
    address public immutable otherChainLiquidityManager;

    address public constant token0 = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant token1 = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    event FeeRecipientChanged(address oldRecipient, address newRecipient);
    event FeeCollected(address recipient, uint256 fee);
    event TradeRateChanged(uint256 oldRate, uint256 newRate);
    event PendingBalanceClaimed(address recipient, uint256 amount);
    event TransferInitiated(bytes32 messageId);
    event TransferCompleted(bytes32 messageId);
    event PendingBalanceUpdated(address recipient, uint256 balance);
    event LiquidityUpdated();

    error ETHTransferFailed();
    error NoFeeRecipientSet();
    error UnsupportedFromToken();
    error UnsupportedToToken();
    error SlippageError();
    error InvalidAmountIn();
    error CCIPRouterIsCursed();
    error InvalidSourceChainSelector();
    error CallerIsNotOtherChainLiquidityManager();
    error InsufficientLiquidity();
    error CCIPMessageReplay();
    error AlreadyInitialized();

    /**
     * @dev Reverts if CCIP's Risk Management contract (ARM) is cursed
     */
    modifier onlyIfNotCursed() {
        IARM arm = IARM(ICCIPRouter(this.getRouter()).getArmProxy());

        if (arm.isCursed()) {
            revert CCIPRouterIsCursed();
        }

        _;
    }

    modifier onlyOtherChainLiquidityManager(uint64 chainSelector, address sender) {
        if (chainSelector != otherChainSelector) {
            // Ensure it's from mainnet
            revert InvalidSourceChainSelector();
        }

        if (sender != otherChainLiquidityManager) {
            // Ensure it's from the other chain's pool manager
            revert CallerIsNotOtherChainLiquidityManager();
        }

        _;
    }

    constructor(address _l2Router, uint64 _otherChainSelector, address _otherChainLiquidityManager)
        CCIPReceiver(_l2Router)
    {
        // Make sure nobody owns the implementation
        _setOwner(address(0));

        otherChainSelector = _otherChainSelector;
        otherChainLiquidityManager = _otherChainLiquidityManager;
    }

    function initialize(address _feeRecipient, uint256 _traderate) external onlyOwner {
        if (initialized) {
            revert AlreadyInitialized();
        }
        initialized = false;
        _setFeeRecipient(_feeRecipient);
        _setTradeRate(_traderate);
    }

    function _setFeeRecipient(address _feeRecipient) internal {
        emit FeeRecipientChanged(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        _setFeeRecipient(_feeRecipient);
    }

    function _setTradeRate(uint256 _traderate) internal {
        // TODO: Set lower and upper bounds
        // Make sure it also accounts for CCIP and redemption fees
        emit TradeRateChanged(traderate, _traderate);
        traderate = _traderate;
    }

    function setTradeRate(uint256 _traderate) external onlyOperatorOrOwner {
        _setTradeRate(_traderate);
    }

    function _transferEth(address receiver, uint256 amount) internal {
        (bool success,) = receiver.call{value: amount}(new bytes(0));
        if (!success) {
            revert ETHTransferFailed();
        }
    }

    function collectFees() external {
        address _recipient = feeRecipient;
        if (_recipient == address(0)) {
            revert NoFeeRecipientSet();
        }

        uint256 _fee = pendingFee;
        if (_fee > 0) {
            pendingFee = 0;
            _transferEth(_recipient, _fee);
            emit FeeCollected(_recipient, _fee);
        }
    }

    function swapExactTokensForTokens(
        address inToken,
        address outToken,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external payable returns (bytes32 messageId) {
        if (inToken != token0) {
            revert UnsupportedToToken();
        }

        if (outToken != token1) {
            revert UnsupportedToToken();
        }

        if (msg.value != amountIn) {
            revert InvalidAmountIn();
        }

        // TODO: Account for CCIP Fees
        uint256 amountOut = (traderate * amountIn) / 1 ether;

        if (amountOut < amountOutMin) {
            revert SlippageError();
        }

        // Calc profit (assuming 1:1 peg)
        uint256 estimatedFeeEarned = amountIn - amountOut;
        pendingFee += estimatedFeeEarned;

        // Build CCIP message
        IRouterClient router = IRouterClient(this.getRouter());

        bytes memory extraArgs = hex"";
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(otherChainLiquidityManager),
            data: abi.encode(to, amountOut),
            tokenAmounts: tokenAmounts,
            extraArgs: extraArgs,
            feeToken: address(0)
        });

        uint256 ccipFees = router.getFee(otherChainSelector, message);

        // TODO: ccipFee not accounted for
        // if (estimatedFeeEarned < ccipFees) {
        //     revert NonProfitableTrade();
        // }

        // Send message to other chain
        messageId = router.ccipSend{value: ccipFees}(otherChainSelector, message);

        emit TransferInitiated(messageId);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message)
        internal
        override
        onlyOtherChainLiquidityManager(message.sourceChainSelector, abi.decode(message.sender, (address)))
        onlyIfNotCursed
    {
        if (messageProcessed[message.messageId]) {
            revert CCIPMessageReplay();
        }
        messageProcessed[message.messageId] = true;

        (address recipient, uint256 amount) = abi.decode(message.data, (address, uint256));

        if (amount <= address(this).balance) {
            // Transfer if there's enough liquidity
            _transferEth(recipient, amount);
            emit TransferCompleted(message.messageId);
        } else {
            // Make it claimable if liquidity is insufficient
            uint256 currBalance = pendingUserBalance[recipient];
            pendingUserBalance[recipient] = currBalance + amount;
            additionalLiquidityNeeded += amount;
            emit PendingBalanceUpdated(recipient, currBalance + amount);
        }
    }

    function claimPendingBalance() external {
        uint256 amount = pendingUserBalance[msg.sender];

        if (amount > address(this).balance) {
            revert InsufficientLiquidity();
        }

        emit PendingBalanceClaimed(msg.sender, amount);
        pendingUserBalance[msg.sender] = 0;
        _transferEth(msg.sender, amount);
    }

    function addLiquidity() public payable {
        uint256 _liquidityNeeded = additionalLiquidityNeeded;
        // Accept all ETH sent to this address as liquidity
        if (_liquidityNeeded >= msg.value) {
            additionalLiquidityNeeded = _liquidityNeeded - msg.value;
        } else if (_liquidityNeeded != 0) {
            additionalLiquidityNeeded = 0;
        }

        emit LiquidityUpdated();
    }

    receive() external payable {
        addLiquidity();
    }
}
