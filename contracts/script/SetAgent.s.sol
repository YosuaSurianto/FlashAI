// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/FlashAICredits.sol";

/**
 * @notice Set the authorizedAgent on an already-deployed FlashAICredits contract
 *
 * Usage:
 * forge script script/SetAgent.s.sol \
 *   --rpc-url celo \
 *   --broadcast \
 *   --sig "run(address,address)" \
 *   <CONTRACT_ADDRESS> \
 *   <AGENT_WALLET_ADDRESS> \
 *   -vvvv
 *
 * Example:
 * forge script script/SetAgent.s.sol \
 *   --rpc-url alfajores \
 *   --broadcast \
 *   --sig "run(address,address)" \
 *   0xYourContractAddress \
 *   0xYourGoBackendWalletAddress \
 *   -vvvv
 *
 * Required env vars:
 *   DEPLOYER_PRIVATE_KEY  = 0x...  (must be the contract owner)
 */
contract SetAgentScript is Script {
    function run(address contractAddr, address agentAddr) external {
        uint256 ownerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address owner    = vm.addr(ownerKey);

        console.log("====================================");
        console.log("SetAuthorizedAgent");
        console.log("====================================");
        console.log("Contract :", contractAddr);
        console.log("Agent    :", agentAddr);
        console.log("Owner    :", owner);
        console.log("====================================");

        require(contractAddr != address(0), "Contract address cannot be zero");
        require(agentAddr    != address(0), "Agent address cannot be zero");

        FlashAICredits flashai = FlashAICredits(contractAddr);

        // Verify caller is actually the owner before broadcasting
        require(flashai.owner() == owner, "Caller is not the contract owner");

        vm.startBroadcast(ownerKey);
        flashai.setAuthorizedAgent(agentAddr);
        vm.stopBroadcast();

        console.log("");
        console.log(">> authorizedAgent set to:", agentAddr);
        console.log("");
        console.log("Verify onchain:");
        console.log("  cast call", contractAddr, "'authorizedAgent()' --rpc-url celo");
    }
}
