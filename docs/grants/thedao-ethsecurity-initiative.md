# Grant draft — TheDAO Security Fund, ETHSecurity Initiatives

Working draft for https://initiatives.thedao.fund/submit. The round is open from
September 15, 2026 with no published closing date; the directory lists it as running to
January 31, 2027. Fill the `TODO` fields before submitting.

The baseline is the shipped `v0.1.8` state
(https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/releases/tag/v0.1.8).
M3 v1 is merged to `main`; its 110-test, 9-suite validation passes locally, and the `Tests`
run on that commit is the CI record rather than a figure quoted here.
It deliberately separates **what exists** from **what the grant would fund**, because most
of what an earlier draft promised as future work is already merged and tested.

**Ask:** $15,000 in one tranche (milestone-based split below). Small asks are normal here:
the platform shows initiatives between $10k and $265k, and each one needs a minimum amount
pledged before it qualifies for TheDAO's vote.

---

## Title

Hardening an executable security reference for AI-agent smart contracts

## One-line summary

The reference is public and tested at `v0.1.8`, and a metered ERC-20 transfer path is
implemented in the local working tree; this grant funds the three gaps the repository
documents about itself — an independent review, a mutation-testing campaign, and key
rotation — plus the second version of that ERC-20 work: allowance exposure, controlled
router support, the migration and revocation tooling, and an independent review of v1.
The point is that the evidence behind the reference stops depending on one author's
judgement.

## Category

Audits & Analysis (secondary: Fuzzing & Testing)

## What already exists

Shipped, tagged, and reproducible from a fresh clone, except where a row says otherwise.
Nothing in this section is proposed work, and a row labelled local is evidence of what the
author can build, not a shipped capability.

| Component | State |
|---|---|
| Three reference contracts (planner/executor, bounded autonomy, multi-agent arbitration) | Merged, `v0.1.8` |
| Solidity suite | 110 tests in 9 suites, green locally; the CI run on that commit is the first pass that covers the metered path |
| Metered ERC-20 transfer path (M3 v1) | Merged to `main`; 23 of the suite's tests cover it |
| Sequence-level invariants | 5 invariants, 256 runs, 128,000 handler calls, every handler action succeeding (measured locally) |
| Python EIP-712 signer and digest-parity tests | 7 tests, green in CI |
| Mutation checks | 5 targeted mutations recorded (14, 6, 8, 1 and 2 failing tests), plus 2 on the invariants; measured locally, not in CI |
| Static analysis | Slither findings with an explicit disposition for each, including the unfixed ones |
| Architecture, threat model, limitations | [`docs/architecture.md`](../architecture.md), [`docs/security.md`](../security.md), [`docs/patterns.md`](../patterns.md) |
| CI | 4 jobs on every push: Solidity, Python, release harness, documentation guard |
| Documentation guard | Rejects a test count or a test name in the docs that the suite does not have |

One test runs the same threat — the planner key is stolen, the attacker holds every
signature, the contract holds 5 ETH — against all three patterns and records the outcome as
an assertion: instant loss, loss bounded to one cap per day, or no execution without a
quorum.

## Problem

Teams are wiring LLM agents to on-chain permissions right now, and most of them design the
policy layer by intuition: a daily cap with no defined reset semantics, an allowlist that
is never reviewed, a signing key living in the same process as the model. There is plenty
of material about how to *call* a contract from an agent; there is very little that is
executable about how to *bound* one, and what bounded autonomy does and does not buy you
when the key is stolen.

The reusable knowledge mostly sits in audit reports and post-mortems written for auditors
and priced for teams that already have one.

## What the grant funds

Every item below is a gap the repository names about itself. None of it is built.

### M1 — Independent review of the three contracts ($6,000, 40%)

This is the item that matters most, because today every claim in the repository is
self-assessed. No amount of additional self-testing removes that.

