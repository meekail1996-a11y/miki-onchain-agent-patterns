#!/usr/bin/env python3
"""Fail when published documentation drifts from the test suite.

Three classes of claim are checked:

1. Every `test_*` or `invariant_*` name mentioned in the documentation must exist in
   the Foundry suite. A renamed or deleted test must not leave a document pointing at
   nothing.
2. Every plain test count in the documentation ("82 tests passed", "82-test suite",
   "82 Solidity tests") must equal the number of tests Foundry reports.
3. Every suite count ("Ran 8 test suites") must equal the number of test contracts
   Foundry reports.

Foundry runs every `invariant_*` function of a contract inside a single test, so an
invariant contract counts as one test and not one per invariant. The count here mirrors
that, which is why the total matches the `N tests passed` line the README quotes.

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
COUNT_CLAIMS = [
    re.compile(r"(\d+) tests passed"),  # README run output
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


def documents() -> list[str]:
    found = list(DOCS)
    for pattern in DOC_GLOBS:
        found.extend(sorted(str(p.relative_to(ROOT)) for p in ROOT.glob(pattern)))
    return found


def main() -> int:
    known, total, suites = suite_contents()
    failures: list[str] = []

    for doc in documents():
        path = ROOT / doc
        if not path.exists():
            failures.append(f"{doc}: listed as a checked document but does not exist")
            continue
        text = path.read_text(encoding="utf-8")

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
                if claimed != len(suites):
                    failures.append(
                        f"{doc}: claims {claimed} test suites, `forge test` runs "
                        f"{len(suites)} (matched {pattern.pattern!r})"
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
