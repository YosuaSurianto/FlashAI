# ⚡ FlashAI — Smart Contracts

Pay-per-use AI credit system on Celo blockchain, built with Foundry.

**Proof of Ship Season 2 | Celo Mainnet | Mei 2026**

---

## Architecture

```
User    → topUp(amount)              → credits[user] += amount    [1 tx by user]
Backend → useCredit(user, cost)      → credits[user] -= cost      [1 tx per AI request]
```

Every AI request = 1 real onchain transaction from the backend agent wallet.

---

## Smart Contract

| Function | Who Calls | Description |
|---|---|---|
| `topUp(amount)` | User | Deposit cUSD credits |
| `useCredit(user, cost, service)` | Backend agent only | Deduct credits per AI request |
| `batchUseCredit(users, costs, services)` | Backend agent only | Bulk deduction |
| `setAuthorizedAgent(agent)` | Owner | Set backend wallet |
| `getBalance(user)` | Anyone | View user credit balance |
| `withdraw()` | Owner | Pull platform revenue |

## Pricing

| Service | Cost |
|---|---|
| Text Generation (short) | 0.02 cUSD |
| Text Generation (long)  | 0.05 cUSD |
| Translation             | 0.02 cUSD |
| Summarizer              | 0.03 cUSD |
| Image Generation        | 0.10 cUSD |

---

## Setup

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone and install deps
git clone <repo>
cd flashai-contracts
forge install OpenZeppelin/openzeppelin-contracts
forge install foundry-rs/forge-std

# Copy env
cp .env.example .env
# Fill in DEPLOYER_PRIVATE_KEY and CELOSCAN_API_KEY
```

---

## Development Workflow

```bash
# Compile
forge build

# Run all tests
forge test -vvv

# Run specific test
forge test --match-test test_TopUp_Success -vvv

# Run fuzz tests
forge test --match-test testFuzz -vvv

# Local fork Celo Mainnet
anvil --fork-url https://feth.celo.org
```

---

## Deployment

```bash
# 1. Deploy to Alfajores testnet first
forge script script/Deploy.s.sol \
  --rpc-url alfajores \
  --broadcast \
  -vvvv

# 2. Deploy to Celo Mainnet + auto verify on Celoscan
forge script script/Deploy.s.sol \
  --rpc-url celo \
  --broadcast \
  --verify \
  -vvvv

# 3. Set backend agent wallet
forge script script/SetAgent.s.sol \
  --rpc-url celo \
  --broadcast \
  --sig "run(address,address)" \
  <CONTRACT_ADDRESS> \
  <AGENT_WALLET_ADDRESS> \
  -vvvv
```

---

## Cast Commands (Debug Onchain)

```bash
# Check user balance
cast call $CONTRACT 'getBalance(address)' $USER_ADDR --rpc-url celo

# Check authorized agent
cast call $CONTRACT 'authorizedAgent()' --rpc-url celo

# Check owner
cast call $CONTRACT 'owner()' --rpc-url celo

# Check total cUSD in contract
cast call $CONTRACT 'totalDeposited()' --rpc-url celo

# Manual useCredit (emergency)
cast send $CONTRACT 'useCredit(address,uint256,string)' \
  $USER_ADDR 20000000000000000 "text_short" \
  --private-key $AGENT_PRIVATE_KEY \
  --rpc-url celo
```

---

## Addresses

| Network | cUSD | FlashAICredits |
|---|---|---|
| Celo Mainnet | `0x765DE816845861e75A25fCA122bb6898B8B1282a` | TBD after deploy |
| Alfajores    | `0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1` | TBD after deploy |

---

## Security

- `useCredit()` — only callable by `authorizedAgent` (backend wallet)
- Agent wallet holds **only CELO for gas**, zero cUSD
- All user cUSD stored **in the smart contract**, not backend
- `ReentrancyGuard` on all state-changing functions
- `SafeERC20` for all token transfers

---

Built with ❤️ for Celo Proof of Ship Season 2