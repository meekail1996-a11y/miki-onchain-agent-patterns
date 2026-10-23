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

git clone https://github.com/meekail1996-a11y/miki-onchain-agent-patterns
cd miki-onchain-agent-patterns
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts
forge test


## Python Intent Signer

Install the Python dependencies:

```powershell
python -m pip install -r requirements.txt
```

Set configuration in your current PowerShell session (replace the example addresses with addresses from your own local/test deployment):

```powershell
$env:PRIVATE_KEY = "YOUR_TEST_WALLET_PRIVATE_KEY"
$env:CHAIN_ID = "31337"
$env:CONTRACT_ADDRESS = "YOUR_DEPLOYED_EXECUTOR_ADDRESS"
$env:TARGET_ADDRESS = "YOUR_INTENDED_TARGET_ADDRESS"
$env:INTENT_NONCE = "0"
python scripts/sign_intent.py
```

Use a dedicated test-only key with no real funds. Never commit a private key or paste it into chat/issues. The nonce must match the executor's current on-chain `nonce()` value; update it after each successful execution. Mainnet signing is blocked unless `ALLOW_MAINNET_SIGNING=1` is explicitly set.

Run the Python validation tests:

```powershell
python -m unittest discover -s tests -v
```

GitHub Actions runs the Python validation tests and Foundry tests on pushes to `main` and pull requests.

## Project Structure

contracts/          # Solidity implementations
  Pattern1_PlannerExecutor.sol
scripts/            # Off-chain signing scripts (Python)
  sign_intent.py
test/               # Foundry tests
docs/
  patterns.md       # Deep dive into each pattern
  security.md       # Security checklist

## Pattern 1: Planner / Executor (Current)

- The AI (Planner) creates a signed Intent
- The smart contract (Executor) verifies the signature and executes it
- Built-in protections: nonce + deadline

This is the safest and simplest pattern for most use cases.

## Contributing

This is being built in public. Feedback, issues, and PRs are very welcome — especially for Pattern 2 and 3.

## License

MIT
