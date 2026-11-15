# AGENTS.md

Instructions for coding agents working in this repository. Read this before changing
anything.

## What this repository is

An educational reference for patterns that connect an AI agent to smart contracts:
a signed planner/executor, a bounded executor with an allowlist and a daily cap, and
multi-agent arbitration with an arbiter, plus a Python EIP-712 signer.

It is **not** an audited or production-ready codebase. Do not describe it as one, and do
not add claims of guarantee to the README, the CHANGELOG, or a grant application.

## Layout

| Path | Contents |
|---|---|
| `contracts/Pattern1_PlannerExecutor.sol` | EIP-712 Intent execution, nonce, deadline |
| `contracts/Pattern2_BoundedAutonomy.sol` | Pattern 1 plus target allowlist, daily cap, emergency stop |
| `contracts/Pattern3_MultiAgentArbitration.sol` | Pattern 2's base plus proposals, agent votes, arbiter |
| `test/` | Foundry suites; `SecurityReview.t.sol` holds the adversarial cases |
| `scripts/` | Python signer and the release-workflow harness |
| `docs/security.md` | Static-analysis findings and deliberate limitations |
| `docs/grants/` | Grant application drafts |
| `.github/workflows/` | `test.yml` and `release.yml` |

## Commands

Foundry is not on `PATH` on the maintainer's Windows machine:

```bash
"$HOME/.foundry/bin/forge.exe" test
"$HOME/.foundry/bin/forge.exe" test --match-path test/AttackComparison.t.sol
"$HOME/.foundry/bin/forge.exe" test -vv          # traces for a failing case
python -m unittest discover -s tests -v
bash scripts/test_release_workflow.sh            # the release guard harness
```

For Slither, prepend the Foundry directory to `PATH` first.

Forge writes CRLF on Windows. Pipe through `sed -e 's/\r$//'` before `grep`, and prefer
`str_replace` over rewriting whole files, because a line-ending rewrite produces a diff
that touches every line.

## Non-negotiable rules

1. **Do not change `pragma solidity ^0.8.20`.** The version is part of the educational
   premise. Record a compiler-related concern in `docs/security.md` instead of fixing it
   in place.
2. **Never weaken a test to make it pass.** No removed assertions, no `vm.assume` that
   quietly narrows a case until it always passes, no `try/catch` that swallows a revert,
   no skipped tests, no type or lint suppressions. If a test is wrong, say why in the
   commit message and fix the test's premise, not its assertion.
3. **A passing suite is not evidence on its own.** When you add a test, check that it
   fails when the behaviour it describes is removed (delete the line locally, run, then
   restore with `git checkout`). If a mutation leaves the new test green, find out why
   before calling the coverage real.
4. **Do not add tests that merely restate documented behaviour.** A test earns its place
   by pinning something a future change could plausibly break, or by pinning a boundary
   that was previously only asserted in prose.
5. **The public numbers must match reality.** When the suite size changes, update the
   `Ran N test suites ... N tests passed` line and the suite table in `README.md`, and add
   a CHANGELOG entry. A test count in a README, a release note, or a grant form that does
   not match `forge test` output is a defect.
6. **Commits, pushes, tags and releases need explicit permission** from the maintainer in
   the current conversation. Prepare the change and the proposed commit message; do not
   commit on your own initiative.
7. **Keep `test/SecurityReview.t.sol` changes reviewable.** It carries the adversarial
   evidence that the documentation cites; do not rewrite it wholesale.

## Contracts

- `Pattern2` checks `paused` **before** the allowlist, and the day reset is lazy: it runs
  inside `execute`, so `dailySpent` can still hold yesterday's figure while paused. That
  ordering is deliberate and documented; a test asserts each half.
- Nonce rules: the nonce must equal the executor's current nonce, and Pattern 3 reserves a
  proposed nonce until the proposal is executed or rejected.
- `dailySpent` tracks native value only. ERC-20 transfers bypass the cap, and that is
  documented as a limitation rather than hidden.
- The daily cap resets on UTC calendar-day boundaries, so a transaction on either side of
  midnight can move two caps within seconds. Documented, not a bug.

## Documentation

- `README.md` claims: keep `Scope and Guarantees` and `Mutation Checks` accurate. Mutation
  results quoted there are two targeted mutations, not a mutation-testing campaign; do not
  inflate them.
- `docs/security.md` lists every Slither finding with an explicit disposition. Do not
  "fix" a finding by suppressing it; either change the code and the tests, or add a
  written justification.
- Grant material must stay honest about what is built and what is planned. Distinguish
  shipped work from proposed work, and never invent audits, users, or partnerships.

## Releases

1. Move `## [Unreleased]` content under `## [vX.Y.Z] - YYYY-MM-DD`, leaving an empty
   `## [Unreleased]` above it. `release.yml` fails fast without an exact section heading,
   so a missing entry cannot produce a release with placeholder notes.
2. Commit, push `main`, then tag that same commit and push the tag.
3. Check the `Tests` and `Release` runs for the tag commit, and confirm the published
   release body is the CHANGELOG section (not a placeholder).
4. Link a tag rather than `main` when pointing anyone at a fixed state — `main` moves, tags
   do not.
