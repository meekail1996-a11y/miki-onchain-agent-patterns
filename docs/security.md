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
| ERC-20 transfer of a registered token beyond its budget | Per-token daily cap read and charged before the token call; `transfer` on a token that was never registered is refused | Pattern 2 |
| An Intent creating or growing an allowance | `approve` and `increaseAllowance` refused, alongside `transferFrom`, on the metered path | Pattern 2 |
| Reentrancy during execution | Nonce and spending accounting updated before the external call, plus a reentrancy guard on `execute` and on `resolveArbitration` | Pattern 2, Pattern 3 |
| Approval without sufficient support | Per-proposal quorum snapshot of a strict majority, checked at resolution | Pattern 3 |
| Late-joining agents voting on older proposals | Per-proposal voter eligibility snapshot (`agentEpoch`) | Pattern 3 |
| Reviving a rejected proposal | Terminal `Rejected` status; execution and further votes revert | Pattern 3 |
| Competing proposals for one nonce | One live proposal per nonce; stale nonces rejected at creation | Pattern 3 |
| Zero-address configuration mistakes | `InvalidTarget`, `InvalidAgent` and `InvalidArbiter` guards | Pattern 2, Pattern 3 |

Residual risks that these controls do not remove are listed under each pattern's Known Limitations.

## Test Evidence

The table above says which control exists. This one says which test would fail if the control
were removed, so a reviewer can go from a claim to an executable assertion instead of trusting
the prose. `scripts/check_doc_claims.py` fails the build if a test named here stops existing,
so this table cannot quietly rot.

| Control | Test | Suite |
|---|---|---|
| Replay of an already executed Intent | `test_ReplayAfterExecutionRevertsOnNonce` | `test/SecurityReview.t.sol` |
| Expired Intent rejected | `test_RevertWhenExpired` | `test/Pattern1.t.sol` |
| Deadline compared inclusively | `test_DeadlineBoundaryIsInclusive` | `test/SecurityReview.t.sol` |
| Malleable (high-`s`) signature rejected | `test_RejectsMalleableHighSSignature` | `test/SecurityReview.t.sol` |
| Signature bound to chain and contract | `test_RejectsSignatureFromAnotherChain` | `test/SecurityReview.t.sol` |
| Target allowlist enforced | `test_RevertWhenTargetNotAllowed` | `test/Pattern2.t.sol` |
| Daily native-cap enforced | `test_RevertWhenSpendingCapExceeded` | `test/Pattern2.t.sol` |
| Cap accounting under random inputs | `testFuzz_DailySpendingNeverExceedsCap` | `test/Pattern2Fuzz.t.sol` |
| Reentrancy cannot raise the cap | `test_ReentrancyCannotExceedDailySpendingCap` | `test/Pattern2.t.sol` |
| Pause checked before the allowlist | `test_ContractPausedTakesPrecedenceOverTargetNotAllowed` | `test/SecurityReview.t.sol` |
| Day reset and midnight straddle | `test_DayResetDoesNotAccumulateAcrossIdleDays`, `test_BoundaryStraddleAllowsTwoCapsCloseTogether` | `test/SecurityReview.t.sol` |
| ERC-20 transfers bounded by the token's own daily cap | `test_TokenTransfersAreBoundedByTheirOwnCap` | `test/SecurityReview.t.sol` |
| `approve` refused on the metered path | `test_ApproveOnMeteredTokenReverts` | `test/TokenControls.t.sol` |
| A token that was never registered is refused | `test_TransferOfUnregisteredTokenReverts` | `test/TokenControls.t.sol` |
| An over-cap token transfer leaves no trace | `test_OverCapTokenTransferRevertsAndRollsBack` | `test/TokenControls.t.sol` |
| Direct execution disabled in Pattern 3 | `test_RevertWhenDirectExecutionIsAttempted` | `test/Pattern3.t.sol` |
| Arbiter cannot approve below quorum | `test_RevertWhenApprovingWithoutQuorum` | `test/Pattern3.t.sol` |
| Removed agents cannot vote | `test_RemovedAgentCannotVoteOnExistingProposal` | `test/SecurityReview.t.sol` |
| Squatted nonce stalls, rejection frees it | `test_SquattedNonceStallsPipelineUntilArbiterRejects` | `test/SecurityReview.t.sol` |
| Zero-address configuration rejected | `test_RevertWhenAgentSignerIsZero`, `test_RevertWhenArbiterIsZero`, `test_RevertWhenAddingZeroAddressTarget` | `test/SecurityReview.t.sol` |
| No execution leaves the recorded spend above the cap in force at that moment | `invariant_ExecutionNeverExceedsCap` | `test/Pattern2Invariant.t.sol` |
| A paused contract executes nothing | `invariant_NoExecutionWhilePaused` | `test/Pattern2Invariant.t.sol` |
| Nonce advances exactly once per successful execution | `invariant_NonceMatchesExecutions` | `test/Pattern2Invariant.t.sol` |
| Contract balance equals recorded outflow, and the target received it | `invariant_BalanceMatchesOutflow` | `test/Pattern2Invariant.t.sol` |
| Stolen-key outcome per pattern | `test_StolenPlannerKey_DrainsPattern1`, `test_StolenPlannerKey_IsBoundedInPattern2`, `test_StolenPlannerKey_DrainsPattern2OverDays`, `test_StolenPlannerKey_CannotExecuteAloneInPattern3` | `test/AttackComparison.t.sol` |

