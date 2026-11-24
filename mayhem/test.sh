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

# Known-answer finite-element checks, run through the OpenSees interpreter that build.sh produced
# (build-mayhem/bin/OpenSees): each mayhem/tests/<name>.tcl prints "RESULT <value>", compared with
# the closed-form answer in mayhem/tests/expected.txt (relative tolerance 1e-4). Plus upstream's own
# tests/steel01_ddm_isotropic_check.tcl, which prints "All Steel01 DDM checks passed" on success.
OPS="$SRC/build-mayhem/bin/OpenSees"
[ -x "$OPS" ] || { echo "test.sh: $OPS missing - run mayhem/build.sh first" >&2; emit_ctrf opensees-known-answer 0 1; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
passed=0; failed=0
while read -r name want; do
  [ -n "$name" ] || continue
  got="$(cd "$work" && "$OPS" "$SRC/mayhem/tests/$name.tcl" 2>&1 | sed -n 's/^RESULT //p' | tail -1)"
  if [ -n "$got" ] && awk -v g="$got" -v w="$want" 'BEGIN{d=g-w; if(d<0)d=-d; s=w<0?-w:w; exit !(d<=1e-4*s)}'; then
    echo "PASS $name ($got)"; passed=$((passed+1))
  else
    echo "FAIL $name: got '$got', want $want"; failed=$((failed+1))
  fi
done < "$SRC/mayhem/tests/expected.txt"
if (cd "$work" && "$OPS" "$SRC/tests/steel01_ddm_isotropic_check.tcl" 2>&1) | grep -q "^All Steel01 DDM checks passed"; then
  echo "PASS steel01_ddm_isotropic_check"; passed=$((passed+1))
else
  echo "FAIL steel01_ddm_isotropic_check"; failed=$((failed+1))
fi
emit_ctrf opensees-known-answer "$passed" "$failed" 0
