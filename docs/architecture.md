# Architecture: who can do what, and where it stops

This document describes the architecture of the three patterns in thi

s repository as a system: which component holds which authority, what crosses each trust boundary, and which test would fail if a control were removed. It is written for a reader who wants to judge the design without reading every contract — and for a reviewer who wants to check whether a claim here is backed by an assertion.

Scope note, stated once and meant: this repository is an educational reference. It has not
been independently audited and is not production-ready. The tests show that named scenarios
behave as described; they do not show the absence of vulnerabilities. See
[`docs/security.md`](security.md) for the static-analysis findings and the deliberate
limitations, and [`docs/patterns.md`](patterns.md) for a per-pattern walkthrough.

Evidence at the time of writing: 110 Solidity tests in 9 suites, 5 invariants over 256 runs
and 128,000 handler calls, 7 Python tests, and 4 CI jobs that run on every push to `main`.
Reproduce all of it with `bash scripts/verify_all.sh`.

## 1. Trust boundaries

Four boundaries carry the design. Everything else is bookkeeping.

```text
        B1: intent is formed            B2: intent is signed
   ┌───────────────────────────┐   ┌──────────────────────────────┐
   │  Planner                  │   │  Signer key (agent)          │
   │  (LLM or off-chain logic) │   │  EIP-712 over the exact Intent│
   │  no keys, no execution    │   │  no ability to execute alone │
   └───────────────────────────┘   └──────────────────────────────┘
                     │                          │
                     │  Intent{target,value,data,nonce,deadline}
                     ▼                          ▼
   ┌──────────────────────────────────────────────────────────────┐
   │  B3: on-chain Executor                                       │
   │  verifies signature, nonce, deadline; applies its own policy  │
   │  (allowlist, daily cap, pause) or requires a quorum           │
   └──────────────────────────────────────────────────────────────┘
                     │
                     ▼
   ┌──────────────────────────┐      ┌──────────────────────────────┐
   │  Target contract         │      │  B4: administration          │
   │  receives the call       │      │  allowlist, cap, pause,      │
   └──────────────────────────┘      │  agents, arbitration         │
                                     └──────────────────────────────┘
```

**B1 — proposition vs. authority.** The Planner can propose anything. Nothing it produces
has effect until it becomes a signed Intent and passes B3. There is no path from Planner to
a transaction; the repository's Python signer (`scripts/sign_intent.py`) is a separate
process with a separate key.

**B2 — authorization.** The signature covers `target`, `value`, `keccak256(data)`, `nonce`
and `deadline` under this contract's EIP-712 domain, which includes `chainId` and the
verifying contract address. Changing any field invalidates the signature, and a signature
for another chain or another deployment does not verify
(`test/Pattern1.t.sol:test_RevertWhenSignatureIsInvalid`,
`test/SecurityReview.t.sol:test_RejectsSignatureFromAnotherChain`).

**B3 — enforcement.** The contract, not the agent, decides whether an authorized Intent may
run. Pattern 1 enforces nonce and deadline only; Pattern 2 adds allowlist, daily cap and
pause; Pattern 3 disables direct execution entirely and requires a quorum plus an arbiter.

**B4 — administration.** Administrative actions change the rules, never the execution path
for a specific Intent: the admin cannot sign an Intent, move funds, or execute a call. In
Pattern 3 the arbiter both administers agent membership and resolves arbitration, which is
the single most concentrated authority in the repository and is treated as such in
`docs/security.md`.

## 2. Roles and authority

