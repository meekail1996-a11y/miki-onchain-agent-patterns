# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the project is at `0.x`, breaking changes may land in minor versions.

## [Unreleased]

Nothing yet.

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

[Unreleased]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.5...HEAD
[v0.1.5]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.4...v0.1.5
[v0.1.4]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.3...v0.1.4
[v0.1.3]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.2...v0.1.3
[v0.1.2]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.1...v0.1.2
[v0.1.1]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/releases/tag/v0.1.1
[v0.1.0]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/releases/tag/v0.1.0