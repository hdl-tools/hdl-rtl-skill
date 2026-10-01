# Checklist: Core — categories 1–8

Format for every category: **Goal / Checks / Fails when / Severity / Fix.**

---

## 1. Functional Intent Review

**Goal.** Confirm the RTL implements what was *asked for*, not a plausible
neighbour of it. This catches more real bugs than every syntactic check combined,
and no tool performs it.

**Checks**
- Restate the requested behaviour in one sentence, then find the lines that
  implement each clause. A clause with no corresponding logic is a missing
  feature; logic with no corresponding clause is unrequested scope.
- Confirm reset values are the *specified* idle state, not merely zero.
- Confirm latency and throughput match the ask. "One beat per cycle" and "one
  beat every other cycle" look identical in a code read.
- Confirm the polarity of every control input against the spec, not against habit.
- For counters: wrap or saturate? This is a specification decision and has no
  safe default.
- Enumerate what the module does on *simultaneous* inputs (load and increment;
  read and write when empty; flush and enable). Every such pair needs a defined
  priority.

**Fails when** behaviour differs from the request under any input the spec
allows; an input is accepted and ignored; a stated requirement has no logic.

**Severity** BLOCKER if the primary function is wrong. HIGH if a corner case is
wrong. MEDIUM if an unstated-but-implied behaviour is missing.

**Fix** Name the clause, name the line, state the corrected behaviour. If the
spec is genuinely ambiguous, do **not** pick silently —
`MANUAL_REVIEW_REQUIRED` and state both readings.

---

## 2. Syntax Review

**Goal.** The file compiles, as the dialect it claims to be.

**Checks**
- `bin/rtl-lint <file>` — any `severity: error` is a BLOCKER. **[slang]**
- `.v` files must not use SystemVerilog constructs (`logic`, `always_ff`,
  `always_comb`, `'0`, `typedef`, `int unsigned` parameters).
- No identifier collides with a reserved word. `small`, `medium`, `large` are
  charge-strength keywords and slang rejects them.
- `` `default_nettype none `` present, and restored to `wire` at end of file.

**Fails when** slang reports any error.

**Severity** BLOCKER, always. Unparseable RTL cannot be reviewed further.

**Fix** Quote slang's message verbatim and correct exactly that.

---

## 3. Synthesizability Review

**Goal.** Everything here becomes gates.

**Checks**
- No `#delay`, no `wait`, no `fork`/`join`, no `initial` driving logic.
- `initial` used only for parameter assertions (`$fatal`) or simulation-only
  checks, and guarded by `// synthesis translate_off` in Verilog-2001.
- No `$random`, `$display`, `$time` in a synthesised path.
- No unbounded `for`; loop bounds must be elaboration-time constants.
- No real/shortreal, no dynamic arrays, no queues, no classes.
- Division and modulo only by a power-of-two constant. A general divider must be
  an explicit instance, not an inferred `/`.
- No hierarchical references out of the module.
- No tri-state except at a true pad.

**Fails when** a construct has no gate-level equivalent, or the tool will
silently infer something enormous (a `/` by a variable).

**Severity** BLOCKER for unsynthesisable constructs. HIGH for a construct that
synthesises but to something unintended (variable divide, huge multiplier).

**Fix** Replace with the synthesisable equivalent; for arithmetic, instantiate an
explicit, pipelined unit and state its latency.

---

## 4. Sequential Logic Review

**Goal.** Every flop is the flop you intended.

**Checks**
- `always_ff` for every clocked block (SV). Plain `always` in `.sv` is a finding.
- **Non-blocking `<=` only.** A blocking `=` in a clocked block is a sim/synth
  mismatch and **slang does NOT detect it** — this check is `[reasoning]` and is
  one of the highest-value manual reads in the list.
- Exactly one `always_ff` drives any given signal. **[slang: multi-driver error]**
- Sensitivity list is `@(posedge clk)` plus at most the async reset edge.
- No clock used as data, no data used as a clock.
- No derived or gated clock written in RTL (`assign gclk = clk & en`). Use an
  enable, or an explicit library clock-gate cell.
- A payload and its valid bit are registered in the **same** block.
- Every flop that needs a defined power-up value has a reset branch.

**Fails when** a blocking assignment appears in a clocked block; two blocks drive
one signal; a clock is generated in RTL.

**Severity** BLOCKER for an RTL-generated clock or multi-driver. HIGH for
blocking-in-clocked or a split valid/payload.

**Fix** Convert to `<=`; merge the drivers into one block; replace the generated
clock with an enable or a library cell.

---