| Role | Can do | Cannot do | Where a failure or misuse stops |
|---|---|---|---|
| **Planner** (LLM / off-chain) | Propose an Intent; choose target, value, calldata | Move funds, sign, execute, or change any on-chain rule | Nothing reaches the chain without a signature (B2) and the executor's policy (B3) |
| **Signer key** (`agentSigner`, `immutable`) | Authorize one exact Intent | Execute it; exceed the nonce order; reuse a nonce; act after `deadline`; address a target the admin never allowed (Pattern 2); execute alone (Pattern 3) | Nonce, deadline and signature checks in the executor; allowlist and cap in Pattern 2; quorum in Pattern 3 |
| **Executor contract** | Verify, then call the target with the Intent's value and data | Choose a different target, value or data than the signed ones; skip its own policy | It fails closed: every check that does not pass is a revert |
| **Admin** (Pattern 2, `immutable`) | Add/remove allowlisted targets, change the daily cap, pause and resume | Sign an Intent, execute, move funds, or bypass the cap itself | Any execution attempt is still a normal Intent; `NotAdmin()` for non-admins |
| **Agent** (Pattern 3) | Create proposals, vote once per proposal | Execute directly; vote twice; vote on proposals older than its registration; vote on an executed or rejected proposal | `DirectExecutionDisabled()`, `AlreadyVoted()`, epoch check, status checks |
| **Arbiter** (Pattern 3, `immutable`) | Add/remove agents, resolve a pending proposal as approved (at quorum) or rejected | Execute without quorum; bypass the signer's signature; resolve twice; act on an executed proposal | Quorum check, signature and nonce checks, status checks, `onlyArbiter` |
| **Target contract** | Whatever it does with the call it receives | Influence the executor's policy | A reverting target rolls the whole Intent back (`test/Pattern2.t.sol:test_RevertWhenTargetCallFailsAndRollsBackState`) |

Two consequences worth stating plainly:

- **The admin is not all-powerful in the direction that matters.** It can lower the cap
  below what is already spent (`test/Pattern2.t.sol:test_ReducingSpendingCapBelowSpentAmountBlocksFurtherSpending`),
  which blocks further spending but cannot recover or redirect funds.
- **No role can rotate its key.** `agentSigner`, `admin` and `arbiter` are `immutable`.
  Rotation requires deploying a new contract and migrating state; the migration order and
  the cost of getting it wrong are in `docs/security.md`.

## 3. Failure and stop paths

Every row is a behaviour a reader can reproduce, with the test that pins it. File paths are
relative to `test/`.

