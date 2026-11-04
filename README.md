# On-chain Agent Patterns

**A security-first reference implementation for AI agents that interact with smart contracts.**

This project explores a simple but important boundary: an AI system can propose an action, but it should not have unrestricted authority to execute it. The Planner reasons about a task; the Executor enforces the rules on-chain.

> **Core principle:** Trust the Planner to propose. Trust the Executor to enforce. Keep signing authority separate from open-ended model output.

[Architecture](#planner--executor-architecture) · [Security model](#security-model) · [Quick start](#quick-start) · [Tests](#testing) · [Roadmap](#roadmap)

---

## Why this project exists

Connecting an LLM directly to a wallet creates a dangerous coupling between reasoning and financial authority. A model can misunderstand a prompt, produce unexpected calldata, or be manipulated by untrusted input.

A safer design introduces a constrained execution boundary. The Planner creates a structured **Intent**. A signer authorizes that exact intent. The smart-contract Executor validates the authorization and applies contract-level checks before making the call.

This repository is a learning-oriented, evolving reference implementation—not a production audit or a guarantee of safety.

## Planner / Executor architecture

```text
 User / Application
        |
        | task or request
        v
 +--------------------+
 |      PLANNER       |  AI / off-chain logic
 | proposes an Intent |
 +--------------------+
        |
        | structured Intent
        v
 +--------------------+       +----------------------+
 | Policy / Review    | ----> | Human approval       |
 | (optional layer)   |       | (when required)      |
 +--------------------+       +----------------------+
        |
        | approved intent
        v
 +--------------------+
 |     SIGNER         |  Dedicated key / wallet
 | signs exact fields |
 +--------------------+
        |
        | EIP-712 signature
        v
 +--------------------+
 |     EXECUTOR       |  Smart contract
 | verifies & checks  |
 +--------------------+
        |
        | authorized call
        v
 | Target contract / protocol |
```

### Responsibilities

| Component | Responsibility | What it should not do |
| --- | --- | --- |
| Planner | Interpret the task and propose target, value, calldata, and execution parameters | Hold an unrestricted private key or decide its own permissions |
| Policy / reviewer | Apply allowlists, value limits, simulation, and optional human approval | Treat model output as trusted by default |
| Signer | Sign the exact typed intent after required checks | Sign arbitrary or unreviewed requests |
| Executor | Verify signature and enforce on-chain constraints | Assume a valid signature makes every target call safe |
| Target | Perform the requested contract operation | Be trusted beyond the guarantees of its own code |

The policy/review layer is an architectural option; it is not implied to be fully implemented in this repository.

### Intent format

Pattern 1 signs an EIP-712 typed `Intent` with these fields:

| Field | Meaning |
| --- | --- |
| `target` | Contract address the Executor is allowed to call |
| `value` | Native currency value, in wei |
| `data` | Calldata for the target call |
| `nonce` | Executor nonce used to prevent replay |
| `deadline` | Unix timestamp after which the intent expires |

The EIP-712 domain binds the signature to the domain name/version, chain ID, and verifying Executor contract. This helps prevent cross-domain replay, while the nonce and deadline provide additional replay and expiry protections.

**Important:** A signature authorizes the exact encoded intent; it does not prove that the target contract or calldata is benign. Review the target, calldata, value, chain, and nonce before signing.

## Security model

The design aims to reduce risk through explicit authorization and constrained execution:

- **Separation of duties:** planning and execution are distinct components.
- **Typed authorization:** EIP-712 signatures bind the signer to structured intent fields and a domain.
- **Replay protection:** nonce tracking and an expiry deadline limit reuse.
- **Configuration validation:** the Python signer validates required environment values, addresses, integer ranges, and calldata hex.
- **Mainnet guard:** signing for Ethereum mainnet is disabled by default in the signer and requires an explicit opt-in.
- **Secret hygiene:** private keys are read from environment variables; never commit a real `.env`, private key, or seed phrase.

### Limitations and safe use

- Use a dedicated **test-only** key with no real funds while learning.
- A private key in an environment variable is still sensitive. Protect the machine, shell history, process environment, and logs.
- Do not enable mainnet signing casually. An explicit opt-in is not a safety review.
- Validate the deployed Executor address and chain ID independently.
- Keep target allowlists, spending limits, simulations, monitoring, and human approval in the surrounding application where appropriate.
- This project is not audited and should not be treated as production-ready financial infrastructure.

See [the security checklist](docs/security.md) for additional guidance.

## Repository status

| Pattern | Summary | Status |
| --- | --- | --- |
| 1. Planner / Executor | Signed intent verified by an on-chain Executor | Implemented reference |
| 2. Bounded Autonomy | Restricted automated execution | Planned |
| 3. Multi-agent + Arbitration | Multiple agents with arbitration | Planned |

“Implemented” refers to the current reference pattern, not a security audit or production-readiness claim.

## Quick start

### Requirements

- Foundry (including `forge`)
- Python 3.10+ (use a version compatible with the dependencies)
- Git

Clone the repository and install Solidity dependencies:

```bash
git clone https://github.com/meekail1996-a11y/miki-onchain-agent-patterns
cd miki-onchain-agent-patterns

forge install foundry-rs/forge-std@v1.9.6 OpenZeppelin/openzeppelin-contracts@v5.0.2
forge test
```

### Python intent signer

Install dependencies:

```bash
python -m pip install -r requirements.txt
```

Copy `.env.example` to a local `.env` and replace the placeholders with values from your own **local or test deployment**. The `.env` file is ignored by Git.

PowerShell example (set values only in your local terminal; do not paste real secrets into source code, chat, or commits):

```powershell
$env:PRIVATE_KEY = "YOUR_TEST_WALLET_PRIVATE_KEY"
$env:CHAIN_ID = "31337"
$env:CONTRACT_ADDRESS = "YOUR_DEPLOYED_EXECUTOR_ADDRESS"
$env:TARGET_ADDRESS = "YOUR_INTENDED_TARGET_ADDRESS"
$env:INTENT_NONCE = "0"

python scripts/sign_intent.py
```

The signer prints the signer address, chain ID, Executor address, intent, and signature. **A signature is sensitive authorization data:** share it only when you understand what it permits. The script creates a signature; it does not submit a transaction.

The nonce must match the Executor's current on-chain `nonce()` value. Update it after each successful execution. Ethereum mainnet signing is blocked unless `ALLOW_MAINNET_SIGNING=1` is explicitly set.

## Testing

Run Python validation tests:

```bash
python -m unittest discover -s tests -v
```

Run Solidity tests:

```bash
forge test
```

Tests are useful evidence, not a formal security guarantee. Review the current CI workflow and test output for the exact checks run on a given revision.

## Project structure

```text
contracts/                 Solidity Executor implementation
scripts/                   Off-chain tooling
  sign_intent.py           EIP-712 intent signer
test/                      Foundry tests
tests/                     Python validation tests
docs/
  patterns.md              Pattern design notes
  security.md              Security checklist
.env.example               Safe configuration template
```

## Roadmap

- [x] Pattern 1: Planner / Executor reference
- [ ] Pattern 2: Bounded autonomy
- [ ] Pattern 3: Multi-agent coordination and arbitration
- [ ] Expand threat modeling and adversarial tests
- [ ] Add stronger policy examples, such as target allowlists and value caps

## Contributing

This project is being built in public. Issues, feedback, and pull requests are welcome—especially around threat modeling, test coverage, policy enforcement, and developer experience.

When reporting a security issue, do not publish secrets, private keys, seed phrases, or exploitable details in a public issue.

## License

MIT. See [LICENSE](LICENSE).
