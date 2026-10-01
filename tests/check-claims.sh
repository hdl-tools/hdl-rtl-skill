#!/usr/bin/env bash
# check-claims.sh -- verify README's counted claims still match the files on disk.
#
# The numbers are extracted from the README prose, not hardcoded here -- so this
# script has no number of its own to drift out of sync. It fails when a template or
# anti-pattern entry is added/removed without updating the doc that advertises it.
#
# Needs no slang. tests/run_tests.sh checks the "21 checks" claim separately, since
# that one requires actually running the suite.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail=0

check() {   # label claimed actual
  local label="$1" claimed="$2" actual="$3"
  if [ -z "$claimed" ]; then
    printf '  FAIL  %-14s could not find a claimed count in README.md\n' "$label"
    fail=$((fail+1))
  elif [ "$claimed" = "$actual" ]; then
    printf '  PASS  %-14s claimed %-3s actual %s\n' "$label" "$claimed" "$actual"
  else
    printf '  FAIL  %-14s claimed %-3s actual %s\n' "$label" "$claimed" "$actual"
    fail=$((fail+1))
  fi
}

claimed_templates="$(grep -oP '^\| `skills/rtl-golden-templates/` \| \K[0-9]+' README.md)"
actual_templates="$(ls skills/rtl-golden-templates/templates/*.sv skills/rtl-golden-templates/templates/*.v 2>/dev/null | wc -l)"
check "templates" "$claimed_templates" "$actual_templates"

claimed_antipatterns="$(grep -oP '^\| `skills/rtl-anti-patterns/` \| \K[0-9]+' README.md)"
actual_antipatterns="$(grep -rhoE 'AP-[A-Z]+-[0-9]+' skills/rtl-anti-patterns/patterns/*.md | sort -u | wc -l)"
check "anti-patterns" "$claimed_antipatterns" "$actual_antipatterns"

claimed_probes="$(grep -oP '^\| `skills/rtl-anti-patterns/` \|.*\K[0-9]+(?= have proving probes)' README.md)"
actual_probes="$(ls tests/bad/*.sv 2>/dev/null | wc -l)"
check "probes" "$claimed_probes" "$actual_probes"

echo
printf '%d claim(s) failed\n' "$fail"
[ "$fail" -eq 0 ]
