# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the project is at `0.x`, breaking changes may land in minor versions.

## [v0.1.9] - 2026-11-18

A metered ERC-20 path for Pattern 2: a registered token can be paid only by a direct
standard `transfer`, against that token's own daily cap. The bound is on declared amounts of
direct transfers of standard tokens; allowances, router pulls and non-standard token
behaviour are documented as outside it.

### Added

- Metered ERC-20 transfers in `Pattern2_BoundedAutonomy` (M3, first version). A token
  registered with `addMeteredToken(token, capPerDay)` can only be paid by a direct,
  standard `transfer` issued by the executor, and the declared amount is charged against
  that token's own daily cap before the call is made. The guarantee is stated for the
  declared amounts of successful direct transfers of standard tokens; fee-on-transfer,
  rebasing and non-standard return values are outside it.
- `addMeteredToken` requires the token to be an allowlisted target and rejects the zero
  address or an address with no code (`InvalidToken`). It is idempotent and the registry
  array only grows: there is no removal function, and `setTokenCap(token, 0)` is how a
  token is stopped. A positive cap below the day's spend is refused (`TokenCapBelowSpent`),
  so `tokenSpentToday <= tokenCapPerDay` holds for every non-zero cap.
- `approve`, `increaseAllowance` and `transferFrom` are refused (`TokenCallForbidden`) on
  the metered path, with a non-zero `value` refused the same way. `transfer` on a token
  that was never registered is `TokenNotRegistered`; calldata that is not exactly 68 bytes
  is `MalformedTokenCall`; a call that reverts, returns fewer or more than 32 bytes, or
  returns a word other than `1` is `TokenTransferFailed`. `SafeERC20` is deliberately not
  used, because it accepts an empty return value.
- The Intent prologue (deadline, nonce, signature, `nonce++`) is duplicated in Pattern 2
  rather than carved out of Pattern 1, which is unchanged; `Pattern1`'s `_executeIntent`
  discards the callee's return value, which this path has to read. Two tests pin the
  deadline and nonce rules on both paths.
- `test/TokenControls.t.sol` adds 23 tests covering the selectors, registration, the cap,
  the three failing return shapes, and the duplicated prologue. The suite moves 87 → 110
  tests and 8 → 9 suites, and the invariant suite gains `invariant_TokenSpendNeverExceedsCap`
  (4 → 5 invariants).
