// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ObeyVault} from "../src/ObeyVault.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ObeyVaultTest is Test {
    ObeyVault public vault;
    ERC20Mock public usdc;

    address guardian = address(this);  // test contract is deployer = guardian
    address agentAddr = address(0xA1);
    address user = address(0xB1);
    address randomToken = address(0xC1);

    // Dummy Uniswap addresses (not called in these tests)
    address swapRouter = address(0xD1);
    address uniFactory = address(0xE1);

    function setUp() public {
        usdc = new ERC20Mock();
        vault = new ObeyVault(
            IERC20(address(usdc)),
            agentAddr,
            swapRouter,
            uniFactory,
            1000e6,   // maxSwapSize: 1000 USDC
            10000e6,  // maxDailyVolume: 10,000 USDC
            100        // maxSlippageBps: 1%
        );
    }

    // --- Guardian Tests ---

    function test_guardianCanSetAgent() public {
        address newAgent = address(0xA2);
        vault.setAgent(newAgent);
        assertEq(vault.agent(), newAgent);
    }

    function test_nonGuardianCannotSetAgent() public {
        vm.prank(user);
        vm.expectRevert(ObeyVault.OnlyGuardian.selector);
        vault.setAgent(address(0xA2));
    }

    function test_guardianCanApproveToken() public {
        vault.setApprovedToken(randomToken, true);
        assertTrue(vault.approvedTokens(randomToken));

        vault.setApprovedToken(randomToken, false);
        assertFalse(vault.approvedTokens(randomToken));
    }

    function test_guardianCanPause() public {
        vault.pause();
        assertTrue(vault.paused());

        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_guardianCanSetMaxSwapSize() public {
        vault.setMaxSwapSize(5000e6);
        assertEq(vault.maxSwapSize(), 5000e6);
    }

    function test_guardianCanSetMaxDailyVolume() public {
        vault.setMaxDailyVolume(50000e6);
        assertEq(vault.maxDailyVolume(), 50000e6);
    }

    // --- Deposit / Redeem Tests ---

    function test_depositAndReceiveShares() public {
        uint256 depositAmount = 1000e6;
        usdc.mint(user, depositAmount);

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);
        vm.stopPrank();

        assertGt(shares, 0, "Should receive shares");
        assertEq(vault.balanceOf(user), shares, "Share balance mismatch");
        assertEq(usdc.balanceOf(address(vault)), depositAmount, "Vault should hold USDC");
    }

    function test_redeemReturnsAssets() public {
        uint256 depositAmount = 1000e6;
        usdc.mint(user, depositAmount);

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);

        uint256 assets = vault.redeem(shares, user, user);
        vm.stopPrank();

        assertEq(assets, depositAmount, "Should get back full deposit");
        assertEq(usdc.balanceOf(user), depositAmount, "User USDC balance restored");
        assertEq(vault.balanceOf(user), 0, "Shares should be burned");
    }

    function test_depositWhenPausedReverts() public {
        vault.pause();

        uint256 depositAmount = 1000e6;
        usdc.mint(user, depositAmount);

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vm.expectRevert();
        vault.deposit(depositAmount, user);
        vm.stopPrank();
    }

    // --- Swap Boundary Tests ---

    function test_executeSwap_onlyAgent() public {
        vm.prank(user);
        vm.expectRevert(ObeyVault.OnlyAgent.selector);
        vault.executeSwap(
            address(usdc),
            randomToken,
            100e6,
            90e6,
            bytes("test")
        );
    }

    function test_executeSwap_unapprovedTokenReverts() public {
        vm.prank(agentAddr);
        vm.expectRevert(
            abi.encodeWithSelector(ObeyVault.TokenNotApproved.selector, randomToken)
        );
        vault.executeSwap(
            address(usdc),
            randomToken,
            100e6,
            90e6,
            bytes("test")
        );
    }

    function test_executeSwap_exceedsMaxSizeReverts() public {
        vault.setApprovedToken(randomToken, true);

        vm.prank(agentAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                ObeyVault.SwapExceedsMaxSize.selector,
                2000e6,
                1000e6
            )
        );
        vault.executeSwap(
            address(usdc),
            randomToken,
            2000e6,
            1800e6,
            bytes("too big")
        );
    }

    function test_executeSwap_dailyVolumeCapEnforced() public {
        vault.setApprovedToken(randomToken, true);
        vault.setMaxSwapSize(15000e6);

        vm.prank(agentAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                ObeyVault.DailyVolumeExceeded.selector,
                11000e6,
                10000e6
            )
        );
        vault.executeSwap(
            address(usdc),
            randomToken,
            11000e6,
            10000e6,
            bytes("over daily limit")
        );
    }

    function test_executeSwap_whenPausedReverts() public {
        vault.setApprovedToken(randomToken, true);
        vault.pause();

        vm.prank(agentAddr);
        vm.expectRevert();
        vault.executeSwap(
            address(usdc),
            randomToken,
            100e6,
            90e6,
            bytes("paused")
        );
    }

    // --- TWAP / Held Token Tests ---

    function test_heldTokensTracking() public {
        assertEq(vault.heldTokenCount(), 0);

        uint256 depositAmount = 1000e6;
        usdc.mint(user, depositAmount);

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        assertEq(vault.totalAssets(), depositAmount);
        assertEq(vault.heldTokenCount(), 0);
    }
}