**In scope, stated so the number is defensible.** `contracts/Pattern1_PlannerExecutor.sol`,
`contracts/Pattern2_BoundedAutonomy.sol` and `contracts/Pattern3_MultiAgentArbitration.sol`,
read at the commit the milestone starts from, with `test/SecurityReview.t.sol` supplied to
the reviewer as the map of what is already asserted — the reviewer's job is to find what
those tests miss, not to re-derive them. The reviewer reads against the controls the
repository claims (domain-separated signatures, nonce rules, allowlist, daily cap, pause
precedence, quorum and arbiter paths) and says where a claim is weaker than it reads.

**Explicitly out of scope:** the Python signer, the CI workflows, deployment and operational
security, gas, and formal verification. This is one independent reviewer over three files,
**not** a protocol audit, and no milestone in this application should be read as one.

**Definition of done.** The review is delivered when every finding carries one of four
outcomes: fixed in this milestone, fixed in a named later milestone, accepted as a risk with
a written justification added to `docs/security.md`, or rejected as not-a-finding with the
reason stated. A finding closed as "won't fix" without that sentence is an undelivered
finding, and the milestone stays open. The report is published in the repository with the
reviewer's name attached.

If quotes for this exact scope come back higher, the milestone is re-scoped — fewer
contracts, or a narrower question — rather than padded to match a quote.

### M2 — Mutation-testing campaign ($3,000, 20%)

The README records two targeted mutations, explicitly described as "not a mutation-testing
campaign". This milestone replaces that sentence with one, at a size a reviewer can check.

**Fixed count and classes.** At least 30 mutants across at least six classes: delete a
guard, invert a boolean condition, move an inequality boundary (`>` to `>=` and back), drop
a state update, reorder two checks whose ordering is documented (the pause-before-allowlist
order is the known case), and remove an event emission. Each mutant is a single-line edit
applied to a scratch copy, the full suite plus the four invariants run against it, and the
outcome recorded as killed-by (which tests, which invariant) or survived.

**Deliverable.** The script that applies and reverts each mutant, and a report table with
one row per mutant. Every survivor resolves one of two ways: a new test that kills it, or a
row under a new "mutation survivors" heading in `docs/security.md` stating whether the
mutant is behaviourally equivalent (and why) or a real uncovered behaviour. Survivors left
unexplained do not count as delivered.

**Honest bound.** These are hand-written contract-level mutants; the deliverable is not a
mutation score. A percentage over a chosen mutant list measures the list as much as the
suite, so the report gives the table, not a headline number.

### M3 — ERC-20 exposure: v2, migration tooling and review of v1 ($4,000, 27%)

The repository shipped with a documented gap: `dailySpent` tracks native value only, so a
token movement through an allowlisted target bypassed the native cap. **Version 1 of the
metered path closes one call shape inside that gap, and it is merged to `main`.**
It is evidence of what the author can deliver, not work this milestone charges for.

**What v1 does, at the width of the guarantee.** A token registered with `addMeteredToken`
can be paid only by a direct, standard ERC-20 `transfer` issued by the executor, and the
declared amount is charged against that token's own daily cap before the call is made.
`approve`, `increaseAllowance` and `transferFrom` are refused on the target; a `transfer` on
a token that was never registered is refused; calldata that is not exactly two words is
refused; and a return value that is not a single `true` word is a failure rather than a
success. The bound is on **declared amounts of direct transfers of standard tokens**;
fee-on-transfer and rebasing behaviour, and any movement outside this path, are outside it.
The registry is append-only, and a zero cap is the stop switch
(`test/SecurityReview.t.sol:test_TokenTransfersAreBoundedByTheirOwnCap` records the shape).

**What v1 does not do, and what this milestone funds.** Three things stay open, and none of
them is claimed as delivered:

- **Allowance exposure.** The executor cannot enumerate or revoke the allowances granted to
  it, and an allowance that already existed when the policy was first relied on can still be
  spent outside any Intent. Today that is a migration prerequisite, not a control.
- **Routers and aggregators.** `transferFrom` is never executed, so the common pull-payment
  shape is not supported at all. Supporting it safely needs an exposure ledger, not a
  selector allowlist.
- **Migration and revocation tooling.** An operator has no supported way to find and revoke
  the allowances an executor has granted, which is exactly the step the guarantee depends on.

