# Hallucination prevention

## The empirical result this document is built on

A realistic from-memory asynchronous FIFO was generated and linted. Real output:

```
$ bin/rtl-lint fifo_async_bad.sv
RTL-LINT: clean. 0 findings from slang (full elaboration, -Weverything).
RTL-LINT-SUMMARY BLOCKER=0 HIGH=0 MEDIUM=0 LOW=0 INFO=0 TOOL=slang
```

That file contains, at minimum:

1. **Binary pointers through the CDC synchronisers** (AP-CDC-06, BLOCKER) — multiple
   bits change per increment, so the destination can sample a pointer value that never
   existed.
2. **Pointers `ADDR_W` wide instead of `ADDR_W+1`** (AP-FIFO-01, BLOCKER) — full and
   empty are indistinguishable.
3. **`full` computed in the read domain** (AP-FIFO-05, HIGH) — the flag is optimistic
   instead of conservative, so it overflows.
4. **An exported occupancy** (`level_o`) — no domain in an async FIFO can know this.

**Zero findings.** The tool is not lying; it simply does not model clock domains. This
is the whole problem in one data point: *a tool-clean report is not evidence of a
correct design, and treating it as such is the highest-cost hallucination available.*

Everything below is a response to that.

---

## Why an AI hallucinates in RTL specifically

| Mechanism | What it produces |
|---|---|
| **Plausibility optimisation.** Generation rewards code that looks like correct RTL. A binary pointer through a synchroniser looks exactly like a gray one. | Structurally wrong CDC that reads perfectly. |
| **Answer commitment.** Having produced an answer, the model defends it. Asked "is this right?" it finds reasons it is. | Self-review that confirms rather than tests. |
| **Absent feedback.** No waveform, no bring-up, no customer return. Nothing contradicts a confident claim. | Confidence uncalibrated to correctness. |
| **Tool-coverage conflation.** A clean lint feels like a clean design. | `APPROVED` on the FIFO above. |
| **Recall blending.** Training data mixes Verilog-2001, SystemVerilog, VHDL and vendor dialects. | `-Wall` passed to slang; `logic` in a `.v` file. |
| **Specification drift.** Unstated requirements get filled in with the common case. | A counter that wraps when the spec needed saturate. |

Note that four of the six are *not* knowledge problems. The model knows gray coding is
required for CDC. It wrote binary pointers anyway. **More knowledge does not fix this;
structure does.**

---

## Technique 1 — Tier every claim by its evidence

Every finding carries where it came from:

- **`[slang]`** — proven. Quote the message and the option name.
- **`[spyglass]` / `[vcs]`** — proven by an opt-in deep run.
- **`[reasoning]`** — analysis, labelled **UNVERIFIED**.

This is the single highest-value mechanism in the repo, because it makes the FIFO
result above *expressible*. The review says: slang clean, and four UNVERIFIED BLOCKERs.
Without tiering, "slang clean" and "I checked the CDC" occupy the same confidence slot
in the output, and the reader cannot tell which is which.

`hooks/slang-warnings.txt` records, from actual probing, exactly what slang does **not**
detect — overflow, blocking assignments, CDC, reset release, FSM reachability, protocol
deadlock, arbitration fairness. That list is what turns "the tool was clean" from a
conclusion into a scope statement.

## Technique 2 — Generate the catalogue, never recall it

`hooks/slang-warnings.txt` was produced by writing probe files that trigger each
diagnostic and reading the option names back out of slang's own output. The probes are
`tests/bad/`, so the catalogue is continuously re-verifiable.

Two plausible beliefs died immediately:

- **`-Wall` is invalid in slang.** Universal from gcc. Simply rejected.
- **`--lint-only` does not report `-Winferred-latch`.** It is the obvious flag for a
  lint gate, and it silently removes latch detection — the highest-value automated check
  in the set.

Both would have been written into the hook from memory with complete confidence. Both
were wrong. That is the argument for the technique.

## Technique 3 — Verify before approval, mechanically

The gate runs `bin/rtl-lint` and puts its output in front of the reviewer *before* the
code is read. Anchoring on tool output rather than on a first impression removes the
step where a plausible read becomes the baseline that evidence then has to overcome.