A test named here is evidence about one scenario, not proof that the control is complete; the
Known Limitations sections record what each control deliberately leaves uncovered.

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
- A valid signature confirms that the authorized signer approved the exact target, value, and calldata; it does not establish that the target or the requested operation is safe.
- Pattern 1 permits calls to arbitrary target addresses and does not include Pattern 2's target allowlist or daily native-asset spending cap. This creates an arbitrary-ETH-transfer risk if the signer key is compromised or authorizes an unsafe Intent.

## Pattern 2 — Bounded Autonomy

### Security Controls

- Restricts execution to administrator-approved target contracts.
- Enforces a daily spending cap for native asset value.
- Includes emergency stop and resume controls.
- Updates spending accounting before making the inherited external execution call.
- Uses a reentrancy guard on `execute`, in addition to the checks-effects-interactions ordering.
- Includes adversarial testing for reentrancy against the daily spending limit.

### Known Limitations

- The daily native-asset cap accounts for `intent.value` only. On the metered path a direct
  `transfer` of a registered token is separately bounded by that token's own daily cap; the
  bound is on the declared amount, and fee-on-transfer, rebasing and non-standard return
  values are outside it.
- Token movement outside the metered path is bounded by neither cap: an allowance that
  already existed when the policy was first relied on, and a target that pulls with
  `transferFrom` inside the executed call.
- The cap is per calendar day (UTC) and resets on the first transaction of a new day. Spending the full cap just before midnight and again just after therefore permits up to twice the cap within seconds, while idle days do not accumulate allowance. `test/SecurityReview.t.sol` pins both edges.
- Administrative authority is centralized and the `admin` address is `immutable`: no multisig or timelock is required, and losing the admin key permanently loses administrative control (pause, allowlist, and spending-cap changes).
- The target allowlist restricts which contracts can be called, but does not validate the safety of individual functions or calldata sent to an allowed contract.
- Reentrancy-focused tests cover specific attack scenarios; they do not prove that all possible reentrancy vulnerabilities have been eliminated.
- Further adversarial testing and independent security review are necessary.

### Metered Token Path

Pattern 2 also enforces a per-token daily cap on one specific call shape: a direct, standard
ERC-20 `transfer` issued by the executor to a token the admin registered with
`addMeteredToken`. Three things are separate here and should not be read as one.

- **The bounded operation** is a direct `transfer` on a registered token. The declared amount
  in the calldata is compared with that token's remaining budget and charged before the call
  is made, so the guarantee is about the amounts the executor declared, not about the balance
  change that results. Fee-on-transfer and rebasing tokens are outside it, and a token whose
  return value is not a single `true` word is refused rather than tolerated.
- **The refused selectors** are `approve`, `increaseAllowance` and `transferFrom`, on any
  target. This is what keeps the metered path from creating or spending an allowance, and it
  is why the allowance route below is a documented prerequisite rather than a control.
- **The movements outside this path** are bounded by neither cap: an allowance that already
  existed when the policy was first relied on, and a target that pulls with `transferFrom`
  inside the executed call. `test_PreExistingAllowanceIsPulledWithoutAnyExecution` and
  `test_IndirectPullDuringExecutionIsNotCharged` pin both, and both still pass.

Two details that follow from the design rather than from taste:

- **The cap is per token, shared across Intents, and not per target.** Two transfers in the
  same day draw on one budget, because the token is the unit of exposure, not the call.
