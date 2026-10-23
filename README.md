# On-chain Agent Patterns

Reference implementations for AI agents that interact with smart contracts.

## Why this repo exists

Most "AI agents" on-chain are just LLM wrappers with a wallet attached. They work in demos, break in production.

The gap between *deciding* and *executing* is where the real engineering happens.

This repo documents patterns that actually work — with code.

## Patterns at a glance

| Pattern | Trust | Latency | Use case |
|---|---|---|---|
| **1. Planner / Executor** | High | Low | Retail DeFi |
| **2. Bounded Autonomy** | Medium | Medium | Automated strategies |
| **3. Multi-agent + Arbitration** | Highest | High | Institutional |

📖 **[Full breakdown →](docs/patterns.md)**

## Quick start (Pattern 1)

```bash
git clone https://github.com/meekail1996-a11y/miki-onchain-agent-patterns
cd miki-onchain-agent-patterns
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts
forge test
.
├── contracts/         Solidity implementations
├── scripts/           Off-chain signer scripts (Python)
├── test/              Foundry tests
└── docs/
    ├── patterns.md    Deep dive into each pattern
    └── security.md    Security checklist for production
