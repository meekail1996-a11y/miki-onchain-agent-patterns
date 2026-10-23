# On-chain Agent Patterns

Reference implementations for AI agents that interact with smart contracts.

## Why this repo exists

Most "AI agents" on-chain are just LLM wrappers with a wallet attached. They work in demos. They break in production.

The real engineering challenge is the gap between **deciding** and **executing**.

This repository documents practical patterns for bridging that gap — with working code.

## Patterns at a glance

| Pattern | Trust | Latency | Use Case | Status |
| :--- | :--- | :--- | :--- | :--- |
| 1. Planner / Executor | High | Low | Retail DeFi, simple actions | ✅ Implemented |
| 2. Bounded Autonomy | Medium | Medium | Automated strategies | 🚧 Planned |
| 3. Multi-agent + Arbitration | Highest | High | Institutional / high-value | 🚧 Planned |

📖 **[Full pattern breakdown](docs/patterns.md)**  
🔒 **[Security checklist](docs/security.md)**

## Quick Start (Pattern 1)

```bash
git clone https://github.com/meekail1996-a11y/miki-onchain-agent-patterns
cd miki-onchain-agent-patterns
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts
forge test
Project Structure
text

├── contracts/          # Solidity implementations
│   └── Pattern1_PlannerExecutor.sol
├── scripts/            # Off-chain signing scripts (Python)
│   └── sign_intent.py
├── test/               # Foundry tests
└── docs/
    ├── patterns.md     # Deep dive into each pattern
    └── security.md     # Security checklist

Pattern 1: Planner / Executor (Current)

    The AI (Planner) creates a signed Intent

    The smart contract (Executor) verifies the signature and executes it

    Built-in protections: nonce + deadline

This is the safest and simplest pattern for most use cases.

Contributing
This is being built in public. Feedback, issues, and PRs are very welcome — especially for Pattern 2 and 3.

License
MIT



