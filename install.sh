#!/usr/bin/env bash
# install.sh -- make the skills discoverable, then print the hook registration.
#
# Idempotent: safe to run repeatedly. Symlinks (not copies) so a git pull
# updates the installed skills with no reinstall.
#
# Two halves, and the second one is the one that matters:
#   SKILLS  -- useful immediately, but model-discretionary.
#   HOOK    -- makes review unskippable. Printed, never written: this script
#              will not edit your settings.json behind your back.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${CLAUDE_SKILL_DIR:-$HOME/.claude/skills}"

echo "hdl-rtl-skill installer"
echo "  repo:   $REPO_ROOT"
echo "  skills: $SKILL_DIR"
echo

mkdir -p "$SKILL_DIR" || { echo "cannot create $SKILL_DIR" >&2; exit 1; }

for d in "$REPO_ROOT"/skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  target="$SKILL_DIR/$name"
  if [ -L "$target" ]; then
    if [ "$(readlink "$target")" = "${d%/}" ]; then
      echo "  ok        $name (already linked)"
    else
      ln -sfn "${d%/}" "$target" && echo "  relinked  $name"
    fi
  elif [ -e "$target" ]; then
    echo "  SKIP      $name -- $target exists and is not a symlink." >&2
    echo "            Move it aside first; refusing to clobber real files." >&2
  else
    ln -s "${d%/}" "$target" && echo "  linked    $name"
  fi
done

chmod +x "$REPO_ROOT"/bin/rtl-lint "$REPO_ROOT"/bin/rtl-cdc \
         "$REPO_ROOT"/hooks/rtl_gate.sh "$REPO_ROOT"/tests/run_tests.sh 2>/dev/null || true

echo
echo "--- tool check -------------------------------------------------------"
if command -v slang >/dev/null 2>&1; then
  echo "  slang     $(slang --version 2>&1 | head -1)"
  echo "            Deterministic width / latch / driver / signedness checks: ON"
else
  echo "  slang     NOT FOUND"
  echo "            Findings will be UNVERIFIED. The single highest-value"
  echo "            thing you can do for this repo is install slang."
fi
for t in vcs xrun; do
  command -v "$t" >/dev/null 2>&1 && echo "  $t        $(command -v $t)"
done
command -v sg_shell >/dev/null 2>&1 || command -v spyglass >/dev/null 2>&1 \
  || echo "  cdc tool  NOT FOUND -- CDC findings stay [reasoning] UNVERIFIED"

echo
echo "--- self test --------------------------------------------------------"
if "$REPO_ROOT"/tests/run_tests.sh >/dev/null 2>&1; then
  echo "  PASS      all golden templates elaborate clean; all anti-patterns detected"
else
  rc=$?
  if [ "$rc" -eq 77 ]; then
    echo "  SKIP      slang absent, nothing was verified"
  else
    echo "  FAIL      run tests/run_tests.sh to see what broke" >&2
  fi
fi

echo
echo "--- MANDATORY GATE (not installed automatically) ---------------------"
echo
echo "The skills above are advisory: the model may choose not to invoke them."
echo "To make RTL review unskippable, merge this into your settings.json"
echo "(~/.claude/settings.json for all projects, or .claude/settings.json for"
echo "this project only):"
echo
cat <<EOF
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "$REPO_ROOT/hooks/rtl_gate.sh" }
        ]
      }
    ]
  }
EOF
echo
echo "Verify the matcher syntax against the current Claude Code hooks docs;"
echo "hook schemas change. Try it first with:"
echo "  $REPO_ROOT/hooks/rtl_gate.sh $REPO_ROOT/tests/bad/ap_inferred_latch.sv"
echo "which should exit 2 and print a HIGH latch finding."
echo
echo "To disable temporarily: RTL_GATE_DISABLE=1"