**Why v1's shape was chosen, and why it is not the whole answer.** The executor forwards
calldata and does not know what the target does with it, so a token limit cannot simply
increment from `intent.value`. Declared-amount accounting is cheap and honest about its
width; a measured-delta design would see pull payments but makes correctness depend on what
the token does to balances. v1 ships the first, refuses the selector that would make the
second invisible, and leaves the ledger design to v2 rather than implying it is covered.

**Deliverable.** A second version of the metered path with an allowance-exposure ledger and
a documented, tested answer for router-mediated transfers; a migration tool that enumerates
and revokes outstanding allowances; adversarial tests in the same style as v1's 23,
including the two cases that record the current hole
(`test_PreExistingAllowanceIsPulledWithoutAnyExecution` and
`test_IndirectPullDuringExecutionIsNotCharged`); and an independent review of v1 and v2
inside the review scope M1 defines. The branch this milestone does not build is written into
Future Work rather than implied.

**Why the milestone survived the gap partly closing.** v1 shows the shape of the solution and
its ceiling. v2 is the part that needs the ledger design, the tooling and a second pair of
eyes — which is what a single author cannot produce alone. The $4,000 buys that, not a path
that already exists.

### M4 — Key rotation and administrative hardening ($2,000, 13%)

Rotation is not one problem here, and the milestone is scoped by which key it is:

| Key | Where it is immutable | What it can do | Deliverable |
|---|---|---|---|
| `agentSigner` | `Pattern1`, inherited by patterns 2 and 3 | Authorise every intent | Code and tests |
| `admin` | `Pattern2` | Widen the allowlist, raise the cap, pause | Code and tests |
| `arbiter` | `Pattern3` | Add and remove agents, resolve proposals | Code, or a documented procedure if code would disturb pending proposals |

The Pattern 3 agent set is already mutable through `addAgent` and `removeAgent`; this
milestone does not re-open that, except where rotation changes its interaction with
`agentEpoch` and quorum.

**Required tests for whichever paths ship as code:** an intent signed by the previous
`agentSigner` does not execute after rotation; a queued future nonce — behaviour currently
pinned by `test_QueuedFutureNonceExecutesAfterEarlierIntent` — has its post-rotation
treatment decided explicitly and tested rather than left to fall out of the implementation;
rotation while paused does not strand the contract; and the event trail identifies who
rotated, to what, and on whose authority.

**Arbiter path:** if rotation is delivered as a procedure rather than code, the design
document must argue why — the pending-proposal and reserved-nonce rules (`test_SquattedNonceStallsPipelineUntilArbiterRejects`) are the reason this is not free — and the procedure
must state the order: pause, rotate, confirm, resume, plus what each step guarantees if it
fails halfway.

**Deliverable:** the design document with that ordering, the implementation for at least
`agentSigner` and `admin`, and the tests above. If the honest conclusion is that some key
should be rotated by redeploying and migrating instead, the deliverable is the documented
procedure and the argument for it — the same standard the Risks section already sets.

## Future Work

Recorded here so that a proposal is never mistaken for a shipped capability.

- **Branch 2 — allowance exposure ledger.** Charge an Intent for the lifetime exposure an
  allowance represents, instead of for the transfer that happens inside the call. It is the
  only design that can see a pull, and it is what M3 v2 evaluates. It is not implemented
  today.
- **Router and aggregator support.** Deliberately absent from v1: a router calls
  `transferFrom` from inside its own frame, so the executor observes neither the token nor
  the amount. Adding it means bounding exposure, not allowing a selector.
- **Non-standard token behaviour.** Fee-on-transfer, rebasing, and tokens that do not return
  a single `true` word remain outside the guarantee. v1 refuses the last category rather than
  tolerating it.
- **Allowance revocation as a contract feature.** Today it is an operational step during
  migration. Making it a control needs a way to enumerate spenders, which the ERC-20
  interface does not offer.

## Why this scope

The reference exists. Asking a fund to pay for it again would be dishonest, and a reviewer
who reads the repository would see that immediately. What a single author cannot produce
alone is exactly what is listed: an outside opinion, a systematic instead of anecdotal
mutation record, the second version of a value path the code bounds for one call shape
today, and a rotation design that trades away `immutable`'s simplicity.

