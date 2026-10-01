# Architecture

Five skills, one hook, two scripts. The split follows one principle: **separate the
thing that generates from the thing that judges, and make the judge unskippable.**

```
                         user request
                              |
                   +----------v-----------+
                   |   rtl-workflow       |  trigger scoring, routing
                   +----------+-----------+
                              |
         GENERATION-TIME      |      (pass 1: designer)
    +-------------------------+--------------------------+
    |                         |                          |
+---v-------------+  +--------v-----------+  +-----------v------+
| rtl-style-guide |  | rtl-golden-        |  | rtl-anti-        |
|                 |  | templates          |  | patterns         |
| how to write it |  | what to start from |  | what not to do   |
+---+-------------+  +--------+-----------+  +-----------+------+
    |                         |                          |
    +-------------------------v--------------------------+
                              |
                        RTL produced
                              |
                     Write / Edit *.sv
                              |
    =========================================================
    ||            hooks/rtl_gate.sh  (MANDATORY)           ||
    =========================================================
                              |
                   +----------v-----------+
                   |    bin/rtl-lint      |  slang, full elaboration
                   |  deterministic only  |  -> severity via
                   +----------+-----------+     hooks/slang-warnings.txt
                              |
         GATE-TIME            |      (pass 2: reviewer)
    +-------------------------v--------------------------+
    |              rtl-review-signoff                   |
    |  20 categories -> self-critique -> severity rubric |
    +-------------------------+--------------------------+
                              |
                  +-----------v------------+
                  |    severity gate       |
                  +-----------+------------+
                              |
        APPROVED <------------+------------> REJECTED
                              |                  |
                              |         (pass 3: corrector)
                              |                  |
                              +--- auto-fix -----+
                                      |
                              re-review, max 3
                                      |
                        MANUAL_REVIEW_REQUIRED
```

## Why each piece exists

**`rtl-workflow`** — Routing. Without it every task loads everything, context fills with
irrelevant checklists, and the important file gets crowded out. It also owns the
*negative* rules: where the gate must **not** fire. A gate that fires on testbenches
and comment-only diffs gets switched off, and then it protects nothing.

**`rtl-style-guide`** — Runs implicitly, before a line is written. Style is not taste
here: every rule names the bug class it prevents. `` `default_nettype none `` is one
line that turns a typo from an invisible wrong-by-one-bit net into a compile error.
Because it is injected at generation time, it shapes the output rather than being
checked afterwards.

**`rtl-golden-templates`** — Eleven implementations proven to elaborate with zero
diagnostics. The point is not convenience, it is hallucination avoidance: writing an
async FIFO from recall is how gray-coded pointers become binary ones. Adapting a
verified file is a smaller and more reviewable change than generating a new one.
`tests/run_tests.sh` fails if any template stops compiling, so the guarantee is
maintained rather than asserted.

**`rtl-anti-patterns`** — The inverse index: symptom → bug. Its most important column
is **Detectable**, which says whether a tool proves it or only review can catch it. 9
of 53 entries are mechanically proven; the other 44 say so plainly. That column is what
stops a clean lint being mistaken for a clean design.

**`rtl-review-signoff`** — The judge. Nine reviewer personas, 20 categories, a severity
rubric with explicit thresholds, and the 11-question self-critique. It reviews
generated code *harder* than human code, because generated code has no waveform and no
bring-up history behind it, and the generator is biased toward believing its own first
answer.

**`hooks/rtl_gate.sh`** — The only mandatory component, and the reason the rest is more
than a style document. Skills are model-discretionary; a `PostToolUse` hook is not. It
runs the tool, maps severities, emits the review instruction, and exits 2 so the model
must act. It bounds the loop at 3 and then escalates, so it can never spin.

**`bin/rtl-lint`** — One place where tool discovery and severity normalisation live, so
the hook and the slash commands cannot disagree. It reads its severity map from
`hooks/slang-warnings.txt` rather than embedding one, so there is a single source of
truth. With no tool present it exits 0, reports `TOOL=none`, and marks everything
`UNVERIFIED`.

## Deliberate structural choices

**Checklists live inside `rtl-review-signoff/references/`, not as a separate skill.** A
checklist-only skill would never be invoked on its own — the reviewer always needs it.
Progressive disclosure inside one skill avoids a two-hop load on the hottest path.

**The workflow engine is split.** Its human-readable half is a skill; its enforcing half
is the hook. The enforcing half cannot be a skill, because a skill can be skipped.

**The diagnostic catalogue is generated, not written.** `hooks/slang-warnings.txt` was
produced by probing slang with files that trigger each diagnostic, then reading the
option names out of its output. Writing that file from memory would have been the exact
hallucination this repo is built to prevent — and the probe immediately disproved two
plausible assumptions (`-Wall` being valid; `--lint-only` being sufficient).

**Severity thresholds are shared, not duplicated.** `severity-rubric.md` is the
specification; `rtl_gate.sh` implements the same numbers. Both are stated so a drift
between them is visible.

## Degradation

| Missing | Consequence |
|---|---|
| The hook | Skills still work; review becomes advisory. Stated in `install.sh` output. |
| `slang` | `TOOL=none`, everything `UNVERIFIED`, outcome capped at `APPROVED_WITH_CHANGES`. |
| CDC tool | CDC stays `[reasoning]`; `bin/rtl-cdc` reports `NOT_AVAILABLE` and still gives the structural review method. |
| Submodules | `--ignore-unknown-modules` keeps single-file checks working; confidence capped. |

Nothing fails silently. Every degraded mode announces itself, because a quiet
degradation that still prints a clean report is worse than an error.