- **A zero cap stops a token.** `setTokenCap(token, 0)` is the stop switch, and it stays
  available after the token has spent today. A positive cap below today's spend is refused
  (`TokenCapBelowSpent`), which is what keeps `tokenSpentToday <= tokenCapPerDay` true for
  every non-zero cap and lets `invariant_TokenSpendNeverExceedsCap` state the property
  without a carve-out.

The registry is append-only: `addMeteredToken` adds and there is no removal function, so a
token cannot be quietly dropped from the set a reviewer is reading. Stopping a token is a
cap change, not a deletion. Registration does not grant reach on its own either — the token
must already be an allowlisted target, and the same `paused` and allowlist checks run first.

**Selector collisions are closed, not opened.** Any calldata that begins with one of the four
token selectors is treated as a token call, even if the target is not a token at all; if the
target is not a registered token the result is `TokenNotRegistered`. A selector collision
closes the call; it never opens a path. This also means the metered controls are not a
general ERC-20 capability: routers and aggregators are not supported, and `transferFrom` is
never executed.

**Order of validation differs between the two paths, deliberately.** The native path runs
`paused → allowlist → daily cap → deadline / nonce / signature`, because that cap check
predates the metered work and is left unchanged. The metered path runs
`paused → allowlist → selector policy → deadline / nonce / signature → per-token cap`, so the
Intent is authenticated before any budget is consulted. The consequence is real and worth
stating: on the native path an unsigned Intent can still reveal whether the budget would
allow a given amount, while on the metered path it cannot. Error precedence differs between
the two paths for the same reason, and the difference is not claimed to be a defect in
either; aligning the native path is listed under Future Security Improvements.

**What this path does not do.** The executor cannot enumerate the allowances granted to it
and cannot revoke them. Revoking an allowance that existed before the policy was relied on is
a migration prerequisite on the token itself — an operational step, not something the
contract checks or promises. Nothing here protects a holder's other ERC-20 balances, and
nothing here is a general support claim for ERC-20 assets or for allowances.

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
- Proposals for future nonces may be queued. They become executable only once the executor nonce reaches them; until then `resolveArbitration` reverts with `InvalidNonce` and the proposal stays pending. Quorum is checked before the nonce, so a queued proposal that has not reached quorum reports `InsufficientVotes` instead.
- A terminal rejection releases the nonce reservation so a different Intent can use it. An executed proposal advances the nonce permanently.

### Known Limitations

- The arbiter controls agent membership. Because the arbiter can register agents it controls, quorum only constrains an arbiter whose agents are genuinely independent. Separating agent admission from arbitration is not implemented.
- The arbiter retains decisive authority over proposal outcomes and has no enforced timeout or automatic escalation.
- There is no quorum-independent fallback: if agents stop voting, nothing executes.
- Pattern 3 implements neither a target allowlist nor a native-asset spending cap. A quorum-approved Intent may call any non-zero address with an arbitrary `value`. Those controls exist only in Pattern 2.
- Quorum is immutable per proposal, so removing agents can make an existing proposal permanently unable to reach its threshold. Such a proposal can only be closed by an explicit rejection.
- Votes cast before an agent was removed continue to count. Retracting them would let an arbiter erase rejections and change outcomes, so the current behaviour is deliberately conservative.
- An agent holding a valid signed Intent can reserve the current nonce with it and then abstain, stalling new proposals until the arbiter rejects that proposal. Signature validation prevents unsigned reservations but cannot prevent squatting with a genuine signature.
- The `arbiter` address is `immutable`, so rotation and recovery are not possible without a new deployment. A lost arbiter key freezes every proposal permanently, including the rejection path used to release reserved nonces.
- Agent registration and voting do not independently guarantee that proposals are correct or safe.
- The implementation should not be considered decentralized consensus.

### Storage Layout and Upgradeability

- The Pattern 3 storage layout changed when quorum, eligibility epochs, nonce reservations, and the proposal status enum were introduced; `Proposal.executed` was replaced by `Proposal.status`, and new state variables were added.
- Patterns 1-3 are designed for fresh deployments. They are **not** proxy-storage compatible: upgrading an existing proxy to these versions would misalign storage slots.
- If upgradeability is required, the storage layout must be designed and frozen separately, and the contracts re-reviewed for upgrade safety.

## Static Analysis Findings

Slither 0.11.6 was run against the three contracts (forge 1.9.0, solc 0.8.38 as pinned in `foundry.toml`). Six detector classes fired. None of them is an unmitigated code defect; each is recorded here so a reviewer does not have to re-derive the reasoning.