## Evidence a reviewer can rerun

From a fresh clone, no keys, no deployment:

```bash
git submodule update --init --recursive
forge test                                   # 110 tests, 9 suites
python -m unittest discover -s tests -v      # 7 tests
bash scripts/verify_all.sh                   # all four CI checks locally
```

Expected tail of the Solidity run:

```text
Ran 9 test suites in 29.13s (29.66s CPU time): 110 tests passed, 0 failed, 0 skipped (110 total tests)
```

The repository's documentation guard is part of CI: a README that quotes a stale test count,
or a document that names a test the suite does not have, fails the build. That guard was
added after the README was found quoting a figure from before the invariant suite.

## What this grant will not claim

- No audit of any third-party protocol, and no claim that these patterns make a specific
  deployment safe.
- No production readiness. The repository says so in `Scope and Guarantees` and repeats it in
  every document.
- No users, integrations, or partnerships: there are none to point at, and inventing them
  would be the fastest way to fail review.
- No claim that M3 v1 protects ERC-20 holdings in general. It bounds one call shape, and the
  allowance and router paths listed under Future Work are open.

## Team

TODO: full name, location, and jurisdiction eligibility. A solo applicant is acceptable for
this size of ask; the point below is what has been shipped.

- GitHub: [@beshavard_eth](https://github.com/meekail1996-a11y) — owner and sole author of
  this repository: three contracts, 110 Solidity tests, the Python signer, both CI workflows,
  and the documentation set.
- Twelve years running a school. Relevant as evidence of long-horizon delivery and
  documentation discipline, **not** as security experience — remove this line if you would
  rather not include personal background at all.

TODO: wallet address (only on the official form, never in this repository).

## Budget

| Item | Amount | Share |
|---|---|---|
| M1 — Independent review of the three contracts | $6,000 | 40% |
| M2 — Mutation-testing campaign and report | $3,000 | 20% |
| M3 — ERC-20 exposure v2, migration tooling and review of v1 | $4,000 | 27% |
| M4 — Rotation design and admin hardening | $2,000 | 13% |
| **Total** | **$15,000** | |

Payment in ETH to a wallet the applicant controls. The tranche is released after review of
each milestone's diff and test output; a slipped milestone is not paid, and the repository
stays MIT-licensed and public either way.

## Sustainability

The repository is not a product and needs no ongoing revenue: the output is a reference that
stays useful as long as agents hold keys. Maintenance is limited to keeping the Foundry suite
green on new compiler versions, which the existing CI already does.

## Risks and honesty

- This is educational material, not an audit. It will not claim to make any specific
  protocol safe, and the repository states that scope in `Scope and Guarantees`.
- M3 v1's bound covers declared amounts of direct transfers of standard tokens only.
  Fee-on-transfer and rebasing behaviour, an allowance that predates the policy, and
  router-mediated pulls are outside it, and are documented as such rather than claimed as
  solved.
- M4 may conclude that the safest rotation design is "redeploy and migrate"; if so, the
  deliverable is the documented procedure, not new code.
- If a milestone slips, the tranche is not released.

---

## Before submitting

- [ ] Replace every `TODO` (name, location, wallet, jurisdiction).
- [ ] Confirm eligibility for the applicant's jurisdiction and the fund's terms; several
      Ethereum-ecosystem programs exclude sanctioned jurisdictions and require KYC on the
      recipient. Ask info@thedao.fund before spending time on the form.
- [ ] Point the application at the `v0.1.9` tag once it is pushed, not `main`: tags do not
      move. `v0.1.8` describes the suite before the metered path and must not be quoted for
      the current counts.
- [ ] Pledge the minimum needed for TheDAO's vote; the platform shows that threshold per
      initiative.
- [ ] Decide whether a second application (Ethereum Foundation ESP, tooling and education)
      is worth writing separately. The same text must not be sent to both: ESP funds public
      tooling, this round funds hardening, and a reviewer who sees one text twice discounts
      both.
