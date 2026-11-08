# On-chain Agent Patterns

**A learning-oriented reference project for constrained AI-agent interactions with smart contracts.**

This repository demonstrates an important security boundary: an AI system may propose an action, but it should not receive unrestricted authority to execute it. The Planner reasons off-chain; the on-chain Executor validates an explicitly signed `Intent` before making an external call.

> **Core principle:** The Planner proposes. The Executor enforces. Signing authority stays separate from open-ended model output.

[Architecture](#architecture) · [Patterns](#patterns) · [Security Model](#security-model) · [Quick Start](#quick-start) · [Testing](#testing) · [Roadmap](#roadmap)

---

## Why this project exists

Connecting an LLM directly to a wallet creates a dangerous coupling between reasoning and financial authority. A model can misunderstand a request, produce unexpected calldata, or be manipulated by untrusted input.

This project explores a more constrained design:

1. The Planner creates a structured action proposal.
2. A dedicated signer authorizes the exact `Intent`.
3. The Executor checks the typed signature, nonce, and deadline.
4. The Executor makes the requested external call.

The repository is an evolving educational reference. It has **not** been presented as a security audit or production-ready financial infrastructure.

---

## Architecture

```text
User / Application
       |
       v
Planner (AI / off-chain logic)
       |
       | structured Intent
       v
Policy / Review (optional off-chain layer)
       |
       v
Dedicated Signer
       |
       | EIP-712 signature
       v
On-chain Executor
       |
       | validated external call
       v
Target contract / protocol
```

The optional policy/review layer may add simulation, target checks, spending policies, monitoring, or human approval. Those controls must not be assumed to exist on-chain unless the relevant contract actually implements them.

---

## Patterns

### Pattern 1: Planner / Executor

**Code:** `contracts/Pattern1_PlannerExecutor.sol`

The base contract accepts an EIP-712 signed `Intent` containing:

| Field | Meaning |
|---|---|
| `target` | Contract address to call |
| `value` | Native currency value, in wei |
| `data` | Calldata for the target call |
| `nonce` | Sequential Executor nonce used for replay protection |
| `deadline` | Unix timestamp after which the Intent expires |

The contract checks the deadline, expected nonce, and recovered signer. It increments the nonce before making the external call.

**Current scope:** signature validation, nonce checking, deadline checking, and an external call.

**Important limitation:** Pattern 1 does not itself provide a target allowlist, spending cap, emergency pause, transaction simulation, or human approval.

### Pattern 2: Bounded Autonomy

**Code:** `contracts/Pattern2_BoundedAutonomy.sol`

This contract extends Pattern 1 with:

- An admin-managed target allowlist.
- A daily spending cap based on `block.timestamp / 1 days`.
- An admin-controlled emergency stop and resume function.
- An admin role assigned to the deployer.

The `execute` function checks the target allowlist, emergency-stop state, and daily cap before delegating to the Pattern 1 execution logic.

**Current scope:** these controls are present in the contract and have a corresponding Foundry test file at `test/test/Pattern2.t.sol`.

**Important limitations to review:** the daily accounting and external-call/reentrancy behaviour need additional adversarial testing. The contract does not provide a cooldown, role separation, multisig administration, or a time-delayed recovery process.

### Pattern 3: Multi-Agent Arbitration

**Code:** `contracts/Pattern3_MultiAgentArbitration.sol`

This contract extends Pattern 1 with:

- An arbiter-managed agent registry.
- Proposal creation by registered agents.
- One vote per registered agent per proposal.
- An arbiter decision to approve or reject a proposal.
- Execution of an approved proposal through the inherited Pattern 1 logic.

**Current scope:** proposal, voting, and arbiter-resolution functions are present in the contract and have a corresponding Foundry test file at `test/test/Pattern3.t.sol`.

**Important limitation:** the current implementation does not enforce a voting threshold or require a majority before execution. The arbiter can approve a proposal regardless of the recorded votes. Therefore, this is an arbiter-controlled proposal workflow, not a trustless consensus mechanism.

---

## Security Model

The implementation demonstrates several controls, but each has a limited scope:

- **Separation of duties:** planning and on-chain execution are separate components.
- **Typed authorization:** EIP-712 binds the signature to the Intent fields and domain.
- **Replay protection:** the Executor nonce prevents reuse of an already-consumed sequential nonce.
- **Expiry:** the deadline limits how long a signed Intent remains valid.
- **Input validation:** the Python signer validates addresses, integer ranges, required environment variables, and calldata hex.
- **Mainnet guard:** the Python signer blocks chain ID `1` by default unless `ALLOW_MAINNET_SIGNING=1` is explicitly set.
- **Pattern 2 controls:** target allowlisting, daily value cap, and emergency stop are implemented in the Pattern 2 contract.
- **Pattern 3 controls:** registered-agent checks and arbiter-only management/resolution are implemented in the Pattern 3 contract.

### Risks and limitations

- If the `agentSigner` private key is compromised, an attacker may authorize arbitrary Intents within the controls of the deployed Executor.
- A valid signed Intent may be submitted by someone other than the intended submitter. The current Intent does not bind a specific relayer or submitter.
- A long deadline increases the period in which a leaked signature may be used.
- The base Pattern 1 contract allows calls to any target named in a valid signed Intent.
- Pattern 2's allowlist and spending cap are only as reliable as their administration and accounting logic; further adversarial tests are needed.
- Pattern 3's arbiter has decisive authority; recorded votes do not currently constrain the arbiter's decision.
- Environment variables are not a secure key-management system by themselves. Protect the host, shell history, process environment, and logs.
- Test success does not establish that the contracts are free of vulnerabilities.

### Safe-use guidance

- Use a dedicated test-only key with no real funds while learning.
- Never commit `.env`, private keys, or seed phrases.
- Verify the chain ID, deployed Executor address, signer address, target address, and nonce independently.
- Do not enable mainnet signing merely because the script permits an explicit opt-in.
- Review and test every target contract that the Executor may call.
- Obtain an independent security review before considering any real-value deployment.

---

## Repository Status

| Component | Code present | Test file present | Notes |
|---|---:|---:|---|
| Pattern 1: Planner / Executor | Yes | Yes | Base signed-Intent execution |
| Pattern 2: Bounded Autonomy | Yes | Yes | Allowlist, daily cap, emergency stop |
| Pattern 3: Multi-Agent Arbitration | Yes | Yes | Arbiter decision is authoritative; votes do not enforce a threshold |
| Python Intent signer | Yes | Yes | Input validation and EIP-712 signing |

The presence of source code or test files is not, by itself, evidence that tests passed. Check the latest GitHub Actions run and/or execute the commands below to verify test results.

---

## Quick Start

### Requirements

- Git
- Foundry (`forge`)
- Python 3.10 or newer, using a version compatible with the pinned Python dependencies

### Clone the repository

```bash
git clone https://github.com/meekail1996-a11y/miki-onchain-agent-patterns.git
cd miki-onchain-agent-patterns
```

### Install Solidity dependencies

The repository tracks `forge-std` and OpenZeppelin as Git submodules. Initialize them with:

```bash
git submodule update --init --recursive
```

If the submodules are not available in your checkout, consult `.gitmodules` and the repository's dependency configuration before installing alternate versions.

### Run Solidity tests

```bash
forge test
```

### Install Python dependencies

```bash
python -m pip install -r requirements.txt
```

### Run Python validation tests

```bash
python -m unittest discover -s tests -v
```

### Sign a test Intent

Copy `.env.example` to `.env` locally and replace the placeholders with values from your own local or test deployment. Do not commit `.env`.

PowerShell example:

```powershell
$env:PRIVATE_KEY = "YOUR_TEST_WALLET_PRIVATE_KEY"
$env:CHAIN_ID = "31337"
$env:CONTRACT_ADDRESS = "YOUR_DEPLOYED_EXECUTOR_ADDRESS"
$env:TARGET_ADDRESS = "YOUR_INTENDED_TARGET_ADDRESS"
$env:INTENT_NONCE = "0"

python scripts/sign_intent.py
```

The script creates a signature; it does not submit a transaction. A signature is sensitive authorization data. Share it only when you understand exactly what it authorizes.

---

## Testing

Run both test suites from the repository root:

```bash
python -m unittest discover -s tests -v
forge test
```

The repository includes Python validation tests and Foundry test files for Patterns 1, 2, and 3, plus Pattern 1 security cases.

**Do not interpret the existence of test files or the commands above as proof that the tests passed.** Confirm the actual terminal output or the status and logs of the relevant GitHub Actions workflow run.

---

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

---

## Roadmap

- [x] Pattern 1: Planner / Executor reference contract
- [x] Pattern 2: Bounded Autonomy contract
- [x] Pattern 3: Multi-Agent Arbitration contract
- [ ] Add adversarial tests for reentrancy and daily spending accounting
- [ ] Add tests for zero-address and invalid configuration cases
- [ ] Decide whether Pattern 3 should enforce a quorum/threshold or remain explicitly arbiter-controlled
- [ ] Improve signer key management and operational guidance
- [ ] Expand threat modeling and document deployment assumptions

---

## Contributing

This project is being built in public. Issues, feedback, and pull requests are welcome, especially around threat modeling, test coverage, policy enforcement, and developer experience.

Do not publish private keys, seed phrases, or exploitable security details in public issues.

---

## License

MIT. See `LICENSE`.
