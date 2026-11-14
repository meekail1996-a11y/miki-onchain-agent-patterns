# Security Policy

## Project status

This repository is an **educational and experimental reference project** for
constrained AI-agent interactions with smart contracts.

- It has **not** undergone an independent professional security audit.
- It is **not production-ready** and must not be used to custody real funds.
- It is maintained by a single person, on a best-effort basis.
- There is **no bug bounty** and no payment is offered for reports.

If you are evaluating this code for real deployment, treat every pattern as a
starting point that still needs your own review, hardening and audit.

## Supported versions

| Version | Supported |
| ------- | --------- |
| Latest tagged release on `main` (see the Releases page) | Yes |
| Any earlier tag or release | No — superseded |
| Older commits, forks, and local modifications | No |

Only the most recent tag on `main` receives fixes; this table is deliberately not
pinned to a version number, so it cannot go stale between releases. Because the
contracts are not proxy-upgrade compatible, a fix ships as a new deployment, not
as an upgrade to an existing one.

## Reporting a vulnerability

**Preferred channel: GitHub private vulnerability reporting.**

1. Open <https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/security/advisories/new>
   (or the repository's **Security** tab → **Report a vulnerability**).
2. Describe the issue privately. The report stays visible only to you and the
   maintainer.

If private reporting is unavailable, open a regular issue that contains **no
exploit details** and simply asks for a private channel. Do not disclose the
vulnerability publicly before a fix or an agreed disclosure date.

### What to include

A useful report contains:

- **Affected component** — `Pattern1_PlannerExecutor`, `Pattern2_BoundedAutonomy`,
  `Pattern3_MultiAgentArbitration`, the Python signer, or the tooling.
- **Impact** — what an attacker gains: theft of funds, unauthorised execution,
  bypass of the allowlist or spending cap, denial of service, replay, and so on.
- **Reproduction** — a Foundry test, a minimal sequence of calls, or exact steps,
  including the commit or tag you tested.
- **Preconditions** — required roles, deployed configuration, chain, and whether
  a privileged key (admin, arbiter, signer) must be compromised first.
- **Suggested fix**, if you have one.
- **Your disclosure preference** — credited, pseudonymous, or anonymous.

Please avoid attaching real private keys, mainnet transaction data, or other
people's data.

## Scope

**In scope**

- `contracts/*.sol` — the three reference implementations.
- `scripts/sign_intent.py` and the Python test suite under `tests/`.
- The GitHub Actions workflows in `.github/workflows/`.

**Out of scope**

- Third-party dependencies in `lib/` (OpenZeppelin, forge-std). Report those
  upstream.
- Issues that require a compromised or malicious admin, arbiter, or signer key
  acting as designed. Privileged-key risk is documented, not a vulnerability.
- Behaviours that are already listed as known limitations in
  [`docs/security.md`](docs/security.md) — for example: the native spending cap
  does not bound ERC-20 transfers; agents can squat a nonce; the arbiter has no
  enforced timeout.
- Gas optimisations, style, and documentation wording.
- Anything that only exists in a locally modified fork.
- Mainnet deployment incidents; this project is not intended for mainnet use.

## Known limitations

The full threat model, controls per pattern and known limitations live in
[`docs/security.md`](docs/security.md). In short:

- Anyone holding a valid signed Intent can submit it; the relayer is not bound.
- Pattern 1 has no allowlist and no spending cap.
- Pattern 2 caps native value only, and its administrative authority is
  centralised with no multisig or timelock requirement.
- Pattern 3 depends on the arbiter for liveness and membership; it is not
  decentralised consensus, and arbiter rotation is not implemented.
- There are no proxy storage layouts; the contracts target fresh deployments.

## Response expectations

These are intentions, not a service-level agreement:

- Acknowledgement of a private report within about 7 days when possible.
- An initial assessment, including whether the report is in scope, as soon as
  the maintainer can reproduce it.
- A fix and a published advisory for confirmed in-scope issues; a public
  advisory is published after the fix, with credit if you want it.

## Safe harbour

Security research is welcome when it is conducted in good faith:

- Test against local chains, testnets, and your own deployments only.
- Do not access, modify or exfiltrate other people's data or funds.
- Do not run denial-of-service attacks, spam, or social engineering against the
  maintainer or contributors.
- Give the maintainer a reasonable window to fix an issue before publishing.

Reports made in good faith under these conditions will be treated as
authorised research, not as an attack on the project.
