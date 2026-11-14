# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the project is at `0.x`, breaking changes may land in minor versions.

## [Unreleased]

## [v0.1.2] - 2026-11-14

### Added

- `SECURITY.md` security policy: project status, the private reporting channel via
  GitHub Security Advisories, what a useful report must contain, in/out-of-scope
  boundaries, response expectations and safe-harbour terms. Private vulnerability
  reporting is enabled on the repository, with a link from the README.
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

[Unreleased]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.1...HEAD
[v0.1.2]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/compare/v0.1.1...v0.1.2
[v0.1.1]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/releases/tag/v0.1.1
[v0.1.0]: https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/releases/tag/v0.1.0