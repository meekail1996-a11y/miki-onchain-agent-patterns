# On-chain Agent Patterns – Deep Dive

This repository explores security patterns for AI agents interacting with smart contracts.

The core principle is:

**Planner proposes. Executor enforces.**

The Planner operates off-chain and prepares actions. The Executor enforces authorization and execution constraints on-chain.

---

## 1. Planner / Executor

**Status: Implemented**

### How it works

- An off-chain agent (Planner) decides what action to propose.
- It creates and signs an `Intent` using EIP-712.
- The signed Intent can be submitted by any account.
- The Executor verifies the signature, nonce, and deadline.
- If validation succeeds, the contract executes the requested call.

### Key properties

- Explicit authorization through signed Intents.
- Nonce-based replay protection.
- Deadline-based expiration.
- Separation between off-chain decision-making and on-chain enforcement.

### Limitations

- Anyone holding a valid signed Intent may submit it; the current design does not bind execution to a specific relayer.
- A compromised signer can authorize malicious actions.
- Pattern 1 does not provide the target allowlist and daily spending cap implemented in Pattern 2.

---

## 2. Bounded Autonomy

**Status: Implemented**

### How it works

This pattern allows an agent to operate within predefined on-chain boundaries rather than relying only on unrestricted execution.

The contract includes:

- An administrator-managed target allowlist.
- A daily spending cap for native asset value.
- An emergency stop and resume mechanism.
- Spending accounting before the inherited external execution call, preventing reentrant execution from bypassing the daily cap.

### Security properties

- Calls to non-allowlisted targets are rejected.
- Native-value spending is checked against the daily cap.
- Spending is accounted for before the external call.
- Emergency stop can halt execution.

### Limitations

- The daily cap accounts for `intent.value`; it does not measure ERC-20 transfers or other token-denominated exposure.
- Administrative permissions remain centralized.
- The pattern does not currently provide a multisig or timelock for administrative actions.
- The target allowlist does not validate the safety of individual functions or calldata on an allowed contract. An allowlisted contract may still expose dangerous or unintended functionality.
- Passing tests does not establish that the contract is free of vulnerabilities.

---

## 3. Multi-agent + Arbitration

**Status: Implemented**

### How it works

This pattern supports multiple registered agents participating in a proposal and arbitration workflow.

The implemented flow includes:

- Agent registration.
- Proposal creation.
- One vote per registered agent for each proposal.
- An arbiter who can approve or reject a proposal.

### Security properties

- Participation is restricted to registered agents.
- Duplicate voting by the same agent on a proposal is prevented.
- Final approval or rejection is handled by the designated arbiter.

### Limitations

- The current implementation does not enforce a voting quorum or minimum approval threshold.
- The arbiter retains decisive authority, regardless of the recorded votes.
- This is an arbitration model, not a fully decentralized consensus mechanism.

---

## Security and Scope

These patterns demonstrate specific authorization and execution controls. They are educational and experimental reference implementations.

They have **not been independently audited** and should not be considered production-ready.

A successful test suite is evidence that tested scenarios behave as expected; it is not proof that all attack vectors have been addressed.

For implementation details and known risks, see [Security Checklist](security.md).

---

More patterns, tests, and threat-model documentation may be added as the project evolves.