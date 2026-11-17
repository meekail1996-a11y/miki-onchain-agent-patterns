# Grant draft — TheDAO Security Fund, ETHSecurity Initiatives

Working draft for https://initiatives.thedao.fund/submit. The round is open from
September 15, 2026 with no published closing date; the directory lists it as running to
January 31, 2027. Fill the `TODO` fields before submitting.

This draft is written against the shipped `v0.1.8` state
(https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/releases/tag/v0.1.8).
It deliberately separates **what exists** from **what the grant would fund**, because most
of what an earlier draft promised as future work is already merged and tested.

**Ask:** $15,000 in one tranche (milestone-based split below). Small asks are normal here:
the platform shows initiatives between $10k and $265k, and each one needs a minimum amount
pledged before it qualifies for TheDAO's vote.

---

## Title

Hardening an executable security reference for AI-agent smart contracts

## One-line summary

The reference is public and tested at `v0.1.8`; this grant funds the four gaps the
repository documents about itself — an independent review, a mutation-testing campaign,
ERC-20 exposure, and key rotation — so that the evidence behind it stops depending on one
author's judgement.

## Category

Audits & Analysis (secondary: Fuzzing & Testing)

## What already exists

Shipped, tagged, and reproducible from a fresh clone. Nothing in this section is proposed
work.

| Component | State |
|---|---|
| Three reference contracts (planner/executor, bounded autonomy, multi-agent arbitration) | Merged, `v0.1.8` |
| Solidity suite | 82 tests in 8 suites, green in CI |
| Sequence-level invariants | 4 invariants, 256 runs, 128,000 handler calls, every handler action succeeding |
| Python EIP-712 signer and digest-parity tests | 7 tests, green in CI |
| Mutation checks | 2 targeted mutations recorded (14 and 6 failing tests), plus 2 on the invariants |
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

A Solidity reviewer outside this project reads the contracts against the documented
controls and publishes findings with a disposition for each, in the same format as the
existing Slither table. Deliverable: a review report plus either a code change or a written
justification per finding.

This is the item that matters most, because today every claim in the repository is
self-assessed. No amount of additional self-testing removes that.

Scope, stated so the number is defensible: this is a review of three contracts by one
independent reviewer, **not** a full audit engagement — no protocol-level threat model, no
infrastructure or operational review, no formal verification. The $6,000 is a review-sized
budget, and if the quotes for that scope come back higher, the milestone is re-scoped to
fit rather than padded to match a quote.

### M2 — Mutation-testing campaign ($3,000, 20%)

The README records two targeted mutations, explicitly described as "not a mutation-testing
campaign". This milestone replaces that sentence with a campaign: a scripted run of
contract-level mutations (drop a check, invert a comparison, skip a state update) with a
table of which tests and which invariants caught each one. Deliverable: the script, the
report, and the guarantee that a mutation which survives is either killed with a new test
or written down as a known hole.

### M3 — ERC-20 exposure ($4,000, 27%)

`dailySpent` tracks native value only; a token transfer through an allowlisted target
bypasses the cap entirely, and a test asserts exactly that
(`test/SecurityReview.t.sol:test_TokenTransfersAreNotBoundedByTheNativeCap`). This milestone
designs and implements token-aware limits (per-token accounting or a documented
token-allowlist policy), with the same adversarial coverage the native path has. Deliverable:
contract change, tests, and a written note on why the chosen accounting cannot be gamed by
an allowance or a fee-on-transfer token.

### M4 — Key rotation and administrative hardening ($2,000, 13%)

`agentSigner`, `admin` and `arbiter` are `immutable`, so a lost key means a new deployment.
Deliverable: a design document for rotation (multisig or timelocked admin, arbiter transfer)
with the migration order spelled out, plus a reference implementation for at least the admin
path and tests for the failure mode where rotation happens mid-proposal.

## Why this scope

The reference exists. Asking a fund to pay for it again would be dishonest, and a reviewer
who reads the repository would see that immediately. What a single author cannot produce
alone is exactly what is listed: an outside opinion, a systematic instead of anecdotal
mutation record, coverage of a value path the code currently ignores, and a rotation design
that trades away `immutable`'s simplicity.

## Evidence a reviewer can rerun

From a fresh clone, no keys, no deployment:

```bash
git submodule update --init --recursive
forge test                                   # 82 tests, 8 suites
python -m unittest discover -s tests -v      # 7 tests
bash scripts/verify_all.sh                   # all four CI checks locally
```

Expected tail of the Solidity run:

```text
Ran 8 test suites in 20.27s (20.86s CPU time): 82 tests passed, 0 failed, 0 skipped (82 total tests)
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

## Team

TODO: full name, location, and jurisdiction eligibility. A solo applicant is acceptable for
this size of ask; the point below is what has been shipped.

- GitHub: [@beshavard_eth](https://github.com/meekail1996-a11y) — owner and sole author of
  this repository: three contracts, 82 Solidity tests, the Python signer, both CI workflows,
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
| M3 — ERC-20 limits, design and implementation | $4,000 | 27% |
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
- After M3, token limits will still depend on the target's token behaviour; fee-on-transfer
  and rebasing tokens are a known source of accounting bugs and will be documented as such
  rather than claimed as solved.
- M4 may conclude that the safest rotation design is "redeploy and migrate"; if so, the
  deliverable is the documented procedure, not new code.
- If a milestone slips, the tranche is not released.

---

## Before submitting

- [ ] Replace every `TODO` (name, location, wallet, jurisdiction).
- [ ] Confirm eligibility for the applicant's jurisdiction and the fund's terms; several
      Ethereum-ecosystem programs exclude sanctioned jurisdictions and require KYC on the
      recipient. Ask info@thedao.fund before spending time on the form.
- [ ] Point the application at `v0.1.8`, not `main`: the tag is the state this draft describes.
- [ ] Pledge the minimum needed for TheDAO's vote; the platform shows that threshold per
      initiative.
- [ ] Decide whether a second application (Ethereum Foundation ESP, tooling and education)
      is worth writing separately. The same text must not be sent to both: ESP funds public
      tooling, this round funds hardening, and a reviewer who sees one text twice discounts
      both.
