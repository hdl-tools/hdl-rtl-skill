#!/usr/bin/env bash
# rtl_gate.sh -- the mandatory RTL review gate.
#
# Registered as a Claude Code PostToolUse hook on Write|Edit. Skills are
# model-discretionary; a hook is not. This is the only component in the repo
# that makes review unskippable.
#
# What it does
#   1. Decides whether the edited file is RTL worth gating (see SKIP rules).
#   2. Runs bin/rtl-lint for deterministic evidence.
#   3. Maps counts to a decision using the same thresholds as
#      skills/rtl-review-signoff/references/severity-rubric.md.
#   4. On BLOCKER/HIGH, exits 2 so the model is told to fix and re-review.
#   5. Bounds that loop at MAX_REVIEW_LOOPS, then stops blocking and emits
#      MANUAL_REVIEW_REQUIRED, so it can never spin forever.
#
# Exit codes
#   0  pass, or advisory only, or loop budget spent (never blocks again)
#   2  blocking: stderr is fed back to the model as the review to act on
#
# NOTE ON THE HOOK INPUT SCHEMA
#   Claude Code passes hook context as JSON on stdin. This script does not
#   assume a specific field path: it extracts any plausible file path from the
#   payload and also accepts a path as $1. That keeps it working if the schema
#   differs from what this was written against -- verify against the current
#   hook documentation before relying on a specific field.

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
RTL_LINT="$REPO_ROOT/bin/rtl-lint"

MAX_REVIEW_LOOPS="${RTL_GATE_MAX_LOOPS:-3}"
STATE_DIR="${TMPDIR:-/tmp}/rtl_gate_state"

# ---------------------------------------------------------------------------
# 1. Work out which file was edited
# ---------------------------------------------------------------------------
# A path given as $1 short-circuits stdin entirely: cheaper, and it means a
# script or CI caller never touches the stdin path at all.
#
# When we DO read stdin it is bounded by `timeout`. A bare `cat` blocks forever
# if stdin is open but nobody writes or closes it -- which hung this script for
# the full timeout of a scripted run. This hook sits in the user's edit path, so
# it must be structurally incapable of hanging: a frozen editor is a worse
# outcome than a missed review.
FILE=""
PAYLOAD=""

if [ "$#" -ge 1 ] && [ -n "${1:-}" ]; then
  FILE="$1"
elif [ ! -t 0 ]; then
  if command -v timeout >/dev/null 2>&1; then
    PAYLOAD="$(timeout 2 cat 2>/dev/null || true)"
  else
    # No timeout binary: read one line with bash's own bounded read.
    IFS= read -r -t 2 PAYLOAD 2>/dev/null || PAYLOAD=""
  fi
fi

if [ -z "$FILE" ] && [ -n "$PAYLOAD" ]; then
  FILE="$(printf '%s' "$PAYLOAD" | python3 -c '
import json, re, sys
raw = sys.stdin.read()
cand = []
try:
    obj = json.loads(raw)
    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, str) and ("path" in k.lower() or "file" in k.lower()):
                    cand.append(v)
                else:
                    walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    walk(obj)
except Exception:
    pass
# Fall back to any RTL-looking path anywhere in the raw payload.
cand += re.findall(r"[\w./\-]+\.(?:sv|svh|v|vh)\b", raw)
for c in cand:
    if c.endswith((".sv", ".svh", ".v", ".vh")):
        print(c)
        break
' 2>/dev/null || true)"
fi

# Nothing to gate on -- stay silent. A hook that complains about non-RTL edits
# gets switched off, and then it protects nothing.
[ -n "$FILE" ] || exit 0
[ -f "$FILE" ] || exit 0

BASE="$(basename "$FILE")"

# ---------------------------------------------------------------------------
# 2. SKIP rules -- see "Where the review hook must NOT run" in
#    skills/rtl-workflow/SKILL.md. Keeping this list honest is what keeps the
#    gate switched on.
# ---------------------------------------------------------------------------
case "$BASE" in
  *.sv|*.svh|*.v|*.vh) ;;
  *) exit 0 ;;
esac

case "$BASE" in
  *_tb.sv|*_tb.v|tb_*.sv|tb_*.v|*_test.sv|*_test.v|*_tests.sv) exit 0 ;;
esac

if [ "${RTL_GATE_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Gather evidence
# ---------------------------------------------------------------------------
if [ ! -x "$RTL_LINT" ]; then
  echo "rtl_gate: $RTL_LINT missing or not executable; cannot gate $BASE" >&2
  exit 0
fi

REPORT="$("$RTL_LINT" "$FILE" 2>&1 || true)"
SUMMARY="$(printf '%s' "$REPORT" | grep '^RTL-LINT-SUMMARY' | tail -1)"

getc() { printf '%s' "$SUMMARY" | sed -n "s/.*$1=\([0-9]*\).*/\1/p"; }
BLOCKER="$(getc BLOCKER)"; BLOCKER="${BLOCKER:-0}"
HIGH="$(getc HIGH)";       HIGH="${HIGH:-0}"
MEDIUM="$(getc MEDIUM)";   MEDIUM="${MEDIUM:-0}"
LOW="$(getc LOW)";         LOW="${LOW:-0}"
INFO="$(getc INFO)";       INFO="${INFO:-0}"
TOOL="$(printf '%s' "$SUMMARY" | sed -n 's/.*TOOL=\([^ ]*\).*/\1/p')"
TOOL="${TOOL:-unknown}"

# MEDIUM pile-up escalation, matching severity-rubric.md.
EFFECTIVE_HIGH="$HIGH"
if [ "$MEDIUM" -ge 8 ]; then
  EFFECTIVE_HIGH=$((HIGH + 1))
fi

# ---------------------------------------------------------------------------
# 4. Loop accounting -- keyed per file, reset on a clean pass
# ---------------------------------------------------------------------------
mkdir -p "$STATE_DIR" 2>/dev/null || true
KEY="$(printf '%s' "$FILE" | cksum | tr -d ' ' | cut -c1-16)"
STATE_FILE="$STATE_DIR/$KEY"
LOOP=0
[ -r "$STATE_FILE" ] && LOOP="$(cat "$STATE_FILE" 2>/dev/null || echo 0)"
case "$LOOP" in ''|*[!0-9]*) LOOP=0 ;; esac

NEEDS_WORK=0
if [ "$BLOCKER" -ge 1 ] || [ "$EFFECTIVE_HIGH" -ge 1 ]; then
  NEEDS_WORK=1
fi

if [ "$NEEDS_WORK" -eq 0 ]; then
  rm -f "$STATE_FILE" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 5. Decide
# ---------------------------------------------------------------------------
if [ "$BLOCKER" -ge 1 ]; then
  DECISION="REJECTED"
elif [ "$EFFECTIVE_HIGH" -ge 3 ]; then
  DECISION="REJECTED"
elif [ "$EFFECTIVE_HIGH" -ge 1 ]; then
  DECISION="APPROVED_WITH_CHANGES"
else
  DECISION="REVIEW_REQUIRED"   # tool is clean; the 20 categories are not done yet
fi

# ---------------------------------------------------------------------------
# 6. Loop budget spent -> stop blocking, escalate to a human
# ---------------------------------------------------------------------------
if [ "$NEEDS_WORK" -eq 1 ] && [ "$LOOP" -ge "$MAX_REVIEW_LOOPS" ]; then
  rm -f "$STATE_FILE" 2>/dev/null || true
  cat >&2 <<EOF
=============================================================
RTL GATE: MANUAL_REVIEW_REQUIRED  --  $BASE
=============================================================
$MAX_REVIEW_LOOPS auto-fix rounds did not clear the findings. The gate is now
standing down for this file so it cannot loop forever.

Unresolved: BLOCKER=$BLOCKER HIGH=$HIGH MEDIUM=$MEDIUM (tool=$TOOL)

$REPORT

DO NOT present this file as approved. Report MANUAL_REVIEW_REQUIRED to the
user, state what is still unresolved, and say what would resolve it (a spec
clause, a missing file, or a tool run such as /rtl-cdc).
=============================================================
EOF
  exit 0
fi

# ---------------------------------------------------------------------------
# 7. Emit the review instruction
# ---------------------------------------------------------------------------
if [ "$NEEDS_WORK" -eq 1 ]; then
  echo $((LOOP + 1)) > "$STATE_FILE" 2>/dev/null || true

  cat >&2 <<EOF
=============================================================
RTL GATE: $DECISION  --  $BASE   (round $((LOOP + 1)) of $MAX_REVIEW_LOOPS)
=============================================================
DETERMINISTIC EVIDENCE (tool=$TOOL)

$REPORT

REQUIRED NOW
1. Fix every BLOCKER and HIGH above. Fix the design, not the warning --
   narrowing a signal to silence a truncation warning implements the bug.
2. Re-read the request and confirm your fix did not change what the module
   DOES. An auto-fix that alters intent is a worse outcome than the finding.
3. Re-run the FULL review, not a check of the lines you touched:
     - skills/rtl-review-signoff/SKILL.md          all 20 categories
     - references/self-critique.md                 all 11 questions
     - references/severity-rubric.md               classify and decide
4. Remember what the tool does NOT check. CDC, reset release, arithmetic
   overflow, protocol deadlock, arbitration fairness and blocking-assignment
   sim/synth mismatch are all invisible to it. Label those [reasoning]
   UNVERIFIED.

Do not report this file as approved until the gate passes.
=============================================================
EOF
  exit 2
fi

# Tool-clean: no blocking, but the reasoning-tier review still has to happen.
cat >&2 <<EOF
RTL GATE: tool-clean -- $BASE  (BLOCKER=0 HIGH=0 MEDIUM=$MEDIUM LOW=$LOW INFO=$INFO, tool=$TOOL)
A clean tool run is NOT a signoff. slang checks none of: CDC, reset release,
arithmetic overflow, FSM reachability, protocol deadlock, arbitration fairness,
blocking assignments in clocked blocks. Run the 20 categories and the 11
self-critique questions in skills/rtl-review-signoff/ before approving.
EOF
exit 0
