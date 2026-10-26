#!/usr/bin/env bash
#
# mayhem/test.sh — RUN upstream's golden-file suite (tests/*.savo vs tests/*.expected) through the
# `./savo` interpreter that mayhem/build.sh built, plus direct known-answer probes. Asserts output.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

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

if [ ! -x ./savo ]; then
  echo "mayhem/test.sh: ./savo missing — mayhem/build.sh should have built it" >&2
  emit_ctrf "savo-golden" 0 1
  exit 1
fi

pass=0; fail=0

# Known-answer probes: fixed program -> exact expected stdout.
probe() {
  local name="$1" code="$2" want="$3" got
  got=$(./savo -e "$code" 2>/dev/null)
  if [ "$got" = "$want" ]; then pass=$((pass + 1)); echo "PASS  probe:$name"
  else fail=$((fail + 1)); echo "FAIL  probe:$name (want '$want', got '$got')"; fi
}
probe multiply 'savomoltiplication 6 7' '42.00'
probe concat   'savoprint "ab" + "cd"' 'abcd'
probe upper    'savoprint savoupper("savo")' 'SAVO'
probe factorial 'savovar @n = 5
savovar @f = 1
savowhile (@n > 1)
savovar @f = @f * @n
savovar @n = @n - 1
savoend
savoprint @f' '120.00'

# Upstream golden-file suite (tests/run.sh), one case per tests/*.savo.
out=$(sh tests/run.sh 2>&1); echo "$out"
sp=$(printf '%s\n' "$out" | sed -n 's/^\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed$/\1/p' | tail -1)
sf=$(printf '%s\n' "$out" | sed -n 's/^\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed$/\2/p' | tail -1)
if [ -z "$sp" ] || [ -z "$sf" ] || [ "$sp" -eq 0 ]; then
  echo "mayhem/test.sh: golden suite produced no summary" >&2
  fail=$((fail + 1))
else
  pass=$((pass + sp)); fail=$((fail + sf))
fi

emit_ctrf "savo-golden" "$pass" "$fail"
