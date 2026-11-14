# Grant draft — TheDAO Security Fund, ETHSecurity Initiatives

Working draft for https://initiatives.thedao.fund/submit. The round is open from
September 15, 2026 with no published closing date; the directory lists it as running to
January 31, 2027. Fill the `TODO` fields before submitting.

**Ask:** $15,000 in one tranche (milestone-based split below). Small asks are normal here:
the platform shows initiatives between $10k and $265k, and each one needs a minimum amount
pledged before it qualifies for TheDAO's vote.

---

## Title

An executable security reference for AI-agent smart contracts

## One-line summary

An open, test-backed reference that shows what a compromised AI-agent key can and cannot
do under three contract patterns — with an attack lab, a threat model, and mutation-tested
suites instead of prose claims.

## Category

Audits & Analysis (secondary: Fuzzing & Testing)

## Problem

Teams are wiring LLM agents to on-chain permissions right now, and most of them design the
policy layer by intuition: a daily cap with no defined reset semantics, an allowlist that
is never reviewed, a signing key living in the same process as the model. There is plenty
of material about how to *call* a contract from an agent; there is very little that is
executable about how to *bound* one, and what bounded autonomy does and does not buy you
when the key is stolen.

The reusable knowledge exists, but it is scattered across audit reports and post-mortems
that are written for auditors and priced for teams that already have one.

## What will be built

1. **Attack comparison lab** (upstreamed, already drafted): one threat — stolen planner
   key — executed against a signature-only executor, a capped executor, and a multi-agent
   arbitration contract, with the loss recorded as an assertion rather than a claim.
2. **Threat model with test evidence**: assets, actors, capabilities, controls, residual
   risk, and the name of the test that demonstrates each control.
3. **Parameter guidance**: how to choose a cap, a quorum, and an allowlist for an agent
   deployment, including the reset-semantics trap (a per-calendar-day cap permits two caps
   across midnight) and the liveness trap (a squatted nonce can stall an arbitration
   pipeline until the arbiter intervenes).
4. **Key lifecycle guidance**: what `immutable` signer and admin addresses cost
   operationally, and a documented migration path for rotation, since rotation is not
   possible in-contract today.
5. **Verification habits as artifacts**: the mutation-check results, the fuzz properties,
   and the CI guard that keeps them from regressing — so a reader can rerun the evidence
   instead of trusting it.

All of it is MIT-licensed, in one repository, runnable with `forge test`.

## Why this matters for Ethereum security

Agent-driven transactions concentrate risk in a single key while removing the human who
used to read the confirmation screen. The defensive patterns are simple, but the failure
modes around them are not: a cap that resets on the wrong boundary, a pause that silently
invalidates signed intents, a quorum that one compromised agent can stall. Educational
material that stops at "use an allowlist and a cap" hides exactly those edges.

This initiative produces the missing middle layer: a reference implementations plus the
evidence that the mitigations behave as described, free for any team to copy, test, and
argue with.

## Deliverables and milestones

| Milestone | Deliverable | Share |
|---|---|---|
| 1 | Attack comparison lab merged, with README table generated from the tests | 30% |
| 2 | Threat model document with per-control test evidence | 25% |
| 3 | Parameter and key-lifecycle guidance, reviewed against the contracts | 25% |
| 4 | Mutation and fuzz evidence published in CI artifacts; a one-page "how to reuse this in your repo" guide | 20% |

Each milestone is a merged pull request in the public repository; the tranche is released
after review of the diff and the test output.

## Prior work (evidence the applicant can execute)

- The repository already contains the three patterns, a Python EIP-712 signer, 81 tests
  (fuzz properties included), a documented static-analysis pass, and a CI release guard.
- Two targeted mutations were applied and caught: removing the spend counter broke 14
  tests, removing the daily reset broke 6; the original contract was restored and the full
  suite passed again.
- `docs/security.md` records the Slither findings with an explicit disposition for each,
  including the ones deliberately left unfixed.

Repository: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns

## Team

TODO: name, location, GitHub handle, any prior public work or audits. A solo applicant is
acceptable for this size of ask; say so plainly and list what you have shipped.

## Budget

| Item | Amount |
|---|---|
| Writing and reviewing the threat model and guidance | $9,000 |
| Attack lab, fuzz properties, and CI evidence (about 3 weeks) | $4,500 |
| Review pass by an independent Solidity developer | $1,500 |
| **Total** | **$15,000** |

Payment in ETH to a wallet the applicant controls. TODO: wallet address (only on the
official form, never in this repository).

## Sustainability

The repository is not a product and does not need ongoing revenue: the output is a
reference that stays useful as long as agents hold keys. Maintenance is limited to keeping
the Foundry test suite green on new compiler versions, which the existing CI already does.

## Risks and honesty

- This is educational material, not an audit. It will not claim to make any specific
  protocol safe, and the repository states that scope in `Scope and Guarantees`.
- The patterns cover native-asset transfers; ERC-20 exposure and upgradeability are out of
  scope and documented as such.
- If a milestone slips, the tranche is not released; the repository stays public either
  way.

---

## Before submitting

- [ ] Replace every `TODO` (team, wallet, repository owner details).
- [ ] Confirm eligibility for the applicant's jurisdiction and the fund's terms; several
      Ethereum-ecosystem programs exclude sanctioned jurisdictions and require KYC on the
      recipient. Ask info@thedao.fund before spending time on the form.
- [ ] Publish the repository state you want reviewed (tag a release so the application
      points at a fixed commit).
- [ ] Pledge the minimum needed for TheDAO's vote; the platform shows that threshold per
      initiative.
