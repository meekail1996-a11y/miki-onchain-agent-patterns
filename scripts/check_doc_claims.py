#!/usr/bin/env python3
"""Fail when published documentation drifts from the test suite.

Two classes of claim are checked:

1. Every `test_*` name mentioned in the documentation must exist in the Foundry
   suite. A renamed or deleted test must not leave a document pointing at nothing.
2. Every plain test count in the documentation ("81 tests passed", "81-test
   suite") must equal the number of tests Foundry reports.

CHANGELOG.md is deliberately excluded: it records what was true at each release,
so historical counts there are correct even when they differ from today's suite.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ["README.md", "docs/security.md", "AGENTS.md"]

# Not preceded by a path separator: `scripts/test_release_workflow.sh` is a script,
# not a test function.
TEST_NAME = re.compile(r"(?<![A-Za-z0-9_/])test_[A-Za-z0-9_]+")
COUNT_CLAIMS = [
    re.compile(r"(\d+) tests passed"),  # README run output
    re.compile(r"(\d+)-test suite"),  # docs/security.md coverage paragraph
    re.compile(r"(\d+) Solidity tests"),  # README feature line
]


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


def suite_tests() -> list[str]:
    proc = subprocess.run(
        [find_forge(), "test", "--list"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        errors="replace",
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout + proc.stderr)
        sys.exit("check_doc_claims: `forge test --list` failed")

    tests: list[str] = []
    for line in proc.stdout.splitlines():
        match = re.match(r"^\s{4}(test[A-Za-z0-9_]*)\s*$", line)
        if match:
            tests.append(match.group(1))
    if not tests:
        sys.exit("check_doc_claims: no tests parsed; the --list format may have changed")
    return tests


def main() -> int:
    tests = suite_tests()
    # Two suites may define the same test name; the count is per run, not per name.
    known = set(tests)
    failures: list[str] = []

    for doc in DOCS:
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
                if claimed != len(tests):
                    failures.append(
                        f"{doc}: claims {claimed} tests, the suite has {len(tests)} "
                        f"(matched {pattern.pattern!r})"
                    )

    if failures:
        print("Documentation and test suite disagree:\n")
        for failure in failures:
            print(f"  - {failure}")
        print(f"\nSuite size: {len(tests)} tests.")
        return 1

    print(f"OK: {len(tests)} tests, every referenced test name and count matches the docs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
