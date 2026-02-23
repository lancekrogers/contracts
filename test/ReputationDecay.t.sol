// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ReputationDecay.sol";
import "../src/interfaces/IHederaScheduleService.sol";

contract ReputationDecayTest is Test {
    ReputationDecay reputation;
    address agent1 = makeAddr("agent1");
    address agent2 = makeAddr("agent2");

    function setUp() public {
        reputation = new ReputationDecay();
    }

    function test_updateReputation_positive() public {
        reputation.updateReputation(agent1, 100);
        assertEq(reputation.getReputation(agent1), 100);
    }

    function test_updateReputation_negative() public {
        reputation.updateReputation(agent1, 100);
        reputation.updateReputation(agent1, -30);
        assertEq(reputation.getReputation(agent1), 70);
    }

    function test_updateReputation_clampsToZero() public {
        reputation.updateReputation(agent1, 10);
        reputation.updateReputation(agent1, -100);
        assertEq(reputation.getReputation(agent1), 0);
    }

    function test_updateReputation_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ReputationDecay.ReputationUpdated(agent1, 100, 100, block.timestamp);

        reputation.updateReputation(agent1, 100);
    }

    function test_updateReputation_revertsZeroAddress() public {
        vm.expectRevert(ReputationDecay.ZeroAddress.selector);
        reputation.updateReputation(address(0), 100);
    }

    function test_updateReputation_revertsUnauthorized() public {
        vm.prank(agent1);
        vm.expectRevert(ReputationDecay.Unauthorized.selector);
        reputation.updateReputation(agent2, 100);
    }

    function test_decay_reducesScoreOverTime() public {
        // Set decay rate to 1 point per second for predictable testing.
        reputation.setDecayRate(1e18);
        reputation.updateReputation(agent1, 3600);

        // Advance 1800 seconds — score should be 3600 - 1800 = 1800.
        vm.warp(block.timestamp + 1800);
        assertEq(reputation.getReputation(agent1), 1800);
    }

    function test_decay_clampsToZero() public {
        reputation.setDecayRate(1e18); // 1 point per second
        reputation.updateReputation(agent1, 100);

        // Advance 200 seconds — should clamp to 0.
        vm.warp(block.timestamp + 200);
        assertEq(reputation.getReputation(agent1), 0);
    }

    function test_decay_resetsOnUpdate() public {
        reputation.setDecayRate(1e18); // 1 point per second
        reputation.updateReputation(agent1, 1000);

        // Advance 500 seconds — score decays to 500.
        vm.warp(block.timestamp + 500);
        assertEq(reputation.getReputation(agent1), 500);

        // Update with +200 — decayed score 500 + 200 = 700, timer resets.
        reputation.updateReputation(agent1, 200);
        assertEq(reputation.getReputation(agent1), 700);
    }

    function test_getRawReputation() public {
        reputation.setDecayRate(1e18); // 1 point per second
        reputation.updateReputation(agent1, 1000);
        vm.warp(block.timestamp + 500);

        (uint256 rawScore, uint256 lastUpdated) = reputation.getRawReputation(agent1);
        assertEq(rawScore, 1000);
        assertTrue(lastUpdated > 0);

        // Decayed score should be different from raw.
        assertEq(reputation.getReputation(agent1), 500);
    }

    function test_defaultDecayRate_1pointPerHour() public {
        // Default rate: ~1 point per hour (integer truncation adds ~1 second).
        reputation.updateReputation(agent1, 100);

        // After 2 hours (7200s), decay = 7200 * (1e18/3600) / 1e18 = ~2 points.
        vm.warp(block.timestamp + 7200);
        assertTrue(reputation.getReputation(agent1) <= 99);
        assertTrue(reputation.getReputation(agent1) >= 98);
    }

    function test_setDecayRate() public {
        uint256 newRate = uint256(1e18) / 60; // 1 point per minute.
        reputation.setDecayRate(newRate);
        assertEq(reputation.decayRatePerSecond(), newRate);
    }

    function test_setDecayRate_revertsOnZero() public {
        vm.expectRevert(ReputationDecay.InvalidDecayRate.selector);
        reputation.setDecayRate(0);
    }

    function test_multipleAgents_independent() public {
        reputation.updateReputation(agent1, 100);
        reputation.updateReputation(agent2, 200);

        assertEq(reputation.getReputation(agent1), 100);
        assertEq(reputation.getReputation(agent2), 200);
    }

    function test_transferOwnership() public {
        reputation.transferOwnership(agent1);
        assertEq(reputation.owner(), agent1);
    }

    // ── HIP-1215 Scheduling Tests ────────────────────────────────────

    address constant SCHEDULE_ADDR = address(0x167);

    function _mockScheduleService(bool hasCapacity) internal {
        vm.etch(SCHEDULE_ADDR, hex"00");
        vm.mockCall(
            SCHEDULE_ADDR,
            abi.encodeWithSelector(IHederaScheduleService.hasScheduleCapacity.selector),
            abi.encode(hasCapacity)
        );
        vm.mockCall(
            SCHEDULE_ADDR,
            abi.encodeWithSelector(IHederaScheduleService.scheduleNative.selector),
            abi.encode(address(0xBEEF))
        );
    }

    function test_scheduleDecay() public {
        _mockScheduleService(true);

        address[] memory agents = new address[](2);
        agents[0] = agent1;
        agents[1] = agent2;

        reputation.scheduleDecay(agents, block.timestamp + 1 hours);
    }

    function test_scheduleDecay_revertsNoCapacity() public {
        _mockScheduleService(false);

        address[] memory agents = new address[](1);
        agents[0] = agent1;

        vm.expectRevert("no schedule capacity");
        reputation.scheduleDecay(agents, block.timestamp + 1 hours);
    }

    function test_processDecay() public {
        reputation.setDecayRate(1e18); // 1 point per second
        reputation.updateReputation(agent1, 1000);

        vm.warp(block.timestamp + 500);

        address[] memory agents = new address[](1);
        agents[0] = agent1;
        reputation.processDecay(agents);

        // After processDecay, score should be persisted as decayed value.
        assertEq(reputation.getReputation(agent1), 500);
    }
}
