---
name: rtl-style-guide
description: "Coding style and naming rules for Verilog and SystemVerilog RTL. Load whenever writing, modifying, or suggesting a fix to any .v/.sv/.svh/.vh file. Naming: _q _d _n _i _o clk rst_n. always_ff, always_comb, logic vs reg vs wire. FSM structure, parameters and localparam, default_nettype none, module structure, port ordering, formatting, commenting, forbidden patterns. Applies to ASIC and FPGA RTL. Keywords: verilog, systemverilog, rtl, module, always_ff, always_comb, naming convention, coding style, lint clean, synthesizable."
metadata:
  type: implicit
  applies-to: ["*.v", "*.sv", "*.svh", "*.vh"]
  verified-with: "slang 9.0.0+54385bb -- every rule below is clean on the golden templates"
---

# RTL Style Guide

This is not a taste document. Every rule here exists because breaking it causes
a specific class of bug, and that bug is named. Rules marked **[slang]** are
mechanically enforced by `bin/rtl-lint`; the rest are enforced by review.

**Every rule is demonstrated by a working, slang-clean file in
`skills/rtl-golden-templates/templates/`.** When a rule and a template
disagree, the template is right — it compiles.

---

## 1. Naming

| Suffix | Means | Example |
|---|---|---|
| `_i` | module input port | `wr_en_i`, `s_valid_i` |
| `_o` | module output port | `full_o`, `grant_o` |
| `_q` | output of a flop (current registered state) | `count_q`, `state_q` |
| `_d` | input to a flop (next value, combinational) | `count_d`, `state_d` |
| `_n` | active low | `rst_n`, `cs_n` |
| `_w` | explicitly a wire/net alias, where it aids reading | `max_count_w` |

Combine in the order *role then direction*: a registered output port is `count_q`
(see `golden_counter.sv`), a registered output whose valid matters is
`valid_q_o` (see `golden_pipeline_stage.sv`).

**Exempt from `_i`/`_o`:** `clk` and `rst_n`. Universally understood, and
suffixing them adds noise to every single module. Multi-clock modules qualify by
domain instead: `wr_clk`, `wr_rst_n`, `rd_clk`, `rd_rst_n` (see
`golden_fifo_async.sv`).

**The `_d`/`_q` pair is the point.** If you can see `count_d` and `count_q`, you
can see at a glance that one `always_comb` computes it and one `always_ff`
registers it. If a signal is named `count` and assigned in an `always_ff`, a
reviewer cannot tell whether a read of it is the old or the new value.

### Names that are not allowed
- `small`, `medium`, `large` — Verilog charge-strength **keywords**. slang
  rejects them as identifiers. Found the hard way while writing these templates.
- `data`, `temp`, `tmp`, `foo`, `signal`, `value` alone. Say what it is.
- Single letters except loop variables (`i`, `j`, `k`) and genvars.
- Anything differing from another name only by case. Verilog is case sensitive;
  humans reviewing a diff are not.

---

## 2. Sequential logic

**Preferred — SystemVerilog:**
```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    count_q <= '0;
  end else begin
    count_q <= count_d;
  end
end
```

**Acceptable — Verilog-2001 only when SystemVerilog is unavailable:**
```verilog
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) count_q <= {WIDTH{1'b0}};
  else        count_q <= count_d;
end
```

Rules:
- **`always_ff`, not `always`.** `always_ff` makes the tool *prove* the block is
  a flop. A plain `always` that accidentally contains a combinational path
  synthesises to something you did not design, silently.
- **Non-blocking `<=` only, never `=`.** Blocking assignment in a clocked block
  creates a sim/synth mismatch that slang does **not** catch (verified). Review
  must catch it. See `tests/bad/` for the probe.
- **One signal, one `always_ff`.** Two clocked blocks driving one signal is a
  multiple-driver error, which slang catches as a hard error **[slang]**.
- **Payload and its valid bit in the SAME `always_ff`.** Splitting them lets a
  later edit change one enable and not the other, and the valid bit drifts a
  cycle from its data. See `golden_pipeline_stage.sv`.
- **No logic in the sensitivity list** beyond `posedge clk` and the reset edge.
  No `@(posedge clk or posedge something_else)`.

---

## 3. Combinational logic