| Detector | Location | Assessment |
|---|---|---|
| `arbitrary-send-eth` | `Pattern1_PlannerExecutor._executeIntent` | By design. The executor forwards `intent.value` and `intent.data` to `intent.target` on behalf of the signer. The only gate is the signature; the target is not constrained by Pattern 1. Mitigations belong above it: Pattern 2's allowlist and daily cap, or Pattern 3's quorum and arbiter. Deploying Pattern 1 alone means a compromised signer key can drain the contract balance to any address. |
| `low-level-calls` | `Pattern1_PlannerExecutor._executeIntent` | Same call, reported separately. The low-level `call` is the execution mechanism; its success flag is checked and a failure reverts with `CallFailed`, but the revert reason of the callee is discarded. |
| `timestamp` | deadline checks in all three contracts; `currentDay > lastSpendingResetDay` in Pattern 2 | Accepted with a bounded effect, not treated as risk-free. Block timestamps are set by block producers and can be shifted within the tolerance of the target chain (seconds on most L1s, but sequencer-controlled and possibly coarser on some L2s). It affects two things: an Intent near its deadline may be accepted or rejected a few seconds early or late, and a payment near a day boundary may be counted against the previous or the next day's cap. It cannot raise the cap itself, and on chains with coarse timestamps the window is wider than on Ethereum. |
| `unused-return` | `EIP712`/`ECDSA` `tryRecover` in `_verifyIntentSignature` | Deliberate. In OpenZeppelin 5.0.2 the third return value is `errorArg`, which OZ only forwards into its own typed errors (for example `ECDSAInvalidSignatureLength`). This contract collapses every recovery failure into a single `InvalidSignature()`, so the argument is intentionally discarded and no failure detail is exposed to callers. |
| `solc-version` | `pragma solidity ^0.8.20` in all three contracts | Known advisory surface, not currently exploitable in this repository. Builds pin `solc_version = "0.8.38"` in `foundry.toml` and CI compiles with that version. The constraint itself still permits older 0.8.x compilers that carry the flagged bugs (`VerbatimInvalidDeduplication`, `FullInlinerNonExpressionSplitArgumentEvaluationOrder`, `MissingSideEffectsOnSelectorAccess`), so anyone building with a different toolchain should pin a recent compiler. Tightening the pragma was considered and deliberately deferred. |
| `naming-convention` | contract and parameter names | Style only. `Pattern1_PlannerExecutor` and the `_param` argument prefixes are chosen for readability of the patterns. |

### Test Coverage

`forge coverage` over the current 110-test suite reports **100% of lines** (187/187), 97.58% of statements (202/207), 90.74% of branches (49/54) and 100% of functions across the three contracts, measured with `forge coverage --report summary --no-match-coverage "(test|script)/"` on the pinned solc 0.8.38. Every line of every contract is executed by at least one test.

The remaining gaps are statements and branches in `Pattern3_MultiAgentArbitration` (92.96% of statements, 79.17% of branches): `Pattern1_PlannerExecutor` and `Pattern2_BoundedAutonomy` are fully covered on every metric. An uncovered branch is not automatically a defect — some are unreachable defensive reverts — but a reviewer should read those paths rather than assume they are exercised. Coverage is a coverage metric, not a security guarantee.

## Key Lifecycle

Every privileged address in this repository is `immutable`. That is a deliberate choice — it removes an entire class of "who can change the signer?" bugs — but it moves rotation out of the contract and into operations, which is where the risk now lives.

| Key | Field | Consequence if lost | Consequence if stolen | In-contract recovery |
|---|---|---|---|---|
| Planner / signer | `agentSigner` (all three) | Nothing can be signed: the executor is frozen (Pattern 2 can still be paused, but not used) | Valid signatures for arbitrary Intents; the loss is bounded only by whatever sits above Pattern 1 | None — redeploy |
| Admin | `admin` (Pattern 2) | The cap, the allowlist and the emergency stop can no longer be changed; a paused contract stays paused | Can allowlist any target, raise the cap, or pause execution indefinitely | None — redeploy |
| Arbiter | `arbiter` (Pattern 3) | Every pending proposal stays pending forever, including the rejection that releases a squatted nonce | Can mint quorum by admitting agents it controls, and can approve or reject at will | None — redeploy |

The two consequences worth pausing on:

- **A lost admin is silent.** There is no event, no error, and no failing test. The deployment keeps accepting Intents and looks healthy until the day a cap needs changing.
- **A stolen arbiter is not obviously visible either.** Voting proceeds normally; the arbiter simply approves whatever it wants, and admitted agents that it controls make quorum meaningless. Pattern 3's quorum constrains an arbiter only when the agents are genuinely independent of it.

### Rotating a key without rotation support

Rotation is a migration, not a transaction. The sequence below is the one the contracts allow; each step has a cost that is worth knowing in advance.

1. Deploy a new instance with the new key and the same parameters (cap, allowlist, quorum shape). Verify the deployed bytecode against a local build before funding it.
2. Recreate the allowlist entry by entry. This is the step that is silently skipped in a hurry, and it is the control that bounds a stolen signer.
3. Fund the new contract with working capital only. Do not sweep the treasury in before the new instance has executed successfully at least once.
4. Deal with the old instance honestly. If the signer is *lost*, its balance is unrecoverable: freezing it is the only safe action, and the loss is the balance. If the signer is *stolen*, pausing stops the attacker but also stops you — resuming to migrate re-opens the attacker's access at the cap rate, so migration must happen in cap-sized steps immediately after resuming, or not at all. There is no primitive here that moves funds while execution is paused.
5. Reject every pending Pattern 3 proposal on the old instance before retiring it. A retired contract with pending proposals has reserved nonces and a frozen arbiter path, and the next person to read the state will assume it still matters.
6. Remove the old address from agent configuration and monitors, and keep it monitored read-only for unexpected activity.

A two-step handover (`proposeSigner` / `acceptSigner`) would remove most of this, at the cost of adding an administrative path an attacker can target. That trade-off is recorded under Future Security Improvements rather than implemented.

## Liveness and Stalled Pipelines

The controls in this repository are safety controls. None of them is a liveness control, and a system that is safe but stuck is still a failed system.

- **Nonce squatting is the cheapest stall.** Any agent holding one genuinely signed Intent can propose it, reserve the current nonce, and abstain. New proposals for that nonce are rejected with `NonceAlreadyProposed`, so the queue stops until a human rejects the proposal. The signature check cannot help here: the signature is valid.
- **Pending proposals do not expire.** The Intent's own `deadline` limits when it can execute, but nothing closes the proposal itself. `resolveArbitration` works whenever the arbiter calls it, which means a pending proposal can sit in that state indefinitely.
- **Quorum can become unreachable.** Quorum is fixed when the proposal is created, so removing an agent can leave a proposal below its threshold forever. Rejection is again the only exit.
- **The arbiter is the timeout.** Every escape path above ends in an arbiter call, so Pattern 3's liveness is the arbiter's availability, and behind a single key that availability is one lost device away from zero.

What follows for an operator: monitor proposals whose age exceeds the expected voting window, treat a rising count as an incident rather than noise, and give the arbiter a multisig with a response expectation. The tests pin the behaviour (`test_SquattedNonceStallsPipelineUntilArbiterRejects`), which means a future change that silently makes the stall permanent would be caught.

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
- `test/SecurityReview.t.sol` pins the guarantees that are easy to regress: rejection of malleable (high-`s`) signatures, rejection of signatures bound to another chain, the inclusive deadline boundary, release of a nonce reserved by a proposal that expired before resolution, the arbiter-dependent liveness of a squatted nonce, blocked votes from removed agents, a registered token's direct transfer staying inside its
own cap, and token movement outside that path escaping both caps.
- Passing automated tests does not guarantee the absence of vulnerabilities.
- The documented controls reduce specific risks but do not eliminate all smart contract, key-management, operational, or integration risks.

## Future Security Improvements

Potential improvements include:

- Multisig and timelock-based administration.
- An arbiter-transfer mechanism, so a lost arbiter key does not freeze governance; this needs a redesign because the arbiter is immutable today.
- Signer and admin rotation, for example a two-step `proposeSigner` / `acceptSigner` handover, which today requires a full migration (see Key Lifecycle).
- An on-chain timeout for pending proposals, so a squatted nonce or an unreachable quorum closes itself instead of waiting for a human.
- A separate agent-admission role, so quorum cannot be minted by the approving arbiter.
- Explicit expiry or timeout handling for proposals that can no longer reach quorum.
- Stronger configuration validation.
- Aligning the native path's validation order with the metered path's, so an unsigned Intent
  cannot probe the native budget.
- An operator tool that enumerates and revokes allowances already granted to an executor,
  since the contract can do neither; today that is a migration-checklist item.
- Expanded threat modeling.
- Additional adversarial and invariant testing.
- Improved monitoring and operational safeguards.
- Stronger governance and authorization boundaries.
