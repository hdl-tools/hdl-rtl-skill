# Anti-patterns: FSM

`AP-FSM-02` is detectable by slang (two diagnostics, proven in
`tests/bad/ap_case_no_default.sv`). The rest are `[reasoning]`.

---

## AP-FSM-01 — Missing illegal-state recovery
**Severity: HIGH**

**Description.** The next-state `case` has no `default`, or has one that just holds
(`default: state_d = state_q;`).

**Root cause.** An encoding with S legal states in B bits has `2**B - S` illegal
encodings. A bit flip (SEU, a long wire, a marginal reset release) or an X at
bring-up lands in one. Holding state there is a permanent wedge.

**Symptoms.** A block that works for hours then stops responding and needs a power
cycle. No error flag — from the outside it just goes quiet. Extremely expensive to
diagnose in the field.

**Detection.** Every FSM `case` has a `default` that moves to a **recovery** state.
`default: state_d = state_q;` is this bug wearing a disguise. Check the arithmetic:
`2**$bits(state_q)` vs the number of enum values.

**Auto-fix.** `default: state_d = ST_ERROR;` (or `ST_IDLE` where a silent restart is
acceptable). Going to an error state is better — it makes the fault observable
instead of merely survivable. See `golden_fsm.sv`.

---

## AP-FSM-02 — `case` without `default`
**Severity: HIGH** | **Detectable: `[slang]`** — `-Wcase-default`, and usually
`-Winferred-latch` alongside it.

**Description.** Any `case` in a combinational block with no `default`.

**Root cause.** Unlisted selector values leave the outputs unassigned, which infers
a latch — so one omission produces two different bugs at once.

**Symptoms.** Latch warnings in synthesis; timing failures on a path through a
latch; state or outputs holding values nobody intended.

**Detection.** `bin/rtl-lint` reports `-Wcase-default`. Proven to fire —
`tests/bad/ap_case_no_default.sv`.

**Auto-fix.** Add `default`. Better: assign all outputs defaults on the first lines
of the block, which makes the omission harmless as well as reported.

---

## AP-FSM-03 — Unreachable state
**Severity: MEDIUM**

**Description.** A state that no transition from any other state targets.

**Root cause.** A transition was removed, renamed, or never written. Often a state
added for a feature that was then implemented differently.

**Symptoms.** Synthesis removes the state and all logic exclusive to it — including
behaviour you expected. The design is smaller than you predicted and quietly
missing a feature. A lint warning usually appears and is usually waived.

**Detection.** Build the transition list: for each state, which states target it?
Any state with no inbound transition (except the reset state) is unreachable.

**Auto-fix.** Either add the missing transition, or delete the state and its logic.
Do not leave it: a dead state misleads every future reader about what the machine
does.

---

## AP-FSM-04 — State with no exit
**Severity: BLOCKER**

**Description.** A state whose only exit condition can never become true once the
machine is in it.

**Root cause.** The exit depends on something the state itself prevents — waiting
for a `done` from a unit the state does not start, or for a counter that only
increments in another state.

**Symptoms.** A hard hang, reproducible once the triggering sequence is found. Often
reaches silicon because the triggering sequence is a corner case: an error during a
transfer, an abort, a simultaneous request.

**Detection.** For each state, write its exit condition and name what makes that
condition true. If the answer involves something only reachable from a different
state, the state is a deadlock. Pay particular attention to error and abort states.

**Auto-fix.** Add a timeout exit, or make the exit depend on something the state
can itself influence. Every wait state needs an escape.

---

## AP-FSM-05 — One-block FSM mixing state and outputs
**Severity: MEDIUM**

**Description.** State transitions and output assignments in a single `always_ff`.

**Root cause.** Looks more compact. In exchange, every output is registered, so all
outputs appear one cycle later than the state they belong to, and the spec's
waveform no longer matches.

**Symptoms.** Everything off by one cycle at an interface. A protocol violation
where a strobe lands one cycle after the data it qualifies.

**Detection.** Any `always_ff` that assigns both `state_q` and a non-state output.

**Auto-fix.** Split into three blocks (`golden_fsm.sv`): state register, next-state
decode, output decode. If a registered output is genuinely wanted, keep the
three-block structure and register that output deliberately, with a comment.