| Situation | What the contract does | Test |
|---|---|---|
| Signature does not recover to `agentSigner` | Reverts with `InvalidSignature()`; no nonce change, no transfer | `Pattern1.t.sol:test_RevertWhenSignatureIsInvalid` |
| Signature is malleable (high `s`) | Reverts; the recovered address is not the signer | `SecurityReview.t.sol:test_RejectsMalleableHighSSignature` |
| Signature was produced for another chain | Reverts; the domain separator differs | `SecurityReview.t.sol:test_RejectsSignatureFromAnotherChain` |
| The same signed Intent is replayed | Reverts with `InvalidNonce()`; the nonce already advanced | `SecurityReview.t.sol:test_ReplayAfterExecutionRevertsOnNonce` |
| An earlier nonce is skipped | Reverts with `InvalidNonce()`; a future nonce can be queued and later executed | `SecurityReview.t.sol:test_QueuedFutureNonceExecutesAfterEarlierIntent` |
| `deadline` has passed | Reverts with `IntentExpired()`; the boundary second itself is allowed | `Pattern1.t.sol:test_RevertWhenExpired`, `SecurityReview.t.sol:test_DeadlineBoundaryIsInclusive` |
| The Intent exceeds the remaining daily cap | Reverts with `SpendingCapExceeded()`; accounting and nonce untouched | `Pattern2.t.sol:test_RevertWhenSpendingCapExceeded` |
| The Intent is exactly at the cap | Executes; the inclusive boundary is deliberate | `Pattern2.t.sol:test_ExecuteAtExactDailySpendingCap` |
| The cap was spent yesterday | The lazy day reset clears `dailySpent` on the next execution; idle days do not accumulate | `SecurityReview.t.sol:test_DayResetDoesNotAccumulateAcrossIdleDays` |
| A transaction straddles UTC midnight | Two caps can be spent seconds apart; documented, not a bug | `SecurityReview.t.sol:test_BoundaryStraddleAllowsTwoCapsCloseTogether` |
| The contract is paused | Reverts with `ContractPaused()`, checked **before** the allowlist | `Pattern2.t.sol:test_RevertWhenEmergencyStopped`, `SecurityReview.t.sol:test_ContractPausedTakesPrecedenceOverTargetNotAllowed` |
| The contract is resumed | The same signed Intent executes; yesterday's spend is not carried over | `SecurityReview.t.sol:test_ResumeExecutesTheSameSignedIntent`, `SecurityReview.t.sol:test_ResumeAfterMidnightDoesNotCarryYesterdaySpend` |
| The target was never allowlisted | Reverts with `TargetNotAllowed()` | `Pattern2.t.sol:test_RevertWhenTargetNotAllowed` |
| The target call fails | The whole Intent reverts; recorded spend and nonce roll back | `Pattern2.t.sol:test_RevertWhenTargetCallFailsAndRollsBackState` |
| A contract re-enters `execute` | `nonReentrant` blocks it; the cap is still respected | `Pattern2.t.sol:test_ReentrancyCannotExceedDailySpendingCap`, `Pattern3.t.sol:test_ReentrancyCannotExecuteSecondProposal` |
| A non-admin calls an administrative function | Reverts with `NotAdmin()` | `Pattern2.t.sol:test_RevertWhenNonAdminChangesSpendingCap` |
| Someone tries to execute Pattern 3 directly | Reverts with `DirectExecutionDisabled()` | `Pattern3.t.sol:test_RevertWhenDirectExecutionIsAttempted` |
| A proposal has too few approvals | Execution reverts with `InsufficientVotes()`; it stays pending | `Pattern3.t.sol:test_RevertWhenApprovingWithoutQuorum` |
| A squatted nonce stalls a proposal | It stays pending until the arbiter rejects it, which releases the nonce | `SecurityReview.t.sol:test_SquattedNonceStallsPipelineUntilArbiterRejects` |
| A proposal's deadline passes while pending | It cannot execute but can still be rejected | `SecurityReview.t.sol:test_ExpiredProposalCannotExecuteButCanBeRejected` |
| An agent is removed mid-flight | Its vote on an existing proposal stays counted; quorum was snapshotted at proposal time | `SecurityReview.t.sol:test_RemovedAgentCannotVoteOnExistingProposal`, `Pattern3.t.sol:test_RemovingAgentDoesNotLowerExistingProposalQuorum` |

The stop paths are all **reverts**, not silent adjustments. There is no "best effort"
mode: a rejected Intent produces no transfer, no nonce change and no recorded spend.

### Sequence-level properties

Five invariants run against a handler that executes allowlisted and non-allowlisted Intents,
changes the native and token caps, transfers a registered token, jumps days and pauses and
resumes, over 256 runs and 128,000 calls:

