# On-chain Agent Patterns

**A learning-oriented reference project for constrained AI-agent interactions with smart contracts.**

This repository explores how to separate off-chain AI decision-making from on-chain execution authority.

An AI agent may propose an action, but it should not receive unrestricted permission to execute arbitrary transactions. Instead, a dedicated signer authorizes a structured `Intent`, and an on-chain Executor validates that authorization before making an external call.

> **Core principle:** The Planner proposes. The Executor enforces.

[Architecture](#architecture) · [Patterns](#patterns) · [Security Model](#security-model) · [Quick Start](#quick-start) · [Testing](#testing) · [Roadmap](#roadmap)

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
- The reentrancy test covers a specific attack scenario, not every possible vulnerability.

### Pattern 3 — Multi-Agent Arbitration

**Contract:** `contracts/Pattern3_MultiAgentArbitration.sol`

Demonstrates a basic multi-agent proposal and arbitration workflow.

**Implemented controls:**

- Arbiter-managed agent registration.
- Proposals submitted by registered agents.
- One vote per registered agent per proposal.
- Arbiter-controlled approval or rejection.
- Execution through the inherited Planner / Executor mechanism.

**Limitations:**

- There is no enforced quorum or majority threshold.
- The arbiter can approve or reject a proposal regardless of the vote count.
- This is an arbiter-controlled workflow, not decentralized consensus.

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
| Arbitration | Pattern 3 arbiter approval/rejection |
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
- Environment variables are not a complete key-management solution.
- Passing tests do not prove the absence of vulnerabilities.

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

Copy `.env.example` to `.env` and configure the required values for a local test deployment. Never commit `.env`.

Example PowerShell environment variables:

```powershell
$env:PRIVATE_KEY="YOUR_TEST_PRIVATE_KEY"
$env:CHAIN_ID="31337"
$env:CONTRACT_ADDRESS="YOUR_LOCAL_EXECUTOR_ADDRESS"
$env:TARGET_ADDRESS="YOUR_TEST_TARGET_ADDRESS"
$env:INTENT_NONCE="0"
```

**Important:** `INTENT_NONCE` must match the Executor's current on-chain nonce for the signer. Do not guess or reuse a nonce. The value `0` is only an example for a fresh local test deployment.

The signing script also supports optional `INTENT_VALUE`, `INTENT_DATA`, and `INTENT_TTL` settings.

Run the script:

```bash
python scripts/sign_intent.py
```

The script produces an EIP-712 signature; it does not submit a blockchain transaction.

**Never use a private key that has been shared publicly or exposed in chat, source code, logs, or screenshots.**

## Testing

Run the test suites independently:

```bash
forge test
```

```bash
python -m unittest discover -s tests -v
```

The repository includes Solidity tests for Patterns 1, 2, and 3, security-focused tests, and Python tests for the Intent signer.

Pattern 2 includes a targeted adversarial test for a reentrant attempt to exceed the daily spending cap.

Test coverage is not exhaustive. Passing tests should not be interpreted as proof that the contracts or signer are free of vulnerabilities.

For continuous integration, inspect the workflow under:

```text
.github/workflows/tests.yml
```

## Project Structure

```text
.
├── contracts/
│   ├── Pattern1_PlannerExecutor.sol
│   ├── Pattern2_BoundedAutonomy.sol
│   └── Pattern3_MultiAgentArbitration.sol
├── scripts/
│   └── sign_intent.py
├── test/
│   ├── Pattern1.t.sol
│   ├── SecurityTests.t.sol
│   └── test/
│       ├── Pattern2.t.sol
│       └── Pattern3.t.sol
├── tests/
│   └── test_sign_intent.py
├── docs/
│   ├── patterns.md
│   └── security.md
├── .github/
│   └── workflows/
│       └── tests.yml
├── .env.example
├── .gitmodules
├── foundry.toml
└── requirements.txt
```

## Roadmap

- [x] Pattern 1: Planner / Executor reference contract
- [x] Pattern 2: Bounded Autonomy contract
- [x] Pattern 3: Multi-Agent Arbitration contract
- [x] Add a reentrancy-focused adversarial test for Pattern 2's daily spending cap
- [ ] Expand adversarial tests for spending accounting and other execution edge cases
- [ ] Add tests for zero-address and invalid configuration cases
- [ ] Decide whether Pattern 3 should enforce a quorum/threshold or remain explicitly arbiter-controlled
- [ ] Improve signer key management and operational guidance
- [ ] Expand threat modeling and document deployment assumptions

## Contributing

Issues, feedback, and pull requests are welcome.

Please do not publish private keys, seed phrases, or exploitable security details in public issues.

## License

This project is licensed under the MIT License. See `LICENSE` for details.