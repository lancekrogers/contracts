// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ISwapRouter02} from "./interfaces/ISwapRouter02.sol";
import {IUniswapV3Factory, IUniswapV3Pool} from "./interfaces/IOracleLibrary.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {FullMath} from "./libraries/FullMath.sol";

contract ObeyVault is ERC4626, Pausable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // --- Roles ---
    address public guardian;
    address public agent;

    // --- Spending Boundaries ---
    mapping(address => bool) public approvedTokens;
    uint256 public maxSwapSize;
    uint256 public maxDailyVolume;
    uint256 public maxSlippageBps;

    // --- Daily Volume Tracking ---
    uint256 public dailyVolumeUsed;
    uint256 public currentDay;

    // --- Token Tracking ---
    EnumerableSet.AddressSet private _heldTokens;

    // --- Uniswap ---
    ISwapRouter02 public immutable swapRouter;
    address public immutable uniswapFactory;

    // --- TWAP ---
    uint32 public constant TWAP_PERIOD = 1800; // 30 minutes

    // --- Events ---
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes reason
    );
    event AgentUpdated(address indexed oldAgent, address indexed newAgent);
    event TokenApprovalUpdated(address indexed token, bool approved);
    event MaxSwapSizeUpdated(uint256 newMax);
    event MaxDailyVolumeUpdated(uint256 newMax);

    // --- Errors ---
    error OnlyGuardian();
    error OnlyAgent();
    error SameToken();
    error TokenNotApproved(address token);
    error SwapExceedsMaxSize(uint256 amount, uint256 max);
    error DailyVolumeExceeded(uint256 used, uint256 max);
    error SlippageTooHigh(uint256 requested, uint256 max);

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert OnlyGuardian();
        _;
    }

    modifier onlyAgent() {
        if (msg.sender != agent) revert OnlyAgent();
        _;
    }

    constructor(
        IERC20 asset_,
        address agent_,
        address swapRouter_,
        address uniswapFactory_,
        uint256 maxSwapSize_,
        uint256 maxDailyVolume_,
        uint256 maxSlippageBps_
    )
        ERC4626(asset_)
        ERC20("OBEY Vault Share", "oVAULT")
    {
        guardian = msg.sender;
        agent = agent_;
        swapRouter = ISwapRouter02(swapRouter_);
        uniswapFactory = uniswapFactory_;
        maxSwapSize = maxSwapSize_;
        maxDailyVolume = maxDailyVolume_;
        maxSlippageBps = maxSlippageBps_;
        currentDay = block.timestamp / 1 days;

        // USDC (the base asset) is always approved
        approvedTokens[address(asset_)] = true;
    }

    // --- Guardian Functions ---

    function setAgent(address newAgent) external onlyGuardian {
        emit AgentUpdated(agent, newAgent);
        agent = newAgent;
    }

    function setApprovedToken(address token, bool approved) external onlyGuardian {
        approvedTokens[token] = approved;
        emit TokenApprovalUpdated(token, approved);
    }

    function setMaxSwapSize(uint256 newMax) external onlyGuardian {
        maxSwapSize = newMax;
        emit MaxSwapSizeUpdated(newMax);
    }

    function setMaxDailyVolume(uint256 newMax) external onlyGuardian {
        maxDailyVolume = newMax;
        emit MaxDailyVolumeUpdated(newMax);
    }

    function pause() external onlyGuardian {
        _pause();
    }

    function unpause() external onlyGuardian {
        _unpause();
    }

    // --- Token View Helpers ---

    function heldTokenCount() external view returns (uint256) {
        return _heldTokens.length();
    }

    function heldTokenAt(uint256 index) external view returns (address) {
        return _heldTokens.at(index);
    }

    // --- ERC-4626 Overrides ---

    function totalAssets() public view override returns (uint256) {
        uint256 total = IERC20(asset()).balanceOf(address(this));

        uint256 len = _heldTokens.length();
        for (uint256 i = 0; i < len; i++) {
            address token = _heldTokens.at(i);
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance == 0) continue;

            uint256 price = _getTWAPPrice(token);
            if (price > 0) {
                total += FullMath.mulDiv(balance, price, 1e18);
            }
        }

        return total;
    }

    function deposit(uint256 assets, address receiver)
        public
        override
        whenNotPaused
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        whenNotPaused
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }

    // --- Swap Execution ---

    function executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata reason
    ) external onlyAgent whenNotPaused returns (uint256 amountOut) {
        if (tokenIn == tokenOut) revert SameToken();
        if (!approvedTokens[tokenOut]) revert TokenNotApproved(tokenOut);

        if (amountIn > maxSwapSize) {
            revert SwapExceedsMaxSize(amountIn, maxSwapSize);
        }

        uint256 today = block.timestamp / 1 days;
        if (today != currentDay) {
            currentDay = today;
            dailyVolumeUsed = 0;
        }

        uint256 newVolume = dailyVolumeUsed + amountIn;
        if (newVolume > maxDailyVolume) {
            revert DailyVolumeExceeded(newVolume, maxDailyVolume);
        }
        dailyVolumeUsed = newVolume;

        uint256 minAcceptable = amountIn * (10000 - maxSlippageBps) / 10000;
        if (amountOutMinimum < minAcceptable) {
            revert SlippageTooHigh(amountOutMinimum, minAcceptable);
        }

        IERC20(tokenIn).forceApprove(address(swapRouter), amountIn);

        amountOut = swapRouter.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 3000,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            })
        );

        if (tokenOut != asset()) {
            _heldTokens.add(tokenOut);
        }
        if (tokenIn != asset() && IERC20(tokenIn).balanceOf(address(this)) == 0) {
            _heldTokens.remove(tokenIn);
        }

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, reason);
    }

    // --- TWAP Oracle ---

    function _getTWAPPrice(address token) internal view returns (uint256 price) {
        address pool = IUniswapV3Factory(uniswapFactory).getPool(
            token, asset(), 3000
        );
        if (pool == address(0)) return 0;

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = TWAP_PERIOD;
        secondsAgos[1] = 0;

        try IUniswapV3Pool(pool).observe(secondsAgos) returns (
            int56[] memory tickCumulatives,
            uint160[] memory
        ) {
            int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
            int24 averageTick = int24(tickDelta / int56(int32(TWAP_PERIOD)));

            uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);

            price = FullMath.mulDiv(
                uint256(sqrtPriceX96) * uint256(sqrtPriceX96),
                1e18,
                1 << 192
            );

            if (IUniswapV3Pool(pool).token0() == asset()) {
                if (price > 0) {
                    price = FullMath.mulDiv(1e18, 1e18, price);
                }
            }
        } catch {
            return 0;
        }
    }
}
