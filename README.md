# hdl-rtl-skill

An AI skill ecosystem for Verilog/SystemVerilog RTL — generation, review, signoff and
debug. It is **not** a syntax tutorial. Every part of it exists to cut one of:
hallucinations, functional bugs, review escapes, CDC issues, reset issues, FSM errors,
width mismatches, signedness bugs, arithmetic overflow, protocol violations, lint
violations, sim/synthesis mismatch, and post-silicon escapes.

For ASIC and FPGA RTL engineers.

---

## The result that explains the whole design

A realistic from-memory asynchronous FIFO was written and linted. The full trace is in
`docs/example-async-fifo.md`:

```
$ bin/rtl-lint fifo_async_bad.sv
RTL-LINT: clean. 0 findings from slang (full elaboration, -Weverything).
RTL-LINT-SUMMARY BLOCKER=0 HIGH=0 MEDIUM=0 LOW=0 INFO=0 TOOL=slang
```

**Zero findings.** That file has at least four serious bugs: binary pointers through the
CDC synchronisers, pointers one bit too narrow to tell full from empty, `full` computed
in the wrong clock domain, and an exported occupancy that no domain can actually know.
Any of them is a silicon respin.

So this repo is built on two honest halves:

1. **What a tool can prove** — width truncation, signedness, latch inference, multiple
   drivers, undriven signals. `slang` decides these, and findings quote it.
2. **What no tool here checks** — CDC, reset release, arithmetic overflow, FSM
   reachability, protocol deadlock, arbitration fairness, blocking assignments in
   clocked blocks. These are reasoning, labelled `UNVERIFIED`, and they are where the
   expensive bugs live.

Confusing the two is the hallucination. A clean tool run presented as a signoff is the
exact failure mode this repo exists to prevent — which is why the gate prints
*"A clean tool run is NOT a signoff"* and names what it did not check.

---

## Install

```bash
./install.sh
```

Symlinks the five skills into `~/.claude/skills/`, reports which tools are present, runs
the self-test, then **prints** the hook registration for your `settings.json`. It does
not edit your settings for you.

The skills work immediately but are advisory — the model may choose not to invoke them.
**The hook is what makes review unskippable.** Install it:

```json
"hooks": {
  "PostToolUse": [
    { "matcher": "Write|Edit",
      "hooks": [ { "type": "command", "command": "<repo>/hooks/rtl_gate.sh" } ] }
  ]
}
```

Temporarily disable with `RTL_GATE_DISABLE=1`. Loop budget via `RTL_GATE_MAX_LOOPS`
(default 3).

---

## What is here

| | |
|---|---|
| `skills/rtl-style-guide/` | Naming, `always_ff`/`always_comb`, types, FSM shape, parameters, forbidden patterns. Loaded implicitly for any RTL write. |
| `skills/rtl-review-signoff/` | 20 review categories across 5 checklists, severity rubric with explicit gate thresholds, 11-question self-critique. |
| `skills/rtl-golden-templates/` | 11 reference implementations, every one proven to elaborate with zero diagnostics. |
| `skills/rtl-anti-patterns/` | 53 catalogued bug patterns with root cause, symptoms, detection, auto-fix, severity. 9 have proving probes. |
| `skills/rtl-workflow/` | Trigger rules and confidence scoring, the five workflows, bounded retry, context injection, escalation. |
| `hooks/rtl_gate.sh` | **The mandatory gate.** The only unskippable component. |
| `hooks/slang-warnings.txt` | Generated diagnostic catalogue and severity map. Not hand-written. |
| `bin/rtl-lint` | Tool discovery, filelist context, severity normalisation. Degrades honestly. |
| `bin/rtl-cdc` | Opt-in deep CDC. Reports `NOT_AVAILABLE` rather than faking a report. |
| `commands/` | `/rtl-review`, `/rtl-lint`, `/rtl-cdc` slash commands. |
| `tests/run_tests.sh` | 21 checks: 11 templates must elaborate clean, 9 anti-patterns must be detected, no template may carry an unguarded `initial`. |
| `tests/discover-slang-warnings.sh` | Re-derives the diagnostic catalogue by probing slang. |
| `docs/` | Architecture, workflows, hallucination prevention, full worked example. |

## Flow

```
request -> style guide + template + anti-patterns -> generate
        -> [GATE] slang evidence -> 20 categories -> self-critique
        -> severity gate -> auto-fix -> re-review (max 3) -> signoff
                                                  |
                                      3 rounds -> MANUAL_REVIEW_REQUIRED
```

`MANUAL_REVIEW_REQUIRED` is a success. Presenting RTL with unresolved CDC concerns as
approved is the failure.