- Five adversarial tests in `test/SecurityReview.t.sol` that record what the ERC-20 side of
  Pattern 2 does *not* bound, so that accounting decisions can be argued from executable
  cases instead of prose. No contract behaviour changed and none of these is a fix:
  `test_ApproveCreatesAllowanceAtZeroBalanceDelta` (an `approve` creates an allowance with no
  balance movement, and the pull that spends it needs no second Intent),
  `test_PreExistingAllowanceIsPulledWithoutAnyExecution` (an allowance that exists when the
  policy is first relied on is spent with no execution, so no nonce and no counter moves),
  `test_IndirectPullDuringExecutionIsNotCharged` (a target that pulls with `transferFrom`
  moves the executor's balance inside the executed call),
  `test_OutAndBackLeavesTenUnitLossWithinOneExecution` (100e18 out and 90e18 back leaves a
  10e18 loss, which is what a before/after reading could charge and is not the gross
  outflow), and `test_ExecutorDoesNotImplementERC1271` (the `0x1626ba7e` selector is absent,
  which is the whole claim: token-specific `permit` variants are a separate review).
  `PullRouter` and `RebateRouter` are the mocks behind them, and the suite grows 82 → 87.
- Two of those tests were also checked for non-vacuity by breaking the scenario they depend
  on — zeroing the router's balance and its allowance — confirming both fail, and restoring
  the file. That is not a mutation campaign: the behaviour they pin is the absence of
  accounting, and the only change that would flip them is the accounting work itself, which
  is not built.

### Changed

- `test_ApproveCreatesAllowanceAtZeroBalanceDelta` is now
  `test_ApproveIsRefusedAndCreatesNoAllowance`: the premise changed by design, so the
  assertion changed with it rather than the other way round.
- `test_TokenTransfersAreNotBoundedByTheNativeCap` is now
  `test_TokenTransfersAreBoundedByTheirOwnCap`, rewritten rather than deleted.
- `test/Pattern2Invariant.t.sol` gained `transferToken` and `changeTokenCap` handler actions;
  a successful token transfer also consumes a nonce, so it counts as an execution there.
- The README mutation section records five targeted mutations instead of two (M3 removed the
  token charge and failed 8 tests, M4 the length check and failed 1, M5 the return-value
  check and failed 2).
- `Pattern2_BoundedAutonomy` is now at 100% of lines, statements, branches and functions.
- The earlier note in this section stands for the version it describes:
  `test/Pattern2Invariant.t.sol` now drives all four handler actions. `changeCap` and
  `togglePause` called admin-only functions from the handler, which is not the admin, so
  both reverted on every call (31,895/31,895 and 32,167/32,167 in the trace table) and the
  invariants never observed a cap change or a pause. They are pranked as the admin now, and
  every action succeeds.
- `invariant_DailySpendNeverExceedsCap`, named in the v0.1.8 notes, is now
  `invariant_ExecutionNeverExceedsCap`; the released text is left as it was published.
- The spend invariant compared the live `dailySpent` with the live cap. That flagged the
  admin's documented ability to lower the cap below what is already spent, which is not a
  spend. It is replaced by `invariant_ExecutionNeverExceedsCap`, which checks the property
  where it belongs — right after each execution — and by `invariant_NoExecutionWhilePaused`,
  which gives the pause path something to break. Two mutations: dropping the pause check
  fails with `an execution succeeded while paused`, and a cap check that ignores the new
  value fails with `an execution left dailySpent above the cap`. Both were reverted.

### Fixed

- `README.md` said the suite passed again with "77 tests, 0 failures" after the mutation
  checks, a figure from before the invariant suite. The documentation guard missed it
  because none of its patterns covered that sentence shape. It now checks
  `N tests, 0 failures` and runs a fixture-based `--self-test`, so deleting a pattern
  fails the build instead of silently reopening the hole.

## [v0.1.8] - 2026-11-17

Sequence-level invariants for Pattern 2, a documentation guard that reads the suite instead
of guessing, and social assets that follow the new count. No contract behaviour changed.

### Added

- `test/Pattern2Invariant.t.sol`: sequence-level invariants for Pattern 2, which the fuzz
  suite could not reach because it checks single calls. Over 256 runs and 128k handler calls
  they assert that `dailySpent` never exceeds the cap in force, that the nonce advances once
  per successful execution, and that the contract balance equals the ether the target really
  received. Removing the cap check makes `invariant_DailySpendNeverExceedsCap` fail with
  `dailySpent exceeded the cap`; the check was restored and the suite went green again.
- `docs/security.md`: a `Test Evidence` table mapping each documented control to the test
  that would fail if it were removed, so a reviewer can go from a claim to an assertion.
  The documentation guard already rejects a test name that no test defines, so the table
  cannot rot silently.
- `scripts/verify_all.sh`: one command for the four checks CI runs, referenced from the
  README testing section and from `CONTRIBUTING.md`.
- README: a `Contributing` link in the navigation, which previously existed only in the
  file tree and in GitHub's own issue UI.

### Fixed

- `assets/social/`: the card and the 12-second video still said "81 Solidity tests" after the
  invariant suite made it 82. Both are re-rendered from their sources, so the published
  image matches the suite the README quotes.

## [v0.1.7] - 2026-11-16

Contributor guide, social assets for the stolen-key post, and a documentation guard that now
covers the grant material as well as the README.

### Added

- `scripts/check_doc_claims.py` and a `docs-claims` CI job: the documentation may only
  cite test names that exist and test counts that match the suite. It caught two real
  drifts on its first run — a stale `60 Solidity tests` comment and a coverage paragraph
  that reflected an older suite.
- `docs/security.md`: `Key Lifecycle` and `Liveness and Stalled Pipelines` sections. They
  record what each `immutable` key can do, what losing or leaking it costs, the migration
  order when rotation is required, and the fact that every stall path ends in an arbiter
  call — none of the controls in this repository is a liveness control. This landed after
  `v0.1.6` was tagged, so it is not part of that release.
- `CONTRIBUTING.md`: the setup steps (including the submodules), the four local checks that
  CI also runs, and the rules a change has to follow — no weakened tests, a mutation check
  for every new test, documentation counts kept in sync with `forge test`, and the
  private-advisory channel for security reports.
- `assets/social/four-rows-card.html` and `.png`: a 1600×900 card for the "one stolen key,
  four designs" post. Rows 01–03 are the tested patterns; row 04 is labelled
  `external — not tested here` so the card cannot be read as a claim about this repository.
- `assets/social/four-rows-12s.mp4` (with an original synthesised ambient bed), `-silent.mp4`,
  `-12s.gif` and `-12s-poster.png`: a 12-second 1080×1350 motion graphic of the same card, for
  embeds that cannot play video and for platforms that autoplay muted.

### Changed

- `docs/security.md` coverage figures re-measured after the invariant suite landed:
  statements 96.00% (120/125) and branches 85.71% (30/35) on the pinned solc 0.8.38, with
  lines and functions unchanged at 100%. The old figures came from an earlier toolchain.
- `Pattern2_BoundedAutonomy` rejects non-admin callers with a `NotAdmin()` custom error
  instead of a `require` string, matching the error style of the rest of the contract.
  The five tests that pinned the old revert data now assert the selector. No other
  behaviour changed.
- `scripts/check_doc_claims.py` now also checks `CONTRIBUTING.md`, `SECURITY.md` and the grant
  drafts, and verifies suite counts (`Ran 7 test suites`) as well as test counts. Three
  mutations were applied to prove the new checks fail rather than decorate a passing run: a
  stale grant figure, a wrong suite count and an invented test name each failed the guard,
  and the files were restored afterwards.

### Fixed

- Leftover non-English comments removed or translated: the `calldata`/`memory` note in
  `Pattern1_PlannerExecutor.execute` and two comments in `test/SecurityTests.t.sol`.
- `AGENTS.md` listed the CI workflow as `test.yml`; the file is
  `.github/workflows/tests.yml`.
- The changelog link block still compared `[Unreleased]` against `v0.1.5` and had no
  `[v0.1.6]` definition, so the released version rendered as literal bracketed text.

## [v0.1.6] - 2026-11-15

Test and documentation pass. No contract behaviour changed.

### Added
- `test/AttackComparison.t.sol`: the same threat — a stolen planner key with every
  signature valid — executed against all three patterns, so the difference between them
  is asserted rather than described: Pattern 1 loses the whole balance, Pattern 2 is held
  to its allowlist and daily cap and then drained over three days, and Pattern 3 cannot
  execute without a second agent's approval.
- `docs/grants/thedao-ethsecurity-initiative.md`: draft application for TheDAO Security
  Fund's open ETHSecurity Initiatives round, with milestones and the eligibility checks
  that must be made before submitting.
- `test/SecurityReview.t.sol`: emergency-stop cases — a rejected Intent leaves the nonce
  and the daily spend untouched, the same signed Intent executes after
  `emergencyStop(false)`, `ContractPaused` takes precedence over `TargetNotAllowed`, and
  a pause across midnight does not carry yesterday's spend into the new day.
- Validation: two targeted mutations (`dailySpent += intent.value` and `dailySpent = 0`
  in the daily reset) were each caught by the suite, with 14 and 6 failing tests; the
  original contract was restored and the full 77-test run passed again (77 tests at the
  time; the suite is now 81).
- `README.md`: new `Scope and Guarantees` and `Mutation Checks` sections, which state what
  the project does and does not guarantee and record the mutation evidence.
- `test/SecurityReview.t.sol`: combined-state cases — a proposal that reaches quorum
  despite a cast rejection, a queued future-nonce proposal that executes once the
  executor nonce catches up, and a replay of an already executed Intent rejected by
  the nonce.
- `test/SecurityReview.t.sol`: day-boundary cases for the Pattern 2 cap — the cap still
  applies one second before midnight, the reset happens exactly at the boundary, idle
  days do not accumulate allowance, and a midnight straddle can move twice the cap
  within seconds (documented consequence).
- `scripts/test_release_workflow.sh`: a harness that extracts the publish step from
  `.github/workflows/release.yml` and runs it against a stubbed `gh` for four cases —
  a matching changelog section, a missing section, a missing `CHANGELOG.md`, and a
  release that already exists.
- A `release-workflow-guard` CI job runs that harness on every push to `main` and on
  every pull request, so the release guard cannot regress unnoticed.

## [v0.1.5] - 2026-11-14

### Changed

- The `Release` workflow now fails when `CHANGELOG.md` is missing, or when it has no
  section for the pushed tag, instead of publishing a release with a placeholder
  note. The failure is reported as a `::error::` annotation and no release is
  created, so a missing version entry cannot slip out silently.

## [v0.1.4] - 2026-11-14

Coverage and documentation alignment pass. No contract behaviour changed.

### Added

- `test/SecurityReview.t.sol`: seven further scenarios — direct `receive()` funding of
  the executor, a negative vote recorded as a rejection, resolving an already-executed
  proposal, resolving a rejected proposal, and zero-address guards for `agentSigner`,
  allowlist targets and `arbiter`.
- `docs/security.md`: a static analysis section recording the six Slither detector
  classes, each with an assessment and its residual risk, plus the current
  `forge coverage` figures.

### Changed

- README and `docs/security.md` now describe the `admin` and `arbiter` roles as
  `immutable`, matching the contracts; the roadmap item for arbiter transfer is marked
  as requiring a redesign.
- `.gitignore` ignores `lcov.info`, so coverage output cannot leak into commits.

### Fixed

- `docs/patterns.md` claimed Pattern 3 "does not enforce a voting quorum"; it does
  (approval reverts with `InsufficientVotes` below the stored quorum). The document
  now also covers per-proposal eligibility, nonce reservation, terminal rejection,
  disabled direct execution and the immutable `admin`/`arbiter` roles.
- `SECURITY.md` pointed at a Python signer "under `tests/`"; it lives in
  `scripts/sign_intent.py`, while `tests/` holds the Python test suite.

## [v0.1.3] - 2026-11-14

### Added

- `SECURITY.md` security policy: project status, the private reporting channel via
  GitHub Security Advisories, what a useful report must contain, in/out-of-scope
  boundaries, response expectations and safe-harbour terms. Private vulnerability
  reporting is enabled on the repository, with a link from the README.
- README: a constrained treasury payment case study, a section explaining what a
  signed Intent does and does not prove, and a one-block "Run it yourself" path
  with the expected output of both test suites.

### Changed

- `admin` (Pattern 2) and `arbiter` (Pattern 3) are now `immutable`, removing
  administrative reassignment entirely; the residual key-loss risk is documented.
- Solidity is pinned to `0.8.38` with `evm_version = "shanghai"`.

### Fixed

- `docs/security.md` had been truncated mid-sentence; the Pattern 3 nonce policy,
  known limitations, storage/upgradeability notes, operational recommendations and
  the security status section are restored.

## [v0.1.2] - 2026-11-14

### Added

- `test/SecurityReview.t.sol`: tests pinning guarantees that were documented but not
  previously exercised — malleable (high-`s`) signature rejection, cross-chain replay
  rejection, the inclusive deadline boundary, recovery from a proposal that expires
  before resolution, nonce squatting and its arbiter-dependent release, blocked votes
  from removed agents, and token transfers escaping the native spending cap.
- `docs/security.md` now states the signature-canonicalisation, chain-binding,
  deadline and deferred-resolution guarantees explicitly.

## [v0.1.1] - 2026-11-14

Documentation and release-automation follow-up. No contract or signer behaviour changed.

### Added

- `CHANGELOG.md` following Keep a Changelog, seeded with the v0.1.0 entry.
- Latest-release badge in the README header and a changelog link in the navigation.
- `release.yml` workflow that publishes a GitHub release from the matching changelog
  section when a `v*` tag is pushed, and skips tags that already have a release.

### Fixed

- Release-note extraction matches the changelog heading with `index()` instead of a
  backslash-escaped regex, so it no longer depends on shell and YAML escaping.

## [v0.1.0] - 2026-11-13

First tagged, presentable version of the reference implementation.

### Added

- Pattern 1 — EIP-712 signed `Intent` executor with nonce and deadline enforcement.
- Pattern 2 — bounded autonomy: admin-managed target allowlist, daily native-asset
  spending cap, pause control and a reentrancy guard.
- Pattern 3 — multi-agent arbitration: proposal lifecycle, quorum snapshots,
  per-proposal voter eligibility, nonce reservation, terminal rejection, and
  execution restricted to the governance contract.
- Python reference signer with input validation and a mainnet guard.
- Foundry test suites: 53 tests, including fuzz coverage for the spending-cap
  accounting invariants.
- GitHub Actions CI running the Solidity and Python suites on every push to `main`.
- Security documentation with a threat model, mitigation table, nonce policy,
  voter-eligibility and storage/upgradeability notes (`docs/security.md`).

### Changed

- Pattern 2 access-control surface unified around `emergencyStop(bool)` and
  `allowedTargets`; related getters renamed for clarity.
- Pattern 3 verifies the Intent signature before reserving the nonce, so a rejected
  signature cannot consume proposal capacity.

### Security

- Zero-address and invalid-configuration checks for targets, admins, arbiters and
  the bound token.
- Spending accounting is written before the external call, so a reverting call
  cannot inflate the remaining daily allowance.
- A paused contract rejects execution with a dedicated `ContractPaused` error.
- An over-cap Intent reverts without changing accounting or the nonce.

### Known limitations

- Not independently audited and **not production-ready**. See `docs/security.md`.

[Unreleased]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.9...HEAD
[v0.1.9]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.8...v0.1.9
[v0.1.8]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.6...v0.1.8
[v0.1.7]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.6...v0.1.7
[v0.1.6]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.5...v0.1.6
[v0.1.5]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.4...v0.1.5
[v0.1.4]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.3...v0.1.4
[v0.1.3]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.2...v0.1.3
[v0.1.2]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.1...v0.1.2
[v0.1.1]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/releases/tag/v0.1.1
[v0.1.0]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/releases/tag/v0.1.0