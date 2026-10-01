#!/usr/bin/env bash
# run_tests.sh -- the one check that proves this repo is not fiction.
#
#   1. POSITIVE: every golden template must elaborate with ZERO slang
#      diagnostics. A template that does not compile is worse than no template,
#      because the model will copy it confidently.
#   2. NEGATIVE: every tests/bad/*.sv must produce the diagnostics named in its
#      own "// EXPECT:" headers. This proves the anti-pattern detection claims
#      are real and that the severity map in hooks/slang-warnings.txt is wired
#      to something.
#   3. GUARD: no golden template may carry an unguarded `initial` block. The
#      repo took two positions on this (see issue #2); this check is what
#      keeps it from drifting back.
#
# Exit 0 only if all three checks pass.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES="$REPO_ROOT/skills/rtl-golden-templates/templates"
BAD="$REPO_ROOT/tests/bad"

if ! command -v slang >/dev/null 2>&1; then
  echo "SKIP: slang not on PATH. These tests need it; nothing was verified."
  echo "      Everything this repo claims about width/latch/driver detection"
  echo "      is UNVERIFIED on this machine."
  exit 77
fi

pass=0; fail=0

run_slang() {   # file -> diagnostics on stdout
  slang --ignore-unknown-modules -Weverything --error-limit 0 \
        --diag-option "$1" 2>&1 | grep -E 'warning:|error:' || true
}

echo "=============================================================="
echo " 1. GOLDEN TEMPLATES -- must be completely clean"
echo "=============================================================="
for f in "$TEMPLATES"/*.sv "$TEMPLATES"/*.v; do
  [ -e "$f" ] || continue
  out="$(run_slang "$f")"
  if [ -z "$out" ]; then
    printf '  PASS  %s\n' "$(basename "$f")"
    pass=$((pass+1))
  else
    printf '  FAIL  %s\n' "$(basename "$f")"
    printf '%s\n' "$out" | sed 's/^/          /'
    fail=$((fail+1))
  fi
done

echo
echo "=============================================================="
echo " 2. ANTI-PATTERNS -- each must trigger its declared EXPECT"
echo "=============================================================="
for f in "$BAD"/*.sv; do
  [ -e "$f" ] || continue
  expects="$(grep -oP '^// EXPECT:\s*\K\S+' "$f" || true)"
  if [ -z "$expects" ]; then
    printf '  FAIL  %s -- no "// EXPECT:" header, so it proves nothing\n' \
           "$(basename "$f")"
    fail=$((fail+1))
    continue
  fi
  out="$(run_slang "$f")"
  missing=""
  for e in $expects; do
    if [ "$e" = "error" ]; then
      printf '%s' "$out" | grep -q 'error:' || missing="$missing $e"
    else
      printf '%s' "$out" | grep -q -- "-W$e" || missing="$missing $e"
    fi
  done
  if [ -z "$missing" ]; then
    printf '  PASS  %-28s detected:%s\n' "$(basename "$f")" \
           " $(printf '%s' "$expects" | tr '\n' ' ')"
    pass=$((pass+1))
  else
    printf '  FAIL  %-28s NOT detected:%s\n' "$(basename "$f")" "$missing"
    printf '%s\n' "$out" | sed 's/^/          got: /'
    fail=$((fail+1))
  fi
done

echo
echo "=============================================================="
echo " 3. TEMPLATE initial BLOCKS -- must be synthesis-guarded"
echo "=============================================================="
unguarded=""
for f in "$TEMPLATES"/*.sv "$TEMPLATES"/*.v; do
  [ -e "$f" ] || continue
  if awk '
    /synthesis[ \t]+translate_off/ { off=1; next }
    /synthesis[ \t]+translate_on/  { off=0; next }
    /^[ \t]*initial[^A-Za-z0-9_]/ && !off { bad=1 }
    END { exit !bad }
  ' "$f"; then
    unguarded="$unguarded $(basename "$f")"
  fi
done
if [ -z "$unguarded" ]; then
  printf '  PASS  no unguarded initial block in any template\n'
  pass=$((pass+1))
else
  printf '  FAIL  unguarded initial block in:%s\n' "$unguarded"
  fail=$((fail+1))
fi

echo
echo "=============================================================="
printf ' %d passed, %d failed\n' "$pass" "$fail"
echo "=============================================================="
[ "$fail" -eq 0 ]