**Preferred:** `always_comb`.  **Acceptable in Verilog-2001:** `always @*`.
**Never:** `always @(a or b or sel)` — an explicit list that misses a signal
simulates differently from how it synthesises. This is the classic
Verilog-2001 sim/synth mismatch.

**Assign a default first, on every path.** This is the single highest-value rule
in this document:

```systemverilog
always_comb begin
  count_d = count_q;        // default FIRST -- now no path can infer a latch
  if (clear_i)      count_d = '0;
  else if (load_i)  count_d = load_value_i;
end
```

An `always_comb` that does not assign an output on every path infers a latch
**[slang: `-Winferred-latch`]**. Writing the default on line one makes the block
total by construction, so a future edit that adds a branch cannot break it.

**Prefer `assign` for anything that fits on one line.** `assign full_o = ...;`
cannot infer a latch at all, so it removes a whole failure mode.

---

## 4. Data types

| Use | For | Notes |
|---|---|---|
| `logic` | everything in SystemVerilog | Default choice. Works for flops and nets. |
| `wire` | SystemVerilog module **inputs** | Makes "this is driven elsewhere" explicit, and an accidental procedural assignment to it becomes a compile error. |
| `reg` | Verilog-2001 only | Anything assigned in an `always` block. |
| `wire` | Verilog-2001 only | Anything assigned with `assign`. |

- **`logic` is not "a register".** It is a 4-state variable. Whether it becomes a
  flop depends entirely on the block that drives it.
- Use `logic signed` only when the value is genuinely signed, and then make
  **every** operand in the expression signed. Mixing trips
  **[slang: `-Wsign-compare`, `-Warith-op-mismatch`]**.
- Prefer an `enum` over raw parameters for state encodings — the tool can then
  name the state it is complaining about. See `golden_fsm.sv`.
- `typedef struct packed` for a payload carried as a unit. Packed, so it is
  synthesisable and has a defined bit layout.

---

## 5. `` `default_nettype none `` — mandatory

Open every RTL file with `` `default_nettype none `` and close it with
`` `default_nettype wire ``.

Without it, a typo'd signal name silently becomes a new one-bit implicit wire and
the design is wrong in a way nothing reports. With it, the same typo is a hard
**compile error** (verified: "use of undeclared identifier"). One line converts
an invisible bug class into a BLOCKER. The closing `` `wire `` matters because
the directive leaks into every file compiled after this one.

---

## 6. FSM structure

Three blocks, always. See `golden_fsm.sv`.

1. **State register** — `always_ff`, holds `state_q`, drives nothing else.
2. **Next-state decode** — `always_comb`, assigns `state_d = state_q` first,
   then a `case`.
3. **Output decode** — `always_comb`, assigns all outputs to defaults first,
   then a `case` on `state_q`.

Requirements:
- `typedef enum logic [N-1:0]` with named states.
- **`default:` is mandatory** and must do something useful — go to a recovery or
  error state. An FSM with 5 legal states in 3 bits has 3 illegal encodings; a
  bit flip or an X during bring-up lands there, and without a default the
  machine wedges forever.
- Use plain `case`, **not `unique case`, when you also have a `default`** — they
  conflict, and slang flags it **[slang: `-Wcase-redundant-default`]**. Safe
  recovery beats the uniqueness assertion; assert uniqueness separately as a
  concurrent property. The reasoning is written out in `golden_fsm.sv`.
- Moore outputs (from `state_q` only) unless the spec genuinely needs Mealy.
- Never assign outputs in the state-register block.

---

## 7. Parameterisation

```systemverilog
module m #(
    parameter int unsigned WIDTH = 8,            // caller-tunable
    parameter int unsigned DEPTH = 16
) ( ... );
  localparam int unsigned ADDR_W = $clog2(DEPTH);   // derived, NOT a parameter
```

- **`parameter` for what the caller sets. `localparam` for what you derive.** A
  derived value left as a `parameter` can be overridden inconsistently with the
  value it was derived from, and the module is then quietly broken.
- **Type your parameters** (`int unsigned`, `bit`, `logic [W-1:0]`). An untyped
  parameter takes its type from its default value, which is how a `WIDTH` ends
  up signed.
- **Assert the constraints you rely on**, in an `initial` block with `$fatal`:
  ```systemverilog
  initial begin
    if ((DEPTH & (DEPTH-1)) != 0)
      $fatal(1, "DEPTH must be a power of two (got %0d)", DEPTH);
  end
  ```
  Every golden template with a parameter constraint does this. A FIFO whose
  gray-code pointers assume a power-of-two depth must *refuse to elaborate* at
  depth 12 rather than produce broken flags.
- Size-cast carefully: `WIDTH'(1)` is **signed**, because the bare literal `1`
  is a signed int. Write `WIDTH'(1'b1)` or `{{(WIDTH-1){1'b0}}, 1'b1}`.

