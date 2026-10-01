# Anti-patterns: Simulation vs synthesis, and X propagation

**Entirely `[reasoning]` tier** — and this is the most important fact in this file.
Verified by probe: slang reports **nothing** for a blocking assignment inside an
`always_ff`. The deadliest bug class in Verilog is invisible to the tool, so review
is the only defence.

These bugs share the worst possible signature: **simulation passes and silicon
fails**, which means verification signs off and the escape reaches the lab or the
customer.

---

## AP-SIM-01 — Blocking `=` in a clocked block
**Severity: HIGH** | **No tool catches this. Verified.**

**Description.** A blocking assignment inside `always_ff` / `always @(posedge clk)`.

```systemverilog
always_ff @(posedge clk) begin
  t   = d_i;      // blocking
  q_o <= t;       // sees the NEW t this cycle
end
```

**Root cause.** Blocking assignments take effect immediately within the block, so
`q_o` sees the new `t` and the two statements collapse into one flop. Non-blocking
would have given two flops in series. Simulation and synthesis can also disagree about
ordering when two blocks are involved, because execution order for blocking
assignments across blocks is not guaranteed.

**Symptoms.** Pipeline depth differs between simulation and gates. A race between two
blocks that behaves differently after any netlist change. Gate-level simulation
mismatches that RTL simulation never showed — the most expensive moment to find it.

**Detection.** Read every clocked block and check each assignment operator. This is one
of the highest-value manual reads in the entire review, precisely because no tool does
it. Grep is a reasonable first pass: a bare `=` inside an `always_ff`.

**Auto-fix.** Use `<=` for every assignment in a clocked block. If a temporary within
one cycle is genuinely wanted, compute it in a separate `always_comb` with a `_d` name.

---

## AP-SIM-02 — Incomplete explicit sensitivity list
**Severity: HIGH**

**Description.** `always @(a or b)` where the block also reads `c`.

**Root cause.** Verilog-2001 requires the author to maintain the list by hand.
Synthesis builds logic from what the block *reads*; simulation only re-evaluates on
what the list *names*.

**Symptoms.** Simulation holds a stale output when `c` changes; synthesis does not. A
functional bug that **appears only in simulation**, which inverts the usual debugging
instinct and wastes days.

**Detection.** Any explicit sensitivity list on a combinational block is a finding,
regardless of whether it is currently complete — it will not stay complete.

**Auto-fix.** `always @*` in Verilog-2001, `always_comb` in SystemVerilog. Both derive
the list automatically.

---

## AP-SIM-03 — `full_case` / `parallel_case` pragma
**Severity: HIGH**

**Description.** `case (sel) // synopsys full_case parallel_case`

**Root cause.** These tell **synthesis** to assume all cases are covered and mutually
exclusive. **Simulation ignores them.** So the two tools work from different
assumptions about the same code, and where the assumption is false they produce
different behaviour.

**Symptoms.** Simulation propagates X or takes the default; gates produce a definite
but arbitrary value. A documented post-silicon escape mechanism, not a theoretical risk
— it is one of the few constructs that *systematically* makes silicon differ from the
verified model.

**Detection.** Grep for `full_case`, `parallel_case`, `synopsys`, `synthesis full_case`.
Any occurrence is a finding.

**Auto-fix.** Delete the pragma and write the logic it was substituting for: add a real
`default`, and make the cases genuinely disjoint. If a uniqueness property is wanted,
assert it (`assert property ($onehot(...))`) so it is checked rather than assumed.

---

## AP-SIM-04 — `initial` block driving logic
**Severity: HIGH**

**Description.** `initial` used to set a value that the design then depends on.

**Root cause.** FPGA bitstreams honour initial values, so it works there. ASIC flops
power up arbitrarily and most ASIC synthesis ignores `initial` entirely.

**Symptoms.** Works on FPGA, fails on ASIC. Or works in simulation on both and fails
only in ASIC silicon — the worst case, because the FPGA prototype validated it.

**Detection.** Every `initial` block must be either a parameter assertion (`$fatal`), or
simulation-only and guarded (`// synthesis translate_off`). Anything else is a finding.

**Auto-fix.** Use a reset. If the target is genuinely FPGA-only and the initial value is
deliberate, say so explicitly in a comment — otherwise the block is unportable in a way
nobody will notice until it is ported.

---

## AP-SIM-05 — `#delay` in RTL
**Severity: BLOCKER**

**Description.** Any delay statement in synthesisable code.

**Root cause.** Testbench habit. Synthesis ignores delays; simulation honours them, so
timing-dependent behaviour is validated and then does not exist in hardware.

**Symptoms.** Simulation relies on a delay that silicon does not have. Races that
simulation never exposed because the delay happened to order things correctly.

**Detection.** Grep `#` in RTL files, excluding parameter overrides `#(...)`.

**Auto-fix.** Remove it. If the delay was ordering two events, that ordering needs real
logic — a flop, a handshake, or a state machine.

---

## AP-X-01 — `casex` hides X
**Severity: HIGH**

**Description.** `casex` used anywhere.

**Root cause.** `casex` treats X **in the selector** as don't-care, so an X matches the
first case item. An X that should have propagated and been noticed silently takes a
branch instead.

**Symptoms.** X bugs that simulation hides. A reset or initialisation bug that
simulation says is fine because the X matched a case item, while silicon behaves
unpredictably because the real value was indeterminate.

**Detection.** Grep `casex`. Zero occurrences is the only acceptable count. `casez` is
narrower (Z only) but still surprising — require a written justification.

**Auto-fix.** Explicit `case` with `default`. If masked matching is genuinely needed,
mask explicitly: `case (sel & MASK)`.

---

## AP-X-02 — Flop read before written, no reset
**Severity: HIGH** (BLOCKER on a control path)

**Description.** A flop with no reset whose value is read before anything writes it.

**Root cause.** Skipping reset to save area — legitimate for datapath flops whose valid
bit is reset, illegitimate when nothing gates the read.

**Symptoms.** X in simulation at startup, propagating until someone adds an
initialisation that masks it. In silicon, an arbitrary power-up value that is stable and
wrong — so it looks like a logic bug, not an initialisation bug.

**Detection.** For every unreset flop, find what guarantees it is written before read.
In both golden FIFOs that guarantee is the pointer relationship, and it is commented. No
such guarantee means this bug.

**Auto-fix.** Reset the flop, or gate every read on a valid bit that **is** reset, and
comment the reasoning.

---

## AP-X-03 — X-optimism in a mux or case
**Severity: MEDIUM**

**Description.** Simulation resolves an X input to a definite output where gates would
propagate the X, or the reverse (X-pessimism).

**Root cause.** RTL simulation semantics for `case` and `if` do not match gate-level X
behaviour. A `case` with an X selector takes `default`; the synthesised mux produces X
on its output.

**Symptoms.** RTL simulation clean, gate-level simulation shows X propagation (or the
reverse). Usually found very late, during gate-level regression, when schedule pressure
is highest.

**Detection.** Where an X could reach a selector — during reset, from an uninitialised
memory, across an unsynchronised boundary — the two models may differ. Flag it rather
than relying on either.

**Auto-fix.** Eliminate the X at its source (reset the flop, gate the read). Where it
cannot be eliminated, add an assertion that the selector is never X, so the condition is
detected rather than silently resolved either way.