| Invariant | Property |
|---|---|
| `invariant_ExecutionNeverExceedsCap` | No execution leaves the recorded spend above the cap in force at that moment (checked after each execution, so the admin's documented ability to lower the cap below what is already spent is not misreported as a spend) |
| `invariant_NoExecutionWhilePaused` | No execution succeeds while the contract is paused |
| `invariant_NonceMatchesExecutions` | The nonce advances exactly once per successful execution |
| `invariant_BalanceMatchesOutflow` | Contract balance equals funding minus recorded outflow, and the target really received that ether |
| `invariant_TokenSpendNeverExceedsCap` | No transfer of a registered token leaves that token's recorded spend above its non-zero cap |

The first two have been mutation-checked: removing the pause check fails the second with
`an execution succeeded while paused`, and a cap check that ignores the new value fails the
first with `an execution left dailySpent above the cap`.

## 4. The three patterns are layers, not alternatives

| | Pattern 1 | Pattern 2 | Pattern 3 |
|---|---|---|---|
| What it constrains | Whether an authorized Intent may execute at all | How much a single key may move, and where | Who must agree before execution |
| Decision maker | The signer, per Intent | The signer, within admin-set limits | A quorum of agents, resolved by the arbiter |
| Stolen-key outcome | Total loss in one transaction | Loss limited to one cap per day, and never to a non-allowlisted target | No execution: one key is below quorum |
| New failure mode it introduces | A leaked key drains instantly | A leaked key drains slowly, and a pause blocks legitimate work too | A squatted nonce or an absent arbiter stalls the pipeline |
| Where it is tested | `Pattern1.t.sol` | `Pattern2.t.sol`, `Pattern2Fuzz.t.sol`, `Pattern2Invariant.t.sol` | `Pattern3.t.sol` |

`test/AttackComparison.t.sol` runs the same threat — the planner key is stolen, the attacker
holds every signature, the contract holds 5 ETH — against all three, so the difference is an
assertion rather than a claim: `test_StolenPlannerKey_DrainsPattern1` (5 ETH gone in one
Intent), `test_StolenPlannerKey_IsBoundedInPattern2` (one cap, non-allowlisted target
refused), `test_StolenPlannerKey_DrainsPattern2OverDays` (3 ETH still takes three days), and
`test_StolenPlannerKey_CannotExecuteAloneInPattern3` (balance unchanged, nonce still 0).

That last row is the honest boundary of the second: a daily cap is a rate limit, not a
barrier. It converts an instant total loss into a predictable slow loss. Pattern 3 removes
single-key execution but adds a liveness dependency on the arbiter. The patterns compose:
Pattern 2 and Pattern 3 both build on Pattern 1's signature and nonce rules, and a design
that wants both a cap and a quorum would have to combine the two policies explicitly —
this repository does not implement that combination. They are three points on one design
axis, not three products.

## 5. What this evidence does not cover

Stated so that no reader has to infer it:

- **The five invariants do not prove liveness.** Removing the pause check or the cap check
  is caught; removing `dailySpent += intent.value`, or the `dailySpent = 0` in the day
  reset, is not. Accounting and the day boundary are pinned by the unit and fuzz suites
  (`test/Pattern2Fuzz.t.sol`, and the mutation results in the README), not by the invariants.
  A suite that is green says the tested properties hold, not that every reachable state was
  visited.
- **Searching is not proving.** The handler found no violation across 128,000 calls (256
  runs of 500 calls each); that is evidence about those calls, not a proof.
- **Pattern 3 concentrates authority in the arbiter.** The arbiter decides membership and
  resolves arbitration, and is `immutable`, so a lost arbiter key freezes governance until a
  redeploy. Quorum is snapshotted at proposal time, so removing agents does not lower an
  existing proposal's threshold.
- **Native value only, plus one token path.** The daily cap tracks native transfers. On the
  metered path a registered token's direct `transfer` is bounded by that token's own daily
  cap (`SecurityReview.t.sol:test_TokenTransfersAreBoundedByTheirOwnCap`). Anything that
  moves tokens outside that path — an allowance that already existed at activation time, or a
  target that pulls with `transferFrom` — is outside both caps.
- **No upgradeability, no rotation.** `immutable` keys and no proxy: rotation means a new
  deployment and a migration.
- **Tests are not an audit.** Nothing here has been reviewed by an independent party, and
  no claim of production readiness is made anywhere in this repository.

## 6. Where to go next

| Question | Document |
|---|---|
| What each pattern does, step by step | [`patterns.md`](patterns.md) |
| Findings, dispositions, key lifecycle, liveness traps | [`security.md`](security.md) |
| How to run and verify everything | [README, Testing](../README.md#testing) |
| How to contribute without weakening the evidence | [CONTRIBUTING.md](../CONTRIBUTING.md) |
