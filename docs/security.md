# Security Model and Threat Considerations

This document describes the security controls, assumptions, and known limitations of the patterns implemented in this repository.

The project is an educational and experimental reference for exploring how AI agents can interact with smart contracts under explicit on-chain constraints.

**Core principle: Planner proposes. Executor enforces.**

## General Security Principles

- Off-chain components may prepare and propose actions, but on-chain contracts must enforce critical execution rules.
- Signed Intents should have explicit authorization boundaries.
- Nonces and deadlines help prevent replay and stale execution.
- Spending limits, target restrictions, and emergency controls reduce the impact of unintended actions.
- External calls and state updates must be designed with reentrancy risks in mind.
- Passing tests does not prove that a contract is free from vulnerabilities.

## Mitigations

The implementation maps the most relevant threats to concrete on-chain controls:

| Threat | Control | Where |
|---|---|---|
| Replay of an already executed Intent | Monotonic nonce checked before the call and incremented before it | Pattern 1 |
| Stale or expired authorization | Deadline enforced before signature verification and before any state change; Pattern 3 also rejects expired Intents at proposal creation | Pattern 1, Pattern 3 |
| Signature forgery or malleability | EIP-712 domain-separated digest, low-`s` enforcement from OpenZeppelin `ECDSA`, and `tryRecover` mapped to a single `InvalidSignature` failure | Pattern 1 |
| Cross-chain or cross-contract replay | Domain separator binds `chainId` and `verifyingContract` | Pattern 1 |
| Direct execution bypassing governance | Inherited `execute` overridden to always revert with `DirectExecutionDisabled` | Pattern 3 |
| Arbitrary target or native-value drain | Admin allowlist and daily native-asset cap checked before the external call | Pattern 2 |
| Reentrancy during execution | Nonce and spending accounting updated before the external call, plus a reentrancy guard on `execute` and on `resolveArbitration` | Pattern 2, Pattern 3 |
| Approval without sufficient support | Per-proposal quorum snapshot of a strict majority, checked at resolution | Pattern 3 |
| Late-joining agents voting on older proposals | Per-proposal voter eligibility snapshot (`agentEpoch`) | Pattern 3 |
| Reviving a rejected proposal | Terminal `Rejected` status; execution and further votes revert | Pattern 3 |
| Competing proposals for one nonce | One live proposal per nonce; stale nonces rejected at creation | Pattern 3 |
| Zero-address configuration mistakes | `InvalidTarget`, `InvalidAgent` and `InvalidArbiter` guards | Pattern 2, Pattern 3 |

Residual risks that these controls do not remove are listed under each pattern's Known Limitations.

## Pattern 1 — Signed Intent

### Security Controls

- Uses EIP-712 typed structured data for signing Intents.
- Verifies that the signature belongs to the authorized signer.
- Uses nonces to prevent replay of previously executed Intents.
- Uses deadlines to reject expired Intents.
- Rejects non-canonical signatures: OpenZeppelin's `tryRecover` returns `InvalidSignatureS` for a high-`s` value, so a valid signature cannot be mutated into a second valid form.
- Binds the EIP-712 domain to the chain ID and to this contract's address, so a signature produced on another chain or for another deployment is rejected.
- Compares deadlines inclusively: an Intent is still valid when `block.timestamp == intent.deadline` and rejected one second later.

### Known Limitations

- Anyone holding a valid signed Intent may submit it for execution. The relayer is not bound to the signature.
- A compromised signer key can authorize malicious Intents.
- A valid signature confirms that the authorized signer approved the exact target, value, and calldata; it does not establish that the target or the requested operation is safe.
- Pattern 1 permits calls to arbitrary target addresses and does not include Pattern 2's target allowlist or daily native-asset spending cap. This creates an arbitrary-ETH-transfer risk if the signer key is compromised or authorizes an unsafe Intent.
- Long deadlines increase the time window in which a signed Intent may be submitted.

## Pattern 2 — Bounded Autonomy

### Security Controls

- Restricts execution to administrator-approved target contracts.
- Enforces a daily spending cap for native asset value.
- Includes emergency stop and resume controls.
- Updates spending accounting before making the inherited external execution call.
- Uses a reentrancy guard on `execute`, in addition to the checks-effects-interactions ordering.
- Includes adversarial testing for reentrancy against the daily spending limit.

### Known Limitations

- The daily spending cap accounts for `intent.value` only. It does not track ERC-20 transfers or other token exposure.
- Administrative authority is centralized. The current implementation does not require a multisig or timelock.
- The target allowlist restricts which contracts can be called, but does not validate the safety of individual functions or calldata sent to an allowed contract.
- Reentrancy-focused tests cover specific attack scenarios; they do not prove that all possible reentrancy vulnerabilities have been eliminated.
- Further adversarial testing and independent security review are necessary.

## Pattern 3 — Multi-Agent Coordination and Arbitration

### Security Controls

- Requires agents to register before participating.
- Disables the inherited public `execute` path: direct execution reverts with `DirectExecutionDisabled` for every caller, including the arbiter. Execution is reachable only through `resolveArbitration`.
- Validates the EIP-712 signature and the Intent deadline when a proposal is created, and validates the signature again at execution time.
- Restricts each registered agent to one vote per proposal.
- Snapshots a quorum per proposal and refuses execution while approvals are below it.
- Snapshots voter eligibility per proposal, so agents added later cannot vote on earlier proposals.
- Makes rejection terminal: a rejected proposal can never be executed, and cannot be voted on or resolved again.
- Reserves each executor nonce for at most one live proposal, so two approved proposals can never compete for the same nonce.
- Guards arbiter resolution with a reentrancy lock.
- Records execution status before the external call, so a failed execution leaves the proposal pending instead of permanently consumed.
- Re-checks the Intent deadline at resolution time. An Intent that expires while its proposal is pending cannot execute; the proposal stays pending and an explicit rejection releases the reserved nonce so the executor can move on.

### Voter Eligibility and Quorum

- Each agent records the proposal index at which it was admitted. An agent may vote on a proposal only if it was admitted no later than that proposal's creation.
- Quorum is a strict majority of the agents registered at proposal creation time: `agentCount /