#!/usr/bin/env bash
# discover-slang-warnings.sh -- re-derive which diagnostics slang actually emits.
#
# This is the script referenced by the header of hooks/slang-warnings.txt. It
# does NOT regenerate that file wholesale (the severity mapping and the prose
# notes are human judgement). It re-verifies the mechanical half: which
# optionName each probe in tests/bad/ really produces, so the catalogue can be
# checked against reality after a slang upgrade.
#
# Run it when:
#   - slang is upgraded
#   - a probe is added to tests/bad/
#   - a catalogue entry is doubted
#
# slang has NO --list-warnings option, and -Whelp is not valid. Probing is the
# only way to learn the real names -- which is the point: the catalogue is
# evidence, not recall.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v slang >/dev/null 2>&1; then
  echo "slang not on PATH; nothing can be verified." >&2
  exit 77
fi

echo "# slang version: $(slang --version 2>&1 | head -1)"
echo "# probed: $(date -u +%Y-%m-%d)"
echo
echo "# Flag validity (re-checked, because these are the ones people assume):"
probe="$(mktemp -t slangprobe-XXXXXX.sv)"
trap 'rm -f "$probe"' EXIT
printf 'module p; endmodule\n' > "$probe"
for g in all extra conversion pedantic everything; do
  if slang --lint-only "-W$g" "$probe" 2>&1 | grep -q 'unknown-warning-option'; then
    printf '#   -W%-12s INVALID\n' "$g"
  else
    printf '#   -W%-12s valid\n' "$g"
  fi
done

echo
echo "# Diagnostics actually produced by each probe in tests/bad/."
echo "# NOTE: full elaboration, NOT --lint-only. --lint-only loses"
echo "#       -Winferred-latch and multiple-driver errors."
for f in "$REPO_ROOT"/tests/bad/*.sv; do
  [ -e "$f" ] || continue
  declared="$(grep -oP '^// EXPECT:\s*\K\S+' "$f" | tr '\n' ' ')"
  actual="$(slang --ignore-unknown-modules -Weverything --error-limit 0 \
              --diag-option "$f" 2>&1 \
            | grep -oE '\[-W[a-z0-9-]+\]|error:' \
            | sed 's/\[-W//; s/\]//' | sort -u | tr '\n' ' ')"
  printf '%-30s declared: %-28s actual: %s\n' \
         "$(basename "$f")" "${declared:-(none)}" "${actual:-(none)}"
done

echo
echo "# Confirmed NOT detected (each verified silent):"
echo "#   arithmetic overflow, blocking assignment in always_ff, CDC of any"
echo "#   kind, reset release, FSM reachability, protocol deadlock,"
echo "#   arbitration starvation."
echo "# If a future slang gains any of these, move it out of the"
echo "# [reasoning] tier in the checklists and add a probe here."
