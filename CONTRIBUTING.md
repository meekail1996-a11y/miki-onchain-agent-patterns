# Contributing

Thanks for taking the time to look at this repository.

It is an educational reference for connecting an AI agent to smart contracts through a
signed planner/executor, a bounded executor, and multi-agent arbitration. It is **not** an
audited or production-ready codebase, so contributions are judged on whether they make the
demonstrated patterns clearer and better tested — not on whether they add features quickly.

Bug reports, documentation corrections, new adversarial tests and focused contract changes
are all welcome. Before you start, read [`AGENTS.md`](AGENTS.md) (the layout, the
non-negotiable rules and the release process) and [`docs/security.md`](docs/security.md)
(what is already documented as a deliberate limitation).

Several things that look like bugs are documented decisions: the lazy daily reset in
Pattern 2, the native-only spending cap, the snapshot quorum in Pattern 3, and the
`immutable` privileged addresses. A change to any of them is welcome, but the pull request
has to say why the trade-off is now different, and it has to update the documentation and
the tests that pin it.

## Setting up

```bash
git clone https://github.com/meekail1996-a11y/miki-onchain-agent-patterns.git
cd miki-onchain-agent-patterns
git submodule update --init --recursive   # forge-std and OpenZeppelin
python -m pip install -r requirements.txt # first run only
```

You need Foundry and Python 3.10 or newer. Nothing needs a private key or a deployment:
the suites run against local test contracts only. On Windows, `forge` is often not on
`PATH`; the repository's own convention is to call it as
`"$HOME/.foundry/bin/forge.exe"`.

## Checks to run before opening a pull request

```bash
forge test
python -m unittest discover -s tests -v
bash scripts/test_release_workflow.sh
python scripts/check_doc_claims.py        # needs forge on PATH, or FORGE=/path/to/forge
```

These are the same four checks CI runs on every push to `main` and every pull request
(`python-validation`, `solidity-tests`, `release-workflow-guard`, `docs-claims` in
[`.github/workflows/tests.yml`](.github/workflows/tests.yml)).

`scripts/check_doc_claims.py` fails when a document cites a `test_*` name that no test
defines, or quotes a test count that `forge test` does not report. `CHANGELOG.md` is
excluded on purpose: its historical counts were correct for the releases they describe.

## Rules for changes

### Contracts

- **Do not change `pragma solidity ^0.8.20`.** The version is part of the educational
  premise. Compiler concerns belong in `docs/security.md`, not in place.
- Use custom errors rather than `require` strings, and follow the existing naming and
  event conventions in the contract you are editing.
- Keep deliberate orderings intact unless the change is the point of the pull request:
  Pattern 2 checks `paused` before the allowlist, and the day reset runs inside `execute`.
- Line endings are governed by `.gitattributes` (LF). Keep comments and identifiers in
  English, and avoid reformatting lines your change does not need — a diff that touches
  every line is hard to review.

### Tests

- **Never weaken a test to make it pass.** No removed assertions, no `vm.assume` that
  quietly narrows a case until it always passes, no `try/catch` that swallows a revert, no
  skipped tests, no type or lint suppressions. If a test is wrong, fix its premise and
  explain why in the pull request.
- **A new test has to fail when the behaviour it describes is removed.** Delete the line
  locally, run the suite, restore it, and say in the pull request what you observed. A
  passing suite is not evidence on its own.
- **Do not add tests that merely restate documented behaviour.** A test earns its place by
  pinning something a future change could plausibly break, or a boundary that was
  previously only asserted in prose.
- `test/SecurityReview.t.sol` carries the adversarial evidence the documentation cites.
  Add cases to it, but do not rewrite it wholesale.

### Documentation

- When the suite size changes, update the `Ran N test suites … N tests passed` line, the
  suite table and the coverage figures in `README.md` and `docs/security.md`, and add a
  changelog entry. A number in the documentation that does not match `forge test` output is
  a defect, and `check_doc_claims.py` will reject it.
- `docs/security.md` records every Slither finding with an explicit disposition. Do not
  "fix" a finding by suppressing it; either change the code and the tests, or add a written
  justification.
- Keep the claims honest. This project has no audit, no production deployment, no users and
  no partnerships; do not introduce language that implies otherwise, in the README, the
  changelog, or the grant drafts under `docs/grants/`.

## Changelog and versions

Add your change to the `## [Unreleased]` section of [`CHANGELOG.md`](CHANGELOG.md) under
`Added`, `Changed`, `Fixed` or `Security`, in the style already used there. Do not bump the
version, move `Unreleased` into a release heading, or create a tag — releasing is the
maintainer's step-by-step process, described at the end of `AGENTS.md`.

## Pull requests

- Keep a pull request to one concern. A contract change, its tests and its documentation
  belong together; an unrelated refactor does not.
- Say what changed and why, and call out anything a reviewer would not guess: a changed
  revert path, a new ordering, a test premise you had to correct.
- List the checks you ran and their result. If a check could not run on your machine, say so
  instead of leaving it out.
- If behaviour changes, state what existing deployments or tests would notice.

## Reporting bugs and vulnerabilities

- **Ordinary bugs and documentation errors:** open a GitHub issue with the commit or tag you
  tested, your `forge --version`, and the smallest sequence of calls or commands that shows
  the problem.
- **Security issues:** do not open a public issue with exploit details. Use GitHub private
  vulnerability reporting as described in [`SECURITY.md`](SECURITY.md), which also lists
  what is in scope and what is out of scope. Behaviour already recorded as a known
  limitation is out of scope by definition.

## License

By contributing you agree that your contribution is licensed under the terms of this
repository's [`LICENSE`](LICENSE), the same license the project itself is distributed under.
