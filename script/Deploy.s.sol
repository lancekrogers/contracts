// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/AgentSettlement.sol";
import "../src/ReputationDecay.sol";

/// @title Deploy
/// @notice Deploys AgentSettlement and ReputationDecay to Hedera testnet EVM.
/// Usage: forge script script/Deploy.s.sol --rpc-url $HEDERA_RPC --broadcast --private-key $PRIVATE_KEY
contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        AgentSettlement settlement = new AgentSettlement();
        ReputationDecay reputation = new ReputationDecay();

        vm.stopBroadcast();

        console.log("AgentSettlement deployed at:", address(settlement));
        console.log("ReputationDecay deployed at:", address(reputation));
    }
}
