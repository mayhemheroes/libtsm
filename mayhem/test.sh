#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Run the upstream libcheck suite built by build.sh (7 binaries: htable, screen, selection,
# symbol, valgrind, vte_mouse, vte). Behavioral: each binary must PRINT its libcheck summary
# ("...%: Checks: N, Failures: F, Errors: E") — counts are summed from those asserted results,
# so a neutered exit(0) binary (no summary) fails the oracle.
TESTS_DIR="$SRC/build-tests/test"
[ -d "$TESTS_DIR" ] || { echo "build-tests missing — mayhem/build.sh did not build the suite" >&2; emit_ctrf check 0 1; exit $?; }
passed=0; failed=0
for t in test_htable test_screen test_selection test_symbol test_valgrind test_vte_mouse test_vte; do
  bin="$TESTS_DIR/$t"
  [ -x "$bin" ] || { echo "missing test binary: $t (build.sh bug)" >&2; failed=$((failed+1)); continue; }
  out=$("$bin" 2>&1); rc=$?
  echo "== $t =="; echo "$out"
  line=$(echo "$out" | grep -Eo 'Checks: *[0-9]+, *Failures: *[0-9]+, *Errors: *[0-9]+' | tail -1)
  if [ -z "$line" ]; then
    echo "$t: no libcheck summary printed — treating as FAILED" >&2
    failed=$((failed+1)); continue
  fi
  n=$(echo "$line"  | sed -E 's/Checks: *([0-9]+).*/\1/')
  f=$(echo "$line"  | sed -E 's/.*Failures: *([0-9]+).*/\1/')
  e=$(echo "$line"  | sed -E 's/.*Errors: *([0-9]+).*/\1/')
  bad=$(( f + e )); [ "$rc" -ne 0 ] && [ "$bad" -eq 0 ] && bad=1
  passed=$(( passed + n - bad )); failed=$(( failed + bad ))
done
emit_ctrf check "$passed" "$failed" 0
