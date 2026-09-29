# On-chain Agent Patterns

Reference implementations for AI agents that interact with smart contracts.

## Why this repo exists

Most "AI agents" on-chain are just LLM wrappers with a wallet attached. They work in demos, break in production.

The gap between *deciding* and *executing* is where the real engineering happens.

This repo documents patterns that actually work.

## Patterns

### Pattern 1: Planner / Executor

The LLM only outputs a signed *intent*. A separate contract validates and executes it.

- LLM is stateless (safe)
- Validation is deterministic (auditable)
- Execution is atomic (no partial state)

**Use case:** retail DeFi, low-latency operations, safest starting point.

### Pattern 2: Bounded Autonomy

The LLM runs in a TEE and holds a session key with hard constraints
(whitelisted targets, max spend per tx, expiry).

The chain doesn't trust the LLM. The chain trusts the constraints.

**Use case:** automated strategies, medium-latency, medium-trust.

### Pattern 3: Multi-agent with Arbitration

Multiple specialized agents (planner, executor, auditor) coordinate.
Disagreements go to a dispute contract.

**Use case:** institutional / high-value operations.

## Status

| Pattern | Status | Code |
|---|---|---|
| 1 — Planner/Executor | ✅ Reference impl | `contracts/Pattern1_PlannerExecutor.sol` |
| 2 — Bounded Autonomy | 🚧 In progress | — |
| 3 — Multi-agent | 📋 Planned | — |

## Quick start (Pattern 1)

```bash
git clone https://github.com/meekail19/miki-onchain-agent-patterns
cd miki-onchain-agent-patterns
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts
forge test
