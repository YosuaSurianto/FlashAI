// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/FlashAICredits.sol";

/**
 * @notice Deploy FlashAICredits to Celo Alfajores or Mainnet
 *
 * === Alfajores (Testnet) ===
 * forge script script/Deploy.s.sol \
 *   --rpc-url alfajores \
 *   --broadcast \
 *   -vvvv
 *
 * === Celo Mainnet (dengan auto-verify) ===
 * forge script script/Deploy.s.sol \
 *   --rpc-url celo \
 *   --broadcast \
 *   --verify \
 *   -vvvv
 *
 * Required env vars (.env):
 *   DEPLOYER_PRIVATE_KEY   = 0x...  (deployer wallet private key)
 *   CELOSCAN_API_KEY       = ...    (dari celoscan.io/myapikey)
 */
contract DeployFlashAI is Script {
    // ─── cUSD Addresses ───────────────────────────────────────────────────────

    // Celo Mainnet cUSD
    address constant CUSD_MAINNET    = 0x765DE816845861e75A25fCA122bb6898B8B1282a;

    // Alfajores Testnet cUSD
    address constant CUSD_ALFAJORES  = 0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        // Auto-detect network: Celo Mainnet chainId=42220, Alfajores=44787
        address cUSD = block.chainid == 42220 ? CUSD_MAINNET : CUSD_ALFAJORES;

        console.log("====================================");
        console.log("FlashAI Deployment");
        console.log("====================================");
        console.log("Chain ID    :", block.chainid);
        console.log("Network     :", block.chainid == 42220 ? "Celo Mainnet" : "Alfajores Testnet");
        console.log("Deployer    :", deployer);
        console.log("cUSD        :", cUSD);
        console.log("====================================");

        vm.startBroadcast(deployerKey);

        FlashAICredits flashai = new FlashAICredits(cUSD);

        vm.stopBroadcast();

        console.log("");
        console.log(">> FlashAICredits deployed at:", address(flashai));
        console.log("");
        console.log("Next steps:");
        console.log("  1. Copy contract address above");
        console.log("  2. Run SetAgent.s.sol to set backend agent wallet");
        console.log("  3. Fund agent wallet with 5+ CELO for gas");
        console.log("  4. Copy ABI from out/FlashAICredits.sol/FlashAICredits.json to Go backend");
        console.log("");
        console.log("SetAgent command:");
        console.log("  forge script script/SetAgent.s.sol \\");
        console.log("    --rpc-url <network> --broadcast \\");
        console.log("    --sig 'run(address,address)' <contractAddr> <agentAddr>");
    }
}
