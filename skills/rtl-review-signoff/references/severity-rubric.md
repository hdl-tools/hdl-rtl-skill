# Severity rubric and gate logic

One definition per level, then the gate that consumes them. `hooks/rtl_gate.sh`
implements this; keep the two in step.

---

## Definitions

### BLOCKER — the design is wrong
Ship this and the chip does not work, or does not come up at all.

- Does not compile (any slang `severity: error`).
- Unsynthesisable construct in a synthesised path.
- Primary specified function is incorrect.
- Multi-bit bus crossing clock domains without an async FIFO or handshake.
- Clock generated in RTL (`assign gclk = clk & en`) with no DFT bypass.
- Reset polarity inverted relative to its name, or FSM state with no reset.
- Reachable FSM deadlock, or no recovery from an illegal state encoding.
- Combinational loop.
- Multiple drivers on one signal.
- Overflow that corrupts an address or a control value.
- `valid` combinationally dependent on `ready` (deadlock / comb loop on connect).
- X on a control path or an FSM state register.

**Gate: REJECT.** One is enough. No count threshold, no override.

### HIGH — a real bug under identifiable conditions
Works in the nominal test, fails in a condition the spec permits.

- Width or port truncation on a data or address path (`-Wwidth-trunc`,
  `-Wport-width-trunc`).
- Mixed signedness in a comparison or arithmetic (`-Wsign-compare`,
  `-Warith-op-mismatch`).
- Inferred latch with no justification (`-Winferred-latch`).
- Blocking `=` in a clocked block (sim/synth mismatch; **slang will not catch
  this**).
- Single flop where two are needed; logic inside a synchroniser chain;
  reconvergence of separately synchronised bits.
- Missing reset synchroniser in a domain; reset-domain crossing.
- `casex`, or a `full_case`/`parallel_case` pragma.
- Arbitration starvation; retracted `valid`; unstable payload under backpressure.
- Throughput below the documented figure.
- Data-path overflow reachable with legal inputs.
- Parameter boundary value produces broken hardware with no elaboration assertion.
- Uncontrollable async reset in test mode; memory enable permanently asserted.

**Gate: `APPROVED_WITH_CHANGES` at 1–2. `REJECTED` at >= 3.**
Rationale for the threshold: one or two HIGH findings is a fixable design; three
or more means the author's model of the problem is wrong, and patching
individual symptoms produces a design that is wrong in a way nobody can see any
more. Send it back.

### MEDIUM — latent risk or missing protection
Not currently broken; fragile, or broken outside the stated range.

- Missing `default` on a `case` that is currently provably unreachable.
- Missing `ASYNC_REG` attribute or STA constraint.
- Missing elaboration assertion for a constraint all current callers respect.
- Datapath flop with no reset where the valid bit *is* reset.
- Overflow reachable only outside the specified input range (state the range).
- Missing timeout on something that can wait indefinitely.
- An **unclassified** slang warning — default MEDIUM, never dropped.
- Missing load gating on a narrow register (power).

**Gate: warn and record. Does not block.**
**Escalation: >= 8 MEDIUM in one file counts as one additional HIGH.** A pile of
"minor" risks in one module is itself a signal about that module.

### LOW — style and clarity with a maintenance cost
- Naming deviates from `rtl-style-guide`.
- Unused signal or port (`-Wunused-port`, `-Wunused-but-set-variable`).
- Magic number that should be a named `localparam`.
- `unique case` together with `default` (`-Wcase-redundant-default`).
- Inconsistent reset style with no functional consequence.
- Formatting, comment density, module length.

**Gate: suggest. Never blocks.**

### INFO — observations and recorded decisions
- A CDC crossing that is correct, with its mechanism recorded for the integrator.
- An assumption made about an unstated requirement.
- A deliverable for a downstream team (UPF, SDC false path, memory BIST wrapper).
- `-Wuseless-cast` and similar cosmetic notes.

**Gate: record only.** INFO findings are how the next person learns what you
assumed, so do not suppress them.

---

## Gate logic

```python
def gate(counts, self_critique, confidence):
    # 1. Hard stop
    if counts.BLOCKER >= 1:
        return "REJECTED", f"{counts.BLOCKER} blocker(s)"

    # 2. Confidence escalation runs BEFORE the HIGH count, because an
    #    unanalysable CDC or reset is not improved by having few findings --
    #    it means the review itself was not possible.
    if confidence.cdc   < 0.70:  return "MANUAL_REVIEW_REQUIRED", "CDC unanalysable"
    if confidence.reset < 0.70:  return "MANUAL_REVIEW_REQUIRED", "reset arch unknown"
    if confidence.spec  < 0.70:  return "MANUAL_REVIEW_REQUIRED", "ambiguous requirement"

    # 3. MEDIUM pile-up escalates
    effective_high = counts.HIGH + (1 if counts.MEDIUM >= 8 else 0)

    if effective_high >= 3:  return "REJECTED", f"{effective_high} high findings"

    # 4. Self-critique must be complete, with every YES mitigated
    if not self_critique.all_answered:
        return "MANUAL_REVIEW_REQUIRED", "self-critique incomplete"
    if self_critique.unmitigated_yes:
        return "REJECTED", "unmitigated self-critique risk"

    if effective_high >= 1:
        return "APPROVED_WITH_CHANGES", f"{effective_high} high finding(s), fixes named"

    return "APPROVED", "clean"
```

### Escalation rules
1. **BLOCKER always wins.** No count, no context, no override.
2. **Low confidence outranks a low finding count.** Few findings in code you could
   not analyse is not a good review — it is an absent one.
3. **8+ MEDIUM = 1 HIGH.** Accumulated fragility is a real signal.
4. **An unclassified tool warning is MEDIUM, never discarded**, and gets added to
   `hooks/slang-warnings.txt` so it is classified next time.
5. **`TOOL=none` caps the outcome at `APPROVED_WITH_CHANGES`**, with an explicit
   note that no deterministic check ran. A reasoning-only review must never be
   presented as a signoff.
6. **3 exhausted auto-fix rounds → `MANUAL_REVIEW_REQUIRED`**, regardless of what
   remains. See the retry section in `skills/rtl-workflow/SKILL.md`.

---

## Release gates

| Gate | Requires |
|---|---|
| **Commit** | No BLOCKER. HIGH allowed only with a tracked issue. |
| **Block-level signoff** | No BLOCKER, no HIGH. All CDC crossings enumerated with mechanisms. All parameter assertions present. |
| **Integration** | Block signoff, plus every INFO deliverable (SDC constraints, UPF, BIST wrapper) handed to its owner. |
| **Tape-out** | Nothing above LOW. Every CDC and reset finding closed by a **tool** run (`/rtl-cdc`), not by reasoning alone. Every waiver named, reasoned, and owned. |

The tape-out row is the one that matters: `[reasoning]`-tier CDC and reset
conclusions are **not** sufficient for tape-out, however confident they are. They
exist to catch problems early and to tell you what the tool run must confirm.
