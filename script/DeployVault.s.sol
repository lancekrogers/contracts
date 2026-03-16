// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ObeyVault} from "../src/ObeyVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployVault is Script {
    // --- Base Sepolia Addresses ---
    address constant SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant SEPOLIA_SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant SEPOLIA_FACTORY = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

    // --- Base Mainnet Addresses ---
    address constant MAINNET_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant MAINNET_SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant MAINNET_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

    // --- WETH on Base (same for both networks) ---
    address constant WETH = 0x4200000000000000000000000000000000000006;

    // --- Default Parameters ---
    uint256 constant MAX_SWAP_SIZE = 1000e6;      // 1,000 USDC
    uint256 constant MAX_DAILY_VOLUME = 10000e6;   // 10,000 USDC
    uint256 constant MAX_SLIPPAGE_BPS = 100;       // 1%

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address agentAddress = vm.envAddress("AGENT_ADDRESS");
        bool isMainnet = vm.envOr("MAINNET", false);

        address usdc;
        address swapRouter;
        address factory;

        if (isMainnet) {
            usdc = MAINNET_USDC;
            swapRouter = MAINNET_SWAP_ROUTER;
            factory = MAINNET_FACTORY;
            console2.log("Deploying to BASE MAINNET");
        } else {
            usdc = SEPOLIA_USDC;
            swapRouter = SEPOLIA_SWAP_ROUTER;
            factory = SEPOLIA_FACTORY;
            console2.log("Deploying to BASE SEPOLIA");
        }

        console2.log("Agent:", agentAddress);
        console2.log("USDC:", usdc);
        console2.log("SwapRouter:", swapRouter);
        console2.log("Factory:", factory);

        vm.startBroadcast(deployerPrivateKey);

        ObeyVault vault = new ObeyVault(
            IERC20(usdc),
            agentAddress,
            swapRouter,
            factory,
            MAX_SWAP_SIZE,
            MAX_DAILY_VOLUME,
            MAX_SLIPPAGE_BPS
        );

        // Auto-approve WETH
        vault.setApprovedToken(WETH, true);

        vm.stopBroadcast();

        console2.log("ObeyVault deployed at:", address(vault));
        console2.log("Guardian (deployer):", vault.guardian());
        console2.log("Agent:", vault.agent());
        console2.log("WETH approved:", vault.approvedTokens(WETH));
    }
}
