# DCA Bot — Buy on Schedule, Not on Impulse

> Dollar-cost averaging as a primitive. Create a plan once, fund it, and the scheduled buys execute automatically every interval - cancel or withdraw leftover capital at any time without penalty.

## What it does

Dollar-cost averaging as a primitive. Create a plan once, fund it, and the scheduled buys execute automatically every interval - cancel or withdraw leftover capital at any time without penalty. The entire lifecycle lives in one contract, every button in the UI calls a real function on it — there is no mock backend.

## Contract

| | |
|---|---|
| File | `contracts/DCABot.sol` |
| Contract name | `DCABot` (inherits `ReentrancyGuard, Ownable`) |
| Solidity | `^0.8.20` |
| State functions | 8 (of which 1 payable) |
| Deployed (mainnet 677) | not yet deployed — placeholder `0x000…000` |

### Function surface

| Function | Type | Returns |
|---|---|---|
| `owner` | view | address |
| `createPlan` | payable | uint256 |
| `executePlan` | write | result / revert |
| `cancelSubscription` | write | result / revert |
| `pausePlan` | write | result / revert |
| `resumePlan` | write | result / revert |
| `getPlan` | view | address user, address token, uint256 amount, uint256 interval, uint256 lastExec, uint256 totalExec, uint256 maxExec, bool active |
| `getRemaining` | view | uint256 |

### Events

| Event | Signature |
|---|---|
| `OwnershipTransferred` | (address indexed previousOwner, address indexed newOwner) |
| `PlanCreated` | (uint256 indexed pid, address indexed user, address token, uint256 amount, uint256 interval) |
| `PlanExecuted` | (uint256 indexed pid, address indexed user, uint256 amount) |
| `PlanPaused` | (uint256 indexed pid, address indexed user) |
| `PlanResumed` | (uint256 indexed pid, address indexed user) |
| `PlanCancelled` | (uint256 indexed pid, address indexed user, uint256 refund) |

## Network

| | |
|---|---|
| Chain | BOT Chain Mainnet (chainId `677`) |
| RPC | `https://rpc.botchain.ai` |
| Explorer | `https://scan.botchain.ai` |
| Native currency | BOT (18 decimals) |
| Testnet | BOT Chain Testnet (chainId `968`) - `https://rpc.bohr.life` |

## Frontend

- **Wallet connection** - [Reown/AppKit](https://reown.com) (Web3Modal v2, inline modal, `subscribeAccount` / `subscribeNetwork`)
- **Web3 library** - ethers.js v6 (`BrowserProvider`, `Contract`, `parseEther`)
- **Animation** - GSAP 3 + ScrollTrigger (`expo.out` entrances, `prefers-reduced-motion` fallback renders content instantly)
- **Zero build step** - single `index.html`, CDN imports via ESM import map; no bundler, no framework runtime
- **Accessibility** - auto-generated `aria-label`s on all binary and form controls, focus-visible styles, button busy states

## Run it locally

```bash
git clone https://github.com/Henoch4/dca-bot.git
cd dca-bot
# open the frontend directly (no build step)
start frontend/index.html   # Windows
# or serve it if your browser blocks file:// modules:
npx serve frontend
```

> **Note** — contract addresses: the UI reads its deploy target from the `CA` constant at the top of the inline script. Until the contract is deployed to mainnet 677, the demo runs against the deterministic sample data built into the page; after deployment, set `CA['677']` to the real address and every button goes live.