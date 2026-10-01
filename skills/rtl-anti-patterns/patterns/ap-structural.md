# Anti-patterns: Structural

**The strongest file for tool detection** — four of five are proven detectable, and
each has a file in `tests/bad/`.

---

## AP-LATCH-01 — Incomplete combinational block
**Severity: HIGH** | **Detectable: `[slang]`** — `-Winferred-latch`.
Proven: `tests/bad/ap_inferred_latch.sv`.

**Description.** An `always_comb` (or `always @*`) that does not assign an output on
every path.

```systemverilog
always_comb begin
  if (sel_i) y_o = a_i;    // no else -> y_o latches
end
```

**Root cause.** The language requires a value on every path. With none, the
semantics are "hold the previous value", which is a latch.

**Symptoms.** Latch warnings in synthesis. Timing failures on paths through the
latch (STA handles latches poorly). In an ASIC flow with no characterised latch
cells, synthesis may fail outright. Functionally: stale data where you expected
combinational logic.

**Detection.** `bin/rtl-lint` → `-Winferred-latch`.
**The gate must run FULL elaboration.** `slang --lint-only` does **not** report this
— verified by probe. If anyone "optimises" `bin/rtl-lint` to `--lint-only`, latch
detection silently disappears. This is recorded in `hooks/slang-warnings.txt`
because it is the easiest way to break this repo's main value.

**Auto-fix.** Assign defaults on the **first** lines of the block, not by adding an
`else` to each branch:

```systemverilog
always_comb begin
  y_o = 1'b0;              // total at entry -- future edits cannot break it
  if (sel_i) y_o = a_i;
end
```

---

## AP-STRUCT-01 — Multiple drivers
**Severity: BLOCKER** | **Detectable: `[slang]`** — hard error.
Proven: `tests/bad/ap_multiple_drivers.sv`.

**Description.** Two continuous assignments, or two `always` blocks, driving one
signal.

**Root cause.** Usually a copy-paste, or two authors adding a case to the same
signal in different places.

**Symptoms.** Compile error in a strict tool; in a lenient one, X where the drivers
disagree, or a wired-OR that happens to work until the inputs conflict.

**Detection.** `bin/rtl-lint` reports it as an error, so it is a BLOCKER
automatically.

**Auto-fix.** Merge into one block with explicit priority. Do not "fix" it by making
one driver conditional — that is a latch or a loop waiting to happen.

---

## AP-STRUCT-02 — Implicit net from a typo
**Severity: BLOCKER with `` `default_nettype none ``; otherwise SILENT**
Proven: `tests/bad/ap_implicit_net.sv`.

**Description.** A misspelled signal name creates a new one-bit implicit wire.

```systemverilog
assign some_nte = a_i;     // meant some_net
assign y_o = some_net;     // reads a different, undriven signal
```

**Root cause.** Verilog's default `` `default_nettype wire `` silently declares any
undeclared identifier as a one-bit net.

**Symptoms.** Without `none`: a signal is permanently Z or X, or a multi-bit value
is silently truncated to one bit, and nothing reports it. This is among the most
time-consuming bugs to find because the code reads correctly.

**Detection.** `` `default_nettype none `` turns it into "use of undeclared
identifier" — a compile error. **One line converts an invisible bug class into a
BLOCKER.** This is why the style guide makes it mandatory.

**Auto-fix.** Add `` `default_nettype none `` at the top of every RTL file and
`` `default_nettype wire `` at the end. Then fix the spelling the compiler points at.

---

## AP-STRUCT-03 — Signal read but never driven
**Severity: HIGH** | **Detectable: `[slang]`** — `-Wunassigned-variable`.
Proven: `tests/bad/ap_unassigned.sv`.

**Description.** A declared signal is read but nothing assigns it.

**Root cause.** Logic deleted during refactor; a port never connected; a planned
feature declared and not written.

**Symptoms.** X propagation in simulation, constant zero in synthesis (or whatever
the tool picks) — so sim and synthesis disagree about a value nobody defined.

**Detection.** `bin/rtl-lint` → `-Wunassigned-variable`. Also check
`-Wunused-port`: an unused *input* port usually means a missing connection inside,
which is the same bug from the other side.

**Auto-fix.** Drive it, or delete it. Deleting is usually right — an unassigned
signal is normally a leftover.

---

## AP-LOOP-01 — Combinational loop
**Severity: BLOCKER** | partial `[slang]`

**Description.** A combinational path from a signal back to itself with no flop.

```systemverilog
assign a = b | c;
assign b = a & d;     // a -> b -> a
```

**Root cause.** Often created across module boundaries, where neither module alone
looks wrong: module X's `valid` depends on its `ready` input, module Y's `ready`
depends on its `valid` input. Connect them and the loop exists. This is why
ready/valid rule R4 is a BLOCKER on its own.

**Symptoms.** Simulation hangs or oscillates in zero time ("iteration limit
exceeded"). Synthesis reports a loop and cuts it arbitrarily, producing hardware
nobody designed. STA cannot analyse it.

**Detection.** slang catches some same-module cases. For cross-module loops, check
each interface: does any output depend combinationally on an input that the partner
derives from that output? Trace `valid`→`ready` dependencies specifically.

**Auto-fix.** Break the loop with a register and state the new latency. For
ready/valid, that register is exactly `golden_register_slice.sv` — which is what a
skid buffer is for.
