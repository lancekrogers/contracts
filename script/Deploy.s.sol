// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AgentSettlement.sol";
import "../src/ReputationDecay.sol";
import "../src/AgentINFT.sol";

/// @title Deploy
/// @notice Deploys AgentSettlement, ReputationDecay, and AgentINFT.
///
/// Hedera testnet:
///   forge script script/Deploy.s.sol --rpc-url $HEDERA_RPC --broadcast --private-key $PRIVATE_KEY
///
/// 0G Galileo testnet:
///   forge script script/Deploy.s.sol --rpc-url zerog --broadcast --private-key $ZG_CHAIN_PRIVATE_KEY
contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        AgentSettlement settlement = new AgentSettlement();
        ReputationDecay reputation = new ReputationDecay();
        AgentINFT inft = new AgentINFT();

        vm.stopBroadcast();

        console.log("AgentSettlement deployed at:", address(settlement));
        console.log("ReputationDecay deployed at:", address(reputation));
        console.log("AgentINFT deployed at:", address(inft));
    }
}
