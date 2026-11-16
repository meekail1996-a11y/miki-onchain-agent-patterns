#!/usr/bin/env bash
#
# Runs the four checks CI runs, in the same order, with one command:
#
#   1. the Foundry suite                 (job: solidity-tests)
#   2. the Python signer suite           (job: python-validation)
#   3. the release-workflow harness      (job: release-workflow-guard)
#   4. the documentation claim guard     (job: docs-claims)
#
# Usage:
#   bash scripts/verify_all.sh
#
# Foundry must be on PATH, or FORGE must point at the binary. Python
# dependencies from requirements.txt must be installed for step 2.
# Exit status is non-zero if any check fails.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

forge_bin="${FORGE:-forge}"
python_bin="${PYTHON:-python3}"
failures=0

step() { printf '\n== %s\n' "$1"; }
check() { # name, then the command
  local name="$1"
  shift
  if "$@"; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name"
    failures=$((failures + 1))
  fi
}

step "Solidity suite"
if ! command -v "$forge_bin" >/dev/null 2>&1; then
  printf 'FAIL  forge not found: set FORGE or add it to PATH\n'
  failures=$((failures + 1))
else
  check "forge test" "$forge_bin" test
fi

step "Python signer suite"
check "unittest" "$python_bin" -m unittest discover -s tests

step "Release workflow harness"
check "test_release_workflow.sh" bash scripts/test_release_workflow.sh

step "Documentation claims"
check "check_doc_claims.py" "$python_bin" scripts/check_doc_claims.py

printf '\n'
if [ "$failures" -eq 0 ]; then
  echo "All four checks passed."
  exit 0
fi

echo "$failures check(s) failed."
exit 1