## Technique 4 — Force the self-critique as a separate pass

`references/self-critique.md` asks 11 fixed questions. Each **NO** must name its
evidence; "I don't think so" counts as a YES not yet investigated. Each **YES** owes
Risk / Impact / Severity / Mitigation.

This attacks answer commitment directly. "Is my FIFO correct?" invites defence. "Can
this create CDC issues? — enumerate every clock, name each crossing's mechanism" is a
procedure whose output does not depend on how the author feels about their design.

The expected result on real RTL is two to four YES answers. **All NO on a first pass
means the pass was not done.**

## Technique 5 — Confidence thresholds that escalate

Below 0.70 confidence on CDC, reset, or specification interpretation, the outcome is
`MANUAL_REVIEW_REQUIRED` — regardless of how few findings there are. Few findings in
code you could not analyse is not a good review; it is an absent one.

Critically, the confidence check runs **before** the finding-count check, so a clean
count cannot override an unanalysable design.

## Technique 6 — Bounded, regression-checked retry

Three rounds, with guards against no-progress, regression, and intent drift. The last
matters most: the tempting fix for a truncation warning is to narrow the signal, which
*implements the truncation*. The warning disappears and the bug is now permanent. Every
fix round re-states the intent and confirms it still holds.

## Technique 7 — Make the honest outcome a first-class result

`MANUAL_REVIEW_REQUIRED` is defined as a **success**. Without that, the only way to
finish is to approve, and the pressure to approve is what produces the confident wrong
answer. An escape hatch that is explicitly respectable is what makes refusing to guess
possible.

---

## Two-pass and three-pass

### Two-pass: Designer → Reviewer

```
Pass 1  DESIGNER   style guide + template + anti-patterns -> RTL
Pass 2  REVIEWER   tool evidence -> 20 categories -> self-critique -> decision
```

The gain is not a second look; it is a **different objective function**. Pass 1 asks
"what implements this?". Pass 2 asks "what inputs make this wrong?". Running them
together gets plausible code judged by the faculty that found it plausible.

The pass boundary is enforced by the hook, not by intention. That matters: an intended
boundary gets skipped under time pressure, and skipping it looks identical to passing.

### Three-pass: Designer → Reviewer → Corrector

```
Pass 3  CORRECTOR  fix the findings, preserve intent, hand back for FULL re-review
```

Pass 3 is separated because the corrector has its own failure mode: fixing the
*symptom*. Narrowing a signal to silence `-Wwidth-trunc`. Adding a third flop to a
multi-bit synchroniser that needs a FIFO. Removing a `default` to silence
`-Wcase-redundant-default` instead of dropping `unique`.

So pass 3 hands back to pass 2 rather than self-certifying, and the re-review is
**full**, not a check of the changed lines — a fix changes the design, and the design is
what gets reviewed.

### Why this reduces escapes

| Failure | Which pass catches it |
|---|---|
| Plausible-but-wrong structure (binary CDC pointers) | 2 — checks mechanism, not appearance |
| Answer commitment | 2 — different objective; 3 — cannot self-approve |
| Tool-coverage conflation | 2 — tiering forces the scope statement |
| Symptom fixing | 3→2 boundary — full re-review |
| Unstated requirement | 2 — assumptions must be written down |
| Dialect blending | 2 — syntax category, `[slang]`-proven |
| Infinite polish | Retry bound → escalation |

The cost is real: three passes over every file. It is paid against a respin.

---

## What this does not fix

Honest limits, since overstating them would be the same error:

- **No CDC tool here means no CDC proof.** `severity-rubric.md` therefore refuses
  tape-out signoff on reasoning-tier CDC conclusions. The FIFO result above is exactly
  why.
- **A sufficiently wrong specification** produces correct RTL for the wrong design. The
  system forces assumptions to be *written down*, which makes the mismatch findable by
  a human — it does not detect it.
- **Arithmetic overflow needs real bounds.** If the spec does not state the input range,
  the honest output is `MANUAL_REVIEW_REQUIRED` with the question stated.
- **The gate can be switched off.** `RTL_GATE_DISABLE=1` exists because a gate that
  cannot be switched off gets uninstalled. Noise control — the SKIP rules in
  `rtl-workflow` — is what keeps it switched on.
