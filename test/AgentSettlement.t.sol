// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/AgentSettlement.sol";
import "../src/interfaces/IHederaScheduleService.sol";

contract AgentSettlementTest is Test {
    AgentSettlement settlement;
    address agent1 = makeAddr("agent1");
    address agent2 = makeAddr("agent2");

    function setUp() public {
        settlement = new AgentSettlement();
        vm.deal(address(this), 100 ether);
    }

    function test_settle() public {
        bytes32 taskId = keccak256("task-001");

        settlement.settle{value: 1 ether}(agent1, taskId);

        assertEq(agent1.balance, 1 ether);
        assertTrue(settlement.settled(taskId));
        assertEq(settlement.totalSettled(), 1 ether);
    }

    function test_settle_emitsEvent() public {
        bytes32 taskId = keccak256("task-002");

        vm.expectEmit(true, true, false, true);
        emit AgentSettlement.AgentPaid(agent1, 1 ether, taskId, block.timestamp);

        settlement.settle{value: 1 ether}(agent1, taskId);
    }

    function test_settle_revertsOnDuplicate() public {
        bytes32 taskId = keccak256("task-dup");
        settlement.settle{value: 1 ether}(agent1, taskId);

        vm.expectRevert(AgentSettlement.AlreadySettled.selector);
        settlement.settle{value: 1 ether}(agent1, taskId);
    }

    function test_settle_revertsOnZeroAddress() public {
        vm.expectRevert(AgentSettlement.ZeroAddress.selector);
        settlement.settle{value: 1 ether}(address(0), keccak256("task-x"));
    }

    function test_settle_revertsOnZeroAmount() public {
        vm.expectRevert(AgentSettlement.ZeroAmount.selector);
        settlement.settle{value: 0}(agent1, keccak256("task-y"));
    }

    function test_settle_revertsUnauthorized() public {
        vm.deal(agent1, 10 ether);
        vm.prank(agent1);
        vm.expectRevert(AgentSettlement.Unauthorized.selector);
        settlement.settle{value: 1 ether}(agent2, keccak256("task-z"));
    }

    function test_batchSettle() public {
        address[] memory agents = new address[](2);
        agents[0] = agent1;
        agents[1] = agent2;

        bytes32[] memory taskIds = new bytes32[](2);
        taskIds[0] = keccak256("batch-1");
        taskIds[1] = keccak256("batch-2");

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        settlement.batchSettle{value: 3 ether}(agents, taskIds, amounts);

        assertEq(agent1.balance, 1 ether);
        assertEq(agent2.balance, 2 ether);
        assertEq(settlement.totalSettled(), 3 ether);
        assertTrue(settlement.settled(taskIds[0]));
        assertTrue(settlement.settled(taskIds[1]));
    }

    function test_batchSettle_revertsArrayMismatch() public {
        address[] memory agents = new address[](2);
        bytes32[] memory taskIds = new bytes32[](1);
        uint256[] memory amounts = new uint256[](2);

        vm.expectRevert(AgentSettlement.ArrayLengthMismatch.selector);
        settlement.batchSettle{value: 1 ether}(agents, taskIds, amounts);
    }

    function test_transferOwnership() public {
        settlement.transferOwnership(agent1);
        assertEq(settlement.owner(), agent1);
    }

    function test_transferOwnership_revertsZeroAddress() public {
        vm.expectRevert(AgentSettlement.ZeroAddress.selector);
        settlement.transferOwnership(address(0));
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

    function test_scheduleBatchSettle() public {
        _mockScheduleService(true);

        address[] memory agents = new address[](1);
        agents[0] = agent1;
        bytes32[] memory taskIds = new bytes32[](1);
        taskIds[0] = keccak256("sched-1");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        settlement.scheduleBatchSettle{value: 1 ether}(
            agents, taskIds, amounts, block.timestamp + 1 hours
        );
    }

    function test_scheduleBatchSettle_revertsNoCapacity() public {
        _mockScheduleService(false);

        address[] memory agents = new address[](1);
        agents[0] = agent1;
        bytes32[] memory taskIds = new bytes32[](1);
        taskIds[0] = keccak256("sched-2");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.expectRevert("no schedule capacity");
        settlement.scheduleBatchSettle{value: 1 ether}(
            agents, taskIds, amounts, block.timestamp + 1 hours
        );
    }

    receive() external payable {}
}