---

## 8. Module structure

Fixed order, so a reviewer always knows where to look:

```
header comment block
`default_nettype none
module name #(parameters) (ports);
  parameter assertions (initial / $fatal)
  localparams
  type declarations (typedef, enum)
  signal declarations
  continuous assignments (assign)
  combinational blocks (always_comb)
  sequential blocks (always_ff)
  submodule instantiations
  assertions (assert property)
endmodule
`default_nettype wire
```

Ports: ANSI style only. Grouped clock/reset, then inputs, then outputs; for
multi-domain modules group by domain with a comment banner per domain (see
`golden_fifo_async.sv`). **Always use named port connections** on instantiation
(`.a_i(foo)`), never positional — positional connections break silently when
someone reorders a port list.

---

## 9. Formatting

- 2-space indent, no tabs.
- 100 column soft limit, 120 hard.
- One statement per line. `begin`/`end` on **every** multi-line branch, even
  single-statement ones — it is the cheapest insurance against the next edit.
- Align the `<=` / `=` in a run of related assignments; it makes a missing one
  visible.
- One blank line between logical blocks, a banner comment between major sections.

---

## 10. Commenting

Comment the **why**, never the what. `count_q <= count_q + 1; // increment` is
noise. These are worth writing:

- **Module header** — purpose, and the contract the module assumes.
- **Every non-obvious constant or magic number** — where it came from.
- **Every CDC boundary** — which domains, and why this crossing is safe.
- **Every deliberate deviation from this guide** — with the reason.
- **Every assumption about the caller** — "DEPTH must be a power of two".

If a block needed thought to write, it needs a comment, or the next engineer
will "simplify" it back into the bug you avoided.

---

## 11. Forbidden

| Never | Why |
|---|---|
| `#delay` in RTL | Not synthesisable. Sim-only behaviour baked into the design. |
| `initial` blocks for logic | Only for parameter assertions and simulation-only checks. FPGA tolerates it; ASIC does not. |
| Blocking `=` in a clocked block | Sim/synth mismatch. slang does **not** catch this — review must. |
| Non-blocking `<=` in `always_comb` | Simulates with a delta delay you did not intend. |
| `always @(a or b)` explicit lists | Missing signal = sim/synth mismatch. Use `always @*` / `always_comb`. |
| Latches, unless deliberate and reviewed | `-Winferred-latch`. If you truly want one, say so in a comment and justify it. |
| Multiple drivers on one signal | Hard error. **[slang]** |
| Async reset **release** without synchronisation | Reset recovery/removal violation. Every domain needs a reset synchroniser. |
| Binary counters through a CDC synchroniser | Multiple bits change at once; you sample a value that never existed. Gray code or handshake. |
| Gated/derived clocks in RTL | Use a clock-gate cell from the library, or an enable. Never `assign gclk = clk & en`. |
| `casex` | Treats X in the *selector* as don't-care. Masks real X bugs. |
| `casez` without justification | Narrower than `casex` but still surprising. Prefer explicit `case` with `default`. |
| `full_case` / `parallel_case` pragmas | They tell the synthesis tool to assume what you have not proven, and simulation disagrees. This is a classic post-silicon escape. |
| Positional port connections | Silently wrong after any port reorder. |
| `$random`, `$display` in RTL | Testbench constructs. |
| Hierarchical references across modules | Unsynthesisable and destroys modularity. |
| Tri-state inside the chip | Only at true I/O pads. |

---

## 12. Maintainer-friendly practice

- One module, one responsibility. If the header needs "and", split it.
- Reuse a golden template rather than writing a fresh FIFO. The template has
  been reviewed and compiles; your fresh one has not.
- Keep a module small enough to hold in your head. Past roughly 500 lines, the
  next engineer stops reading and starts guessing.
- Make illegal states unrepresentable where you can: an `enum` beats a `logic
  [2:0]`, and a width-correct signal beats a comment asking people to be careful.
- Write the parameter assertion when you write the parameter, not after the bug.
