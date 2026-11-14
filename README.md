
# On-chain Agent Patterns

[![Tests](https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/actions/workflows/tests.yml/badge.svg)](https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/actions/workflows/tests.yml) [![Latest Release](https://img.shields.io/github/v/release/meekail1996-a11y/miki-onchain-agent-patterns)](https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/releases)

**A learning-oriented reference project for constrained AI-agent interactions with smart contracts.**

This repository explores how to separate off-chain AI decision-making from on-chain execution authority.

An AI agent may propose an action, but it should not receive unrestricted permission to execute arbitrary transactions. Instead, a dedicated signer authorizes a structured `Intent`, and an on-chain Executor validates that authorization before making an external call.

> **Core principle:** The Planner proposes. The Executor enforces.

[Architecture](#architecture) · [Patterns](#patterns) · [Security Model](#security-model) · [Quick Start](#quick-start) · [Testing](#testing) · [Roadmap](#roadmap) · [Changelog](CHANGELOG.md) · [Security Policy](SECURITY.md)

---

## Why this project exists

Connecting an AI agent directly to a wallet can create dangerous security assumptions.

An agent may misunderstand a request, generate unexpected calldata, or be influenced by malicious input. Even when its reasoning appears correct, its proposed action should not automatically become an authorized blockchain transaction.

This project demonstrates a more constrained workflow:

1. **Planner:** prepares a structured action off-chain.
2. **Signer:** authorizes the exact `Intent` using a dedicated signing key.
3. **Executor:** verifies the signature and enforces on-chain rules.
4. **Target:** receives the authorized external call.

The goal is not to prove that an AI agent always makes safe decisions. The goal is to demonstrate how smart contracts can enforce explicit execution constraints independently of the agent's reasoning.

## Architecture

```text
User / Application
       |
       v
    Planner
 (AI / Off-chain logic)
       |
       v
 Optional Policy /
  Review Layer
       |
       v
    Signer
(Intent authorization)
       |
       v
 On-chain Executor
       |
       v
  Target Contract
```

The optional policy or review layer is an architectural possibility, not a claim that every pattern in this repository implements such a layer.

## Patterns

### Pattern 1 — Planner / Executor

**Contract:** `contracts/Pattern1_PlannerExecutor.sol`

Demonstrates a signed `Intent` execution model using EIP-712 typed-data signatures.

An Intent contains:

- `target`: destination contract.
- `value`: native currency amount in wei.
- `data`: encoded call data.
- `nonce`: replay-protection value.
- `deadline`: expiration timestamp.

The Executor validates the signature, checks the expected nonce and deadline, and executes the authorized call.

**Security properties demonstrated:**

- Typed-data signature verification.
- Signer authorization.
- Nonce-based replay protection.
- Deadline enforcement.

**Limitations:**

- A valid signed Intent may be submitted by someone other than the signer.
- The pattern does not implement a target allowlist or daily spending cap.
- It does not independently establish that the target contract or calldata is safe.
- A compromised signer key can authorize malicious Intents.
- The signer authorizes the exact Intent, but signature verification does not establish that the intended action is safe.

### Pattern 2 — Bounded Autonomy

**Contract:** `contracts/Pattern2_BoundedAutonomy.sol`

Extends Pattern 1 with additional execution constraints.

**Implemented controls:**

- Admin-managed target allowlist.
- Daily spending cap based on `intent.value`.
- Emergency stop and resume controls.
- Spending accounting before the external execution call.

The contract checks whether the target is allowlisted, resets the daily accounting period when necessary, verifies the spending cap, records the proposed spending, and then delegates execution to Pattern 1.

**Reentrancy consideration:**

Spending is recorded before the external call. This ensures that a reentrant execution attempt encounters the updated spending amount.

A targeted adversarial test checks an attempt to bypass the daily cap through reentrancy.

**Limitations:**

- The daily cap tracks native currency represented by `intent.value`; it does not account for ERC-20 transfers or other token exposure.
- Administration is centralized in a single admin address.
- Multisig administration and timelocked changes are not implemented.
- The allowlist restricts destination addresses but does not validate the safety of individual functions or calldata.
- The reentrancy test covers specific attack scenarios, not every possible vulnerability.

### Pattern 3 — Multi-Agent Arbitration

**Contract:** `contracts/Pattern3_MultiAgentArbitration.sol`

Demonstrates a multi-agent proposal and arbiter-controlled approval workflow.

**Implemented controls:**

- Arbiter-managed agent registration and removal.
- Proposals submitted by registered agents.
- One vote per registered agent per proposal.
- A proposal-specific quorum calculated when the proposal is created.
- Arbiter-controlled approval or rejection.
- Nonce reservation to prevent multiple proposals from using the same nonce.
- Execution through the inherited Planner / Executor mechanism.
- Reentrancy protection during arbitration resolution.

**Voting and quorum behavior:**

- The quorum is calculated as `(agentCount / 2) + 1` when a proposal is created.
- An approval requires the number of affirmative votes to reach the proposal's stored quorum.
- The quorum is a snapshot and does not change when agents are subsequently removed.
- Agents registered after a proposal is created cannot vote on that older proposal.
- Rejection votes do not automatically reject a proposal. The arbiter makes the final rejection decision.
- The arbiter cannot approve a proposal unless its affirmative votes satisfy the stored quorum.

**Nonce behavior:**

- A proposal reserves its Intent nonce when created.
- Two proposals cannot reserve the same nonce simultaneously.
- A proposal with a future nonce can be created before earlier nonces are executed.
- A future-nonce proposal cannot be executed until its nonce matches the Executor's current nonce.
- Rejecting a proposal releases its reserved nonce.

**Roles:**

The signing authority (`agentSigner`) and the registered voting agents serve different purposes.

The signer authorizes the Intent using an EIP-712 signature. Registered agents participate in proposal voting. Registration as a voting agent does not, by itself, grant signing authority.

**Limitations:**

- The arbiter is a centralized authority and makes the final approval or rejection decision.
- The arbiter cannot bypass the proposal's affirmative-vote quorum when approving it.
- Rejection votes do not trigger automatic rejection.
- The quorum is fixed at proposal creation; removing agents does not lower it.
- A proposal may become difficult or impossible to approve if its quorum can no longer be reached.
- The arbiter is configured at deployment; arbiter rotation is not implemented.
- Multisig arbitration and timelocked arbitration are not implemented.
- There is no target allowlist or daily spending cap in Pattern 3.
- The pattern demonstrates controlled arbitration, not decentralized consensus.

## Case Study — Constrained Treasury Payment

### Scenario

Imagine a treasury application that uses an AI agent to prepare a payment of 0.2 ETH to an approved service provider.

The AI agent analyzes the request and proposes the payment. However, the application must not treat the agent's recommendation as sufficient authorization to move funds.

The project’s three patterns demonstrate different ways to constrain this workflow.

### Pattern 1 — Signed Execution

1. The Planner prepares an Intent containing the destination, amount, calldata, nonce, and deadline.
2. The authorized signer signs the exact Intent using EIP-712.
3. The Executor verifies the signature, nonce, and deadline.
4. The Executor performs the external call.

**What this provides:** Explicit signer authorization, typed-data verification, replay protection, and expiration.

**Remaining risk:** Pattern 1 does not restrict destination addresses or impose a daily spending cap. A compromised signer key could authorize an unsafe payment.

### Pattern 2 — Bounded Execution

The same payment is processed through Pattern 2.

Before execution, the contract additionally checks:

- Is the destination included in the admin-managed allowlist?
- Would the payment exceed the configured daily native-currency spending cap?
- Is the contract currently paused?

If these checks pass, spending is recorded before the external call and execution proceeds.

**What this adds:** Destination restrictions, daily native-currency spending limits, and emergency stop/resume controls.

**Remaining risk:** The cap tracks `intent.value`; it does not account for ERC-20 transfers or other token exposure. The allowlist also does not establish that every function or calldata sent to an approved target is safe.

### Pattern 3 — Multi-Agent Arbitration

In a governance-oriented workflow, a registered agent can submit a payment proposal backed by a valid signed Intent.

1. Registered agents review and vote on the proposal.
2. The proposal must satisfy its quorum snapshot to be eligible for approval.
3. The arbiter makes the final approval or rejection decision.
4. If approved, the contract checks the nonce and executes the Intent.
5. If rejected, the reserved nonce is released.

**What this adds:** Agent participation, one vote per agent per proposal, proposal-specific quorum, nonce reservation, and arbiter-controlled resolution.

**Remaining risk:** The arbiter remains a centralized authority. Pattern 3 does not implement a target allowlist or daily spending cap.

### Key Security Tests

| Test | What it catches | Test file |
|---|---|---|
| `test_ReentrancyCannotExceedDailySpendingCap` | Reentrancy attempts to bypass the daily spending cap | `test/Pattern2.t.sol` |
| `test_MultipleTransactionsCannotExceedDailySpendingCap` | Multiple transactions attempting to exceed the daily cap | `test/Pattern2.t.sol` |
| `test_RevertWhenTargetNotAllowed` | Execution targeting an address outside the allowlist | `test/Pattern2.t.sol` |

### Lessons

This scenario illustrates three distinct security boundaries:

| Pattern | Main protection | Important limitation |
|---|---|---|
| Pattern 1 | Signed authorization and replay protection | No target allowlist or spending cap |
| Pattern 2 | Allowlist and daily native-currency cap | Centralized admin; no ERC-20 cap |
| Pattern 3 | Agent voting and quorum-based approval | Centralized arbiter; no target allowlist or spending cap |

The patterns are educational reference designs, not interchangeable production-ready payment systems.

**Key takeaway:** An AI agent may propose a payment, but authorization and execution constraints must be enforced independently of the agent's reasoning.

This case study is illustrative. It does not claim that a live treasury integration or production payment deployment has been implemented or tested.
## What a Signature Does — and Does Not — Prove

An EIP-712 signature binds authorization to the specified typed-data fields and signing domain.

It allows the Executor to verify that the authorized signer approved the particular Intent being submitted.

However, a valid signature does **not** prove:

- That the AI agent reasoned correctly.
- That the proposed action is economically safe.
- That the target contract is trustworthy.
- That the calldata has harmless effects.
- That the wider application or off-chain environment is secure.

Signature verification is one security boundary, not a complete security guarantee.

## Security Model

The project explores several complementary controls:

| Area | Implemented mechanism |
|---|---|
| Authorization | EIP-712 signed Intents |
| Replay protection | Nonce validation |
| Expiration | Intent deadline |
| Target restriction | Pattern 2 allowlist |
| Spending restriction | Pattern 2 daily native-asset cap |
| Emergency control | Pattern 2 stop/resume |
| Agent participation | Pattern 3 registration and voting |
| Proposal quorum | Pattern 3 proposal-specific quorum |
| Nonce reservation | Pattern 3 proposal nonce reservation |
| Arbitration | Pattern 3 arbiter approval/rejection |
| Reentrancy protection | Pattern 2 spending-order protection and Pattern 3 ReentrancyGuard |
| Off-chain signing | Python Intent signer |

The Python signer includes input validation and a mainnet signing guard. Mainnet signing is blocked by default unless `ALLOW_MAINNET_SIGNING=1` is explicitly configured.

### Important risks

- Compromise of the agent signing key can allow unauthorized Intents.
- A valid signed Intent may be submitted by another party.
- Long deadlines increase the period during which an Intent can be submitted.
- Pattern 1 permits arbitrary targets unless additional restrictions are implemented.
- Pattern 2's daily cap only tracks native currency represented by `intent.value`.
- Pattern 2 uses centralized administration.
- Pattern 3 relies on an authoritative arbiter.
- Pattern 3 does not implement target allowlisting or spending limits.
- Environment variables are not a complete key-management solution.
- Passing tests does not prove the absence of vulnerabilities.

### Safer development practices

- Use test-only private keys.
- Never commit private keys, seed phrases, or populated `.env` files.
- Use short Intent deadlines where practical.
- Verify the chain ID, signer, executor, target, nonce, value, and calldata.
- Review target contracts before allowlisting them.
- Monitor administrative actions and execution events.
- Do not use real funds without independent security review and additional hardening.

## Repository Status

| Component | Implementation | Tests |
|---|---|---|
| Pattern 1 — Planner / Executor | Present | Present |
| Pattern 2 — Bounded Autonomy | Present | Present |
| Pattern 3 — Multi-Agent Arbitration | Present | Present |
| Python Intent signer | Present | Present |

The presence of test files does not, by itself, establish that tests have passed. Run the commands in the Testing section or inspect the GitHub Actions results to verify the current status.

## Quick Start

### Requirements

- Git
- Foundry
- Python 3.10 or newer
- Python dependencies listed in `requirements.txt`

### Clone the repository

```bash
git clone https://github.com/meekail1996-a11y/miki-onchain-agent-patterns.git
cd miki-onchain-agent-patterns
git submodule update --init --recursive
```

### Run it yourself

From a fresh clone, this is everything needed to reproduce both suites. No keys,
no network access and no deployment are required:

```bash
git submodule update --init --recursive
forge test                                   # 60 Solidity tests
python -m pip install -r requirements.txt    # first run only
python -m unittest discover -s tests -v      # 7 Python tests
```

Expected tail of the Solidity run:

```text
Ran 6 test suites in 337.48ms (1.05s CPU time): 60 tests passed, 0 failed, 0 skipped (60 total tests)
```

Expected tail of the Python run:

```text
Ran 7 tests in 0.120s

OK
```

What each suite is worth running for:

| Command | What it pins |
|---|---|
| `forge test` | all three patterns, quorum, nonce and reentrancy behaviour |
| `forge test --match-path test/SecurityReview.t.sol` | malleable (high-`s`) signatures, cross-chain replay, the inclusive deadline, expired proposals, nonce squatting, removed-agent voting, ERC-20 transfers bypassing the native cap |
| `forge test --match-path test/Pattern2Fuzz.t.sol` | daily spending-cap accounting under random inputs (256 runs per property) |
| `python -m unittest discover -s tests -v` | EIP-712 digest parity between the Python signer and the Solidity contract |

The signing script is interactive with the environment, not with a wallet prompt. If
you run it unconfigured it fails fast instead of guessing:

```text
Configuration error: Missing required environment variable: PRIVATE_KEY
```

Set `PRIVATE_KEY`, `CHAIN_ID`, `CONTRACT_ADDRESS`, `TARGET_ADDRESS` and
`INTENT_NONCE` (from the executor's public getter) to sign a test Intent.

### Run Solidity tests

```bash
forge test
```

### Install Python dependencies

```bash
python -m pip install -r requirements.txt
```

### Run Python tests

```bash
python -m unittest discover -s tests -v
```

### Sign a test Intent

Refer to the Python signer documentation and example configuration before running the signing script.

Use test-only private keys and never expose real private keys or seed phrases.

## Testing

Run the complete Solidity test suite:

```bash
forge test -vv
```

Run the Python test suite:

```bash
python -m unittest discover -s tests -v
```

The test suites cover signature validation, nonce handling, execution constraints, agent voting, arbitration, and selected adversarial scenarios.

Passing tests demonstrate that the tested scenarios behave as expected. They do not constitute a formal verification or a complete security audit.

## Roadmap

### Completed

- [x] Pattern 1, 2 and 3 reference contracts.
- [x] EIP-712 Intent signing with a Python reference signer.
- [x] Reentrancy-focused adversarial test for Pattern 2's daily spending cap.
- [x] Governance-only execution, per-proposal quorum snapshots and voter eligibility snapshots in Pattern 3.
- [x] Nonce reservation policy and terminal rejection for Pattern 3 proposals.
- [x] Zero-address and invalid-configuration coverage.
- [x] Fuzz tests for the daily spending cap and its accounting invariants.
- [x] Threat model, known limitations and deployment assumptions documented in [Security Model](docs/security.md).
- [x] CI running both the Solidity and Python suites on every push to `main`.

### Planned

- [ ] Multisig or timelocked administrative controls.
- [ ] Two-step arbiter rotation, so a lost arbiter key cannot freeze governance.
- [ ] A separate agent-admission role for Pattern 3.
- [ ] More flexible target and function-level policies.
- [ ] ERC-20 spending limits.
- [ ] Formal verification of critical execution properties.
- [ ] Improved monitoring guidance.

These are potential future directions, not currently implemented features.

---

## Disclaimer

This repository is an educational reference project. It is not intended for production use or the management of real funds without further development, independent security review, and appropriate operational safeguards.