### Gate thresholds

| | Gate |
|---|---|
| **BLOCKER** >= 1 | `REJECTED` |
| **HIGH** 1-2 | `APPROVED_WITH_CHANGES` |
| **HIGH** >= 3 | `REJECTED` |
| **MEDIUM** >= 8 | counts as one additional HIGH |
| CDC / reset confidence < 0.70 | `MANUAL_REVIEW_REQUIRED` — checked *before* the counts |
| `TOOL=none` | outcome capped at `APPROVED_WITH_CHANGES` |

---

## Filelist context — read this before using it on real RTL

A file is the unit of *editing*; it is not the unit of *compilation*. In a hierarchical
codebase, parameters and macros routinely live in a separate file that the project
filelist pulls in first. Lint one file alone and you get a flood of
`use of undeclared identifier` errors, none of them real.

So `bin/rtl-lint` discovers the project filelist — `<block>/etc/rtl.f`, or `rtl.f`
beside the source, or a lone `*.f` in a sibling `etc/` — compiles the block as a single
unit for **context**, then **scopes findings back to the file you asked about** so
editing one file does not report nine others' warnings.

```bash
bin/rtl-lint rtl/my_block.sv            # auto-discovers the filelist
bin/rtl-lint -F etc/rtl.f rtl/x.sv      # explicit
RTL_LINT_NO_FILELIST=1 bin/rtl-lint …   # single-file only
```

**Stubbed library cells.** Every real block instantiates cells that live in a technology
library, not the filelist. `--ignore-unknown-modules` stubs them, a stub drives nothing,
so its outputs read as undriven and that propagates to the enclosing module's ports.
`rtl-lint` identifies what was stubbed, demotes those findings to LOW, and names the
responsible cell — rather than reporting a functional gap that does not exist.

---

## Verify it yourself

```bash
tests/run_tests.sh                                          # 21 checks
bin/rtl-lint tests/bad/ap_width_trunc.sv                    # HIGH, real slang message
hooks/rtl_gate.sh tests/bad/ap_inferred_latch.sv; echo $?    # exit 2
```

Run the third one four times: it blocks three times, then escalates to
`MANUAL_REVIEW_REQUIRED` and stops blocking. It cannot loop forever.

The gate is also structurally unable to hang — a path argument short-circuits stdin, and
any stdin read is bounded. It runs on every file write in your editor, so a frozen
editor would be a worse outcome than a missed review.

---

## Tools

| Tool | Role | Required |
|---|---|---|
| `slang` | Width, signedness, latch, drivers. The deterministic gate. | Strongly recommended |
| `vcs` / `xrun` | Compile and simulate | Optional |
| A CDC tool (`SPYGLASS_HOME`) | Deep lint and CDC signoff | Optional, needed for tape-out CDC |

With no tool at all, `bin/rtl-lint` exits 0, reports `TOOL=none`, and marks every finding
`UNVERIFIED`. The repo stays usable; it just stops being able to prove anything, and says
so.

### Two invocation facts that cost real debugging time

- **`-Wall` is not valid in slang.** The gcc habit is a trap. Use `-Weverything`.
- **`--lint-only` silently loses `-Winferred-latch` and multiple-driver errors.** Latch
  inference is the highest-value automated check here, so the gate runs full elaboration
  with `--ignore-unknown-modules`. Do not "optimise" that away — it looks faster and
  quietly removes the main benefit.

Both are recorded in `hooks/slang-warnings.txt`, which is generated by probing slang
rather than written from memory. That file is the method of this repo in miniature:
**verify, cite, and say so when you could not.**

---

## Honest limits

- **Reasoning-tier findings are not proof.** CDC, reset release, arithmetic overflow, FSM
  liveness, protocol deadlock and arbitration fairness are checked by reasoning only.
  `severity-rubric.md` therefore refuses tape-out signoff on a reasoning-only CDC
  conclusion, however confident it reads.
- **9 of 53 anti-patterns have proving probes.** The other 44 are review-only by design
  and labelled so. A green test suite verifies the mechanical ninth, not the catalogue.
- **Severity thresholds are calibrated, not proven.** They have been tuned against real
  hierarchical RTL, but a block of a different shape — memory interfaces, mixed-signal
  boundaries, vendor IP wrappers — may need retuning. If the gate starts producing noise,
  fix the severity map; do not loosen the BLOCKER/HIGH thresholds.
- **The gate can be switched off.** `RTL_GATE_DISABLE=1` exists because a gate that
  cannot be switched off gets uninstalled instead. Keeping it quiet on testbenches,
  non-RTL files and comment-only diffs is what keeps it switched on.

## Licence

MIT. See `LICENSE`.
