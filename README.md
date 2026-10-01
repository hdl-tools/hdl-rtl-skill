# hdl-rtl-skill

HDL RTL skill to reduce AI hallucinations and improve code quality.

An AI skill ecosystem for Verilog/SystemVerilog RTL — generation, review, signoff and
debug. It is **not** a syntax tutorial. Every part of it exists to cut one of:
hallucinations, functional bugs, review escapes, CDC issues, reset issues, FSM errors,
width mismatches, signedness bugs, arithmetic overflow, protocol violations, lint
violations, sim/synthesis mismatch, and post-silicon escapes.

For ASIC and FPGA RTL engineers.

---

## The one result that explains the whole design

A realistic from-memory asynchronous FIFO was written and linted:

```
$ bin/rtl-lint fifo_async_bad.sv
RTL-LINT: clean. 0 findings from slang (full elaboration, -Weverything).
RTL-LINT-SUMMARY BLOCKER=0 HIGH=0 MEDIUM=0 LOW=0 INFO=0 TOOL=slang
```

**Zero findings.** That file has at least four serious bugs: binary pointers through
the CDC synchronisers, pointers one bit too narrow to tell full from empty, `full`
computed in the wrong clock domain, and an exported occupancy that no domain can
actually know. Any of them is a silicon respin.

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

Symlinks the five skills into `~/.claude/skills/`, checks which tools are present, runs
the self-test, then **prints** the hook registration for your `settings.json`. It does
not edit your settings for you.

The skills work immediately but are advisory — the model may choose not to invoke them.
The hook is what makes review unskippable. Install it.

---

## What is here

| | |
|---|---|
| `skills/rtl-style-guide/` | Naming, `always_ff`/`always_comb`, types, FSM shape, parameters, forbidden patterns. Loaded implicitly for any RTL write. |
| `skills/rtl-review-signoff/` | 20 review categories, severity rubric, 11-question self-critique, signoff rules. |
| `skills/rtl-golden-templates/` | 11 reference implementations, every one proven to elaborate clean. |
| `skills/rtl-anti-patterns/` | 53 catalogued bug patterns with root cause, symptoms, detection, fix. |
| `skills/rtl-workflow/` | Trigger rules, the four workflows, bounded retry, context injection, escalation. |
| `hooks/rtl_gate.sh` | **The mandatory gate.** The only unskippable component. |
| `hooks/slang-warnings.txt` | Generated diagnostic catalogue. Not hand-written. |
| `bin/rtl-lint` | Tool discovery + severity normalisation. Degrades honestly. |
| `bin/rtl-cdc` | Opt-in deep CDC. Says `NOT_AVAILABLE` rather than faking a report. |
| `tests/run_tests.sh` | Proves the templates compile and the detection works. |
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

## Verify it yourself

```bash
tests/run_tests.sh                              # 19 checks: 11 templates + 8 detections
bin/rtl-lint tests/bad/ap_width_trunc.sv        # HIGH, with the real slang message
hooks/rtl_gate.sh tests/bad/ap_inferred_latch.sv; echo $?   # exit 2
```

The third one is the interesting test. Run it four times: it blocks three times, then
escalates to `MANUAL_REVIEW_REQUIRED` and stops blocking. It cannot loop forever.

## Tools

| Tool | Role | Required |
|---|---|---|
| `slang` | Width, signedness, latch, drivers. The deterministic gate. | Strongly recommended |
| `vcs` / `xrun` | Compile and simulate | Optional |
| VC SpyGlass | Deep lint and CDC signoff | Optional, needed for tape-out CDC |

With no tool at all, `bin/rtl-lint` exits 0, says `TOOL=none`, and every finding is
marked `UNVERIFIED`. The repo stays usable; it just stops being able to prove anything,
and says so.

### Two invocation facts that cost real debugging time

- **`-Wall` is not valid in slang.** The gcc habit is a trap. Use `-Weverything`.
- **`--lint-only` silently loses `-Winferred-latch` and multiple-driver errors.**
  Latch inference is the highest-value automated check here, so the gate runs full
  elaboration with `--ignore-unknown-modules`. Do not "optimise" that away — it looks
  faster and quietly removes the main benefit.

Both are recorded in `hooks/slang-warnings.txt`, which is generated by probing slang
rather than written from memory. That file is the method of this repo in miniature:
**verify, cite, and say so when you could not.**
