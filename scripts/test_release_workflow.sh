#!/usr/bin/env bash
#
# Checks the release workflow's note handling without touching GitHub.
#
# The publish step in .github/workflows/release.yml is extracted verbatim and
# executed against a stubbed `gh`, so the guard logic is tested rather than a
# copy of it. Four cases are covered:
#
#   A. the tag has a matching CHANGELOG section  -> release created from it
#   B. the tag has no matching section           -> exit 1, no release
#   C. CHANGELOG.md is missing                   -> exit 1, no release
#   D. a release already exists for the tag       -> exit 0, nothing created
#
# Usage: bash scripts/test_release_workflow.sh
# Exit status: 0 when every case behaves as expected, 1 otherwise.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/release.yml"

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

failures=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# ---------------------------------------------------------------- extract step

if [ ! -f "$workflow" ]; then
  echo "FAIL  workflow not found: $workflow"
  exit 1
fi

awk '/^        run: [|]$/{ f = 1; next } f { sub(/^          /, ""); print }' \
  "$workflow" > "$work/publish.sh"

if [ ! -s "$work/publish.sh" ]; then
  echo "FAIL  could not extract the run block from $workflow"
  exit 1
fi

if ! bash -n "$work/publish.sh"; then
  echo "FAIL  extracted publish step is not valid shell"
  exit 1
fi

# ------------------------------------------------------------- stub `gh` binary

mkdir -p "$work/bin" "$work/runner-temp"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Records every call, pretends a release exists when the flag file is present.
echo "gh $*" >> "$GH_CALLS"
if [ "$1 $2" = "release view" ]; then
  [ -f "$GH_HAS_RELEASE" ] && exit 0
  exit 1
fi
if [ "$1 $2" = "release create" ]; then
  exit 0
fi
exit 1
STUB
chmod +x "$work/bin/gh"

calls_for() { # case directory -> log file
  echo "$work/calls-${1}.log"
}

# --------------------------------------------------------------------- runner
#
# run_case <label> <dir> <version> [release-exists]
# Sets: $case_exit, $case_stderr, $case_calls, $case_notes (lines or 0)

run_case() {
  local dir="$1" version="$2" exists="${3:-no}"
  local calls="$work/calls-$$.log"
  local stderr_file="$work/stderr-$$.txt"
  local flag="$work/has-release"

  rm -f "$calls" "$stderr_file" "$flag" "$work/runner-temp/release-notes.md"
  [ "$exists" = "yes" ] && : > "$flag"

  ( cd "$dir" && \
    env PATH="$work/bin:$PATH" \
        GH_CALLS="$calls" \
        GH_HAS_RELEASE="$flag" \
        RUNNER_TEMP="$work/runner-temp" \
        GH_TOKEN=stub \
        VERSION="$version" \
        bash "$work/publish.sh" ) 2> "$stderr_file"
  case_exit=$?
  case_stderr="$(cat "$stderr_file" 2>/dev/null || true)"
  case_calls="$(cat "$calls" 2>/dev/null || true)"
  if [ -f "$work/runner-temp/release-notes.md" ]; then
    case_notes="$(wc -l < "$work/runner-temp/release-notes.md" | tr -d ' \r')"
  else
    case_notes=0
  fi
}

created_release() { printf '%s' "$case_calls" | grep -q 'release create'; }
has_message() { printf '%s' "$case_stderr" | grep -q "$1"; }

# A working copy with a real CHANGELOG.md for cases A, B and D.
mkdir -p "$work/with-changelog"
cp "$repo_root/CHANGELOG.md" "$work/with-changelog/CHANGELOG.md"

# A directory with no CHANGELOG.md for case C.
mkdir -p "$work/without-changelog"

# --- case A: section present -------------------------------------------------
version="$(grep -oE '^## \[v[0-9]+\.[0-9]+\.[0-9]+\]' "$repo_root/CHANGELOG.md" | head -1 | sed 's/^## \[\(.*\)\]$/\1/')"

if [ -z "$version" ]; then
  fail "could not find a version heading in CHANGELOG.md"
else
  run_case "$work/with-changelog" "$version" no
  if [ "$case_exit" -eq 0 ] && created_release && [ "$case_notes" -gt 0 ]; then
    pass "A. tag $version with a changelog section publishes notes ($case_notes lines)"
  else
    fail "A. tag $version should publish notes (exit=$case_exit, notes=$case_notes)"
  fi
fi

# --- case B: section missing -------------------------------------------------
run_case "$work/with-changelog" "v0.0.0-missing" no
if [ "$case_exit" -eq 1 ] && ! created_release && has_message "has no section"; then
  pass "B. a tag without a changelog section fails and creates nothing"
else
  fail "B. expected exit 1 and no release (exit=$case_exit, created=$(created_release && echo yes || echo no))"
fi

# --- case C: CHANGELOG missing ----------------------------------------------
run_case "$work/without-changelog" "$version" no
if [ "$case_exit" -eq 1 ] && ! created_release && has_message "not found"; then
  pass "C. a missing CHANGELOG.md fails and creates nothing"
else
  fail "C. expected exit 1 and no release (exit=$case_exit, created=$(created_release && echo yes || echo no))"
fi

# --- case D: release already exists -----------------------------------------
run_case "$work/with-changelog" "$version" yes
if [ "$case_exit" -eq 0 ] && ! created_release; then
  pass "D. an existing release is left alone"
else
  fail "D. expected exit 0 and no new release (exit=$case_exit, created=$(created_release && echo yes || echo no))"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "All release workflow cases passed."
  exit 0
fi

echo "$failures release workflow case(s) failed."
exit 1
