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
- Long deadlines increase the time window in which a signed Intent may be submitted.
- Pattern 1 does not include Pattern 2's target allowlist or daily spending cap.

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
- Quorum is a strict majority of the agents registered at proposal creation time: `agentCount / 2 + 1`, stored per proposal and never recomputed.
- Removing an agent blocks its future votes but does not retract votes it already cast, and does not change any existing proposal's quorum.
- Re-admission grants fresh eligibility only: a re-admitted agent cannot vote on proposals created before it was re-admitted, including proposals created before its earlier removal.

### Nonce Policy

- `propose` rejects Intents whose nonce is below the executor's current nonce, and rejects a nonce already reserved by a live proposal.
- Proposals for future nonces may be queued. They become executable only once the executor nonce reaches them; until then `resolveArbitration` reverts with `InvalidNonce` and the proposal stays pending.
- A terminal rejection releases the nonce reservation so a different Intent can use it. An executed proposal advances the nonce permanently.

### Known Limitations

- The arbiter controls agent membership. Because the arbiter can register agents it controls, quorum only constrains an arbiter whose agents are genuinely independent. Separating agent admission from arbitration is not implemented.
- The arbiter retains decisive authority over proposal outcomes and has no enforced timeout or automatic escalation.
- There is no quorum-independent fallback: if agents stop voting, nothing executes.
- Pattern 3 implements neither a target allowlist nor a native-asset spending cap. A quorum-approved Intent may call any non-zero address with an arbitrary `value`. Those controls exist only in Pattern 2.
- Quorum is immutable per proposal, so removing agents can make an existing proposal permanently unable to reach its threshold. Such a proposal can only be closed by an explicit rejection.
- Votes cast before an agent was removed continue to count. Retracting them would let an arbiter erase rejections and change outcomes, so the current behaviour is deliberately conservative.
- An agent holding a valid signed Intent can reserve the current nonce with it and then abstain, stalling new proposals until the arbiter rejects that proposal. Signature validation prevents unsigned reservations but cannot prevent squatting with a genuine signature.
- Arbiter rotation and recovery are deliberately not implemented. A lost arbiter key freezes every proposal permanently, including the rejection path used to release reserved nonces.
- Agent registration and voting do not independently guarantee that proposals are correct or safe.
- The implementation should not be considered decentralized consensus.

### Storage Layout and Upgradeability

- The Pattern 3 storage layout changed when quorum, eligibility epochs, nonce reservations, and the proposal status enum were introduced; `Proposal.executed` was replaced by `Proposal.status`, and new state variables were added.
- Patterns 1-3 are designed for fresh deployments. They are **not** proxy-storage compatible: upgrading an existing proxy to these versions would misalign storage slots.
- If upgradeability is required, the storage layout must be designed and frozen separately, and the contracts re-reviewed for upgrade safety.

## Operational Security Recommendations

- Never commit private keys, seed phrases, API keys, or other secrets to the repository.
- Use dedicated test accounts for local development and testing.
- Use short Intent deadlines where practical.
- Verify the chain ID, signer, executor address, target address, nonce, and value before signing or submitting an Intent.
- Review target contracts and their callable functions before adding them to an allowlist.
- Deploy Pattern 3 with a multisig or timelock as the arbiter, since arbiter rotation is not implemented.
- Monitor execution events and administrative changes.
- Keep administrative credentials secure and consider multisig and timelock controls before any real-world deployment.
- Do not use real funds without independent security review and appropriate hardening.

## Security Status

This repository is an educational and experimental project.

- It has not undergone an independent professional security audit.
- It is not production-ready.
- `test/SecurityReview.t.sol` pins the guarantees that are easy to regress: rejection of malleable (high-`s`) signatures, rejection of signatures bound to another chain, the inclusive deadline boundary, release of a nonce reserved by a proposal that expired before resolution, the arbiter-dependent liveness of a squatted nonce, blocked votes from removed agents, and token transfers escaping the native spending cap.
- Passing automated tests does not guarantee the absence of vulnerabilities.
- The documented controls reduce specific risks but do not eliminate all smart contract, key-management, operational, or integration risks.

## Future Security Improvements

Potential improvements include:

- Multisig and timelock-based administration.
- Two-step arbiter transfer, so a lost arbiter key does not freeze governance.
- A separate agent-admission role, so quorum cannot be minted by the approving arbiter.
- Explicit expiry or timeout handling for proposals that can no longer reach quorum.
- Stronger configuration validation.
- Expanded threat modeling.
- Additional adversarial and invariant testing.
- Improved monitoring and operational safeguards.
- Stronger governance and authorization boundaries.
