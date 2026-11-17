#!/usr/bin/env python3
"""Fail when published documentation drifts from the test suite.

Three classes of claim are checked:

1. Every `test_*` or `invariant_*` name mentioned in the documentation must exist in
   the Foundry suite. A renamed or deleted test must not leave a document pointing at
   nothing.
2. Every plain test count in the documentation ("82 tests passed", "82-test suite",
   "82 Solidity tests", "82 tests, 0 failures") must equal the number Foundry reports.
3. Every suite count ("Ran 8 test suites") must equal the number of test contracts
   Foundry reports.

Foundry runs every `invariant_*` function of a contract inside a single test, so an
invariant contract counts as one test and not one per invariant. The count here mirrors
that, which is why the total matches the `N tests passed` line the README quotes.

Run with `--self-test` to check the patterns themselves against fixtures, without Forge:
that is the regression test for this guard. It exists because the guard once missed
`(77 tests, 0 failures)` — a sentence whose shape no pattern covered — and a passing run
on real docs could not reveal it. `scripts/verify_all.sh` and the CI job run both modes.

The documents checked are the ones a reader can act on: the README, the security model,
the contributor and security guides, and the grant drafts — the grant material is what a
funder reads, so a stale figure there matters as much as one in the README.

CHANGELOG.md is deliberately excluded: it records what was true at each release, so
historical counts there are correct even when they differ from today's suite.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = [
    "README.md",
    "docs/security.md",
    "AGENTS.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
]
DOC_GLOBS = ["docs/grants/*.md"]

# Not preceded by a path separator: `scripts/test_release_workflow.sh` is a script,
# not a test function.
TEST_NAME = re.compile(r"(?<![A-Za-z0-9_/])(?:test|invariant)_[A-Za-z0-9_]+")

# Each shape a test count is written in somewhere in the documentation. A new sentence
# shape needs a new pattern; `--self-test` is what keeps that honest.
COUNT_CLAIMS = [
    re.compile(r"(\d+) tests passed"),  # README run output
    re.compile(r"(\d+) tests, 0 failures"),  # README mutation-check sentence
    re.compile(r"(\d+)-test suite"),  # docs/security.md coverage paragraph
    re.compile(r"(\d+) Solidity tests"),  # README feature line, grant prior work
]
SUITE_CLAIMS = [re.compile(r"Ran (\d+) test suites")]


def find_forge() -> str:
    env = os.environ.get("FORGE")
    if env:
        return env
    found = shutil.which("forge")
    if found:
        return found
    for candidate in ("forge.exe", "forge"):
        path = Path.home() / ".foundry" / "bin" / candidate
        if path.exists():
            return str(path)
    sys.exit("check_doc_claims: forge not found; set FORGE or add it to PATH")


def suite_contents() -> tuple[set[str], int, list[str]]:
    proc = subprocess.run(
        [find_forge(), "test", "--list", "--json"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        errors="replace",
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout + proc.stderr)
        sys.exit("check_doc_claims: `forge test --list --json` failed")

    try:
        listing = json.loads(proc.stdout)
    except json.JSONDecodeError:
        sys.exit("check_doc_claims: could not parse `forge test --list --json` output")

    known: set[str] = set()
    suites: list[str] = []
    invariant_suites = 0
    test_count = 0

    for contracts in listing.values():
        for functions in contracts.values():
            suites.append("contract")
            has_invariant = False
            for name in functions:
                if name.startswith("test"):
                    known.add(name)
                    test_count += 1
                elif name.startswith("invariant_"):
                    known.add(name)
                    has_invariant = True
            if has_invariant:
                invariant_suites += 1

    if not known:
        sys.exit("check_doc_claims: no tests parsed; the --list format may have changed")
    if not suites:
        sys.exit("check_doc_claims: no suites parsed; the --list format may have changed")

    # Two suites may define the same test name; the count is per run, not per name.
    total = test_count + invariant_suites
    return known, total, suites


def claim_failures(
    doc: str, text: str, known: set[str], total: int, suite_count: int
) -> list[str]:
    failures: list[str] = []

    for name in sorted(set(TEST_NAME.findall(text))):
        if name not in known:
            failures.append(f"{doc}: mentions {name}, which no test defines")

    for pattern in COUNT_CLAIMS:
        for raw in pattern.findall(text):
            claimed = int(raw)
            if claimed != total:
                failures.append(
                    f"{doc}: claims {claimed} tests, the suite has {total} "
                    f"(matched {pattern.pattern!r})"
                )

    for pattern in SUITE_CLAIMS:
        for raw in pattern.findall(text):
            claimed = int(raw)
            if claimed != suite_count:
                failures.append(
                    f"{doc}: claims {claimed} test suites, `forge test` runs "
                    f"{suite_count} (matched {pattern.pattern!r})"
                )

    return failures


def documents() -> list[str]:
    found = list(DOCS)
    for pattern in DOC_GLOBS:
        found.extend(sorted(str(p.relative_to(ROOT)) for p in ROOT.glob(pattern)))
    return found


def self_test() -> int:
    """Pin the patterns themselves, so a shape the guard cannot see is a failing test."""
    known = {"test_RealOne", "invariant_RealInvariant"}
    cases = [
        # (description, text, expected number of failures)
        (
            "current run output",
            "Ran 8 test suites in 20.27s: 82 tests passed, 0 failed, 0 skipped",
            0,
        ),
        (
            "mutation-check sentence, current count",
            "the full suite passed again (82 tests, 0 failures).",
            0,
        ),
        (
            "mutation-check sentence, stale count",
            "the full suite passed again (77 tests, 0 failures).",
            1,
        ),
        ("coverage paragraph", "the 82-test suite, statements 96.00%", 0),
        ("feature line", "82 Solidity tests and 7 Python tests", 0),
        ("stale suite count", "Ran 7 test suites in 20.27s", 1),
        ("existing test name", "asserted in test_RealOne", 0),
        ("invented test name", "asserted in test_DoesNotExist", 1),
        ("invented invariant name", "asserted in invariant_DoesNotExist", 1),
    ]

    problems = 0
    for description, text, expected in cases:
        failures = claim_failures("fixture.md", text, known, total=82, suite_count=8)
        if len(failures) != expected:
            problems += 1
            print(
                f"  FAIL  {description}: expected {expected} failure(s), got {len(failures)}"
            )
            for failure in failures:
                print(f"        {failure}")

    if problems:
        print(f"self-test failed: {problems} case(s) behaved unexpectedly")
        return 1
    print(f"self-test OK: {len(cases)} cases, every count shape is checked")
    return 0


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()

    known, total, suites = suite_contents()
    failures: list[str] = []

    for doc in documents():
        path = ROOT / doc
        if not path.exists():
            failures.append(f"{doc}: listed as a checked document but does not exist")
            continue
        failures.extend(
            claim_failures(doc, path.read_text(encoding="utf-8"), known, total, len(suites))
        )

    if failures:
        print("Documentation and test suite disagree:\n")
        for failure in failures:
            print(f"  - {failure}")
        print(f"\nSuite size: {total} tests in {len(suites)} suites.")
        return 1

    print(
        f"OK: {total} tests in {len(suites)} suites, every referenced test name "
        "and every count matches the docs."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