## 5. Combinational Logic Review

**Goal.** No latches, no loops, no sim/synth divergence.

**Checks**
- `always_comb` (SV) or `always @*` (V2001). An explicit sensitivity list is a
  finding — a missing signal makes simulation and synthesis disagree.
- Every output of the block is assigned a default on the **first** lines.
- No blocking/non-blocking mixing; `always_comb` uses `=` only.
- No combinational feedback: trace every output back and confirm it does not
  reach its own input without a flop. `[reasoning]` — slang catches only some
  cases.
- A signal is not driven by both an `assign` and an `always` block.
- Prefer `assign` wherever the logic fits one expression — it cannot latch.

**Fails when** a path leaves an output unassigned; a sensitivity list is
incomplete; an output feeds back to itself combinationally.

**Severity** HIGH for an inferred latch or incomplete sensitivity list. BLOCKER
for a combinational loop.

**Fix** Add the leading default assignment; switch to `always_comb`/`always @*`;
break the loop with a register and state the new latency.

---

## 6. Latch Review

**Goal.** Zero unintended latches. This is the category tools are best at and
reviewers most often skip.

**Checks**
- `bin/rtl-lint` → `-Winferred-latch`. **[slang]**
- **The tool must run with FULL elaboration.** `slang --lint-only` does *not*
  report `-Winferred-latch` (verified by probe). If someone "optimised" the gate
  to `--lint-only`, latch detection is silently gone. `bin/rtl-lint` is correct;
  do not change it.
- Any `if` without `else`, or `case` without `default`, inside a combinational
  block, where the block assigns an output.
- A deliberate latch must be commented as deliberate and justified.

**Fails when** slang reports `-Winferred-latch` and no justification exists.

**Severity** HIGH normally; BLOCKER on a control path or in an ASIC flow with no
latch cells characterised.

**Fix** Assign every output unconditionally at the top of the block. Not by
adding an `else` to each branch — by making the block total at entry.

---

## 7. FSM Review

**Goal.** The machine cannot get stuck, cannot reach a state it can never leave,
and recovers from an illegal encoding.

**Checks**
- Three-block structure (state register / next-state / output decode).
- States are a named `enum`, not raw literals.
- Next-state block assigns `state_d = state_q` before the `case`.
- **`default:` present and it recovers.** With S legal states in B bits there are
  `2**B - S` illegal encodings; a bit flip or a bring-up X lands in one. Without
  a recovering default the machine wedges until power cycle.
- **Reachability:** every state is the target of at least one transition from
  another state. An unreachable state is dead logic that synthesis removes,
  usually along with the behaviour you wanted.
- **Liveness:** every state has at least one exit that does not depend on a
  condition that the state itself prevents. Walk each state and name its exit.
- Terminal/error states require an explicit acknowledge to leave — not an
  accidental one.
- Outputs decoded from `state_q` only (Moore) unless Mealy is specified; if
  Mealy, confirm the timing against the spec's waveform.
- `unique case` and `default` together are flagged `-Wcase-redundant-default`.
  Keep `default`, drop `unique`.

**Fails when** a state has no exit; a state is unreachable; `default` is missing
or merely assigns `state_d = state_q` (that is a wedge, not a recovery).

**Severity** BLOCKER for a reachable deadlock. HIGH for missing illegal-state
recovery. MEDIUM for an unreachable state.

**Fix** Add the recovering `default`; add the missing transition; delete the dead
state.

---

## 8. Case Statement Review

**Goal.** Full, parallel, and X-honest.

**Checks**
- `default:` on every `case`. **[slang: `-Wcase-default`]**
- **No `casex` — ever.** It treats X in the *selector* as don't-care, which hides
  exactly the X bugs you need to see.
- `casez` only with a written justification.
- **No `full_case` / `parallel_case` pragmas.** They instruct synthesis to assume
  a property simulation does not enforce, so sim and silicon diverge. This is a
  documented post-silicon escape mechanism, not a theoretical risk.
- Case item widths match the selector width. **[slang: `-Wwidth-trunc`]**
- Overlapping items: confirm the intended priority, or make them disjoint.
- `case` on an `enum` covers every enumerated value.

**Fails when** `default` is absent; `casex` appears; a pragma substitutes for
logic; item widths mismatch.

**Severity** HIGH for `casex` or a `full_case`/`parallel_case` pragma. MEDIUM for
a missing `default` that is provably unreachable; HIGH if it is reachable.

**Fix** Add `default`; replace `casex` with explicit `case` plus `default`;
delete the pragma and write the logic it was papering over.
