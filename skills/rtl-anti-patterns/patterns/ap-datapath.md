# Anti-patterns: Datapath — width, signedness, arithmetic

Width and signedness are the best tool-covered categories in this library.
Arithmetic is the opposite: **slang detects no overflow at all** (verified —
8-bit + 8-bit into 8 bits is silent). The split matters, because the first two
feel like the dangerous ones and the third actually is.

---

## AP-WIDTH-01 — Silent truncation on assignment
**Severity: HIGH** (BLOCKER on an address or control value) | **`[slang]`**
`-Wwidth-trunc`. Proven: `tests/bad/ap_width_trunc.sv`.

**Description.** RHS wider than LHS; the upper bits are discarded with no comment.

**Root cause.** Verilog truncates silently by design. A width changed at one end of
a path and not the other.

**Symptoms.** Values correct until they exceed the narrow width, then wrap. An
address that aliases to a lower location and overwrites live data. Passes small
tests, fails at scale — which is also when it is most expensive.

**Detection.** `bin/rtl-lint` → `-Wwidth-trunc`.

**Auto-fix.** Decide which width is right. If the narrow one is correct, make the
truncation explicit and comment why. If the wide one is, widen the LHS and
everything downstream. Never silence the warning with a cast that keeps the bug.

---

## AP-WIDTH-02 — Truncation at an instance port
**Severity: HIGH** | **`[slang]`** `-Wport-width-trunc`.
Proven: `tests/bad/ap_port_width_trunc.sv`.

**Description.** An instance port connection with mismatched widths.

**Root cause.** A submodule's parameter changed without updating the parent, or two
modules parameterised from different sources.

**Symptoms.** As AP-WIDTH-01, but harder to see because the two widths are in
different files. Especially common with positional port connections, which is why
the style guide forbids them.

**Detection.** `bin/rtl-lint` → `-Wport-width-trunc`.

**Auto-fix.** Parameterise both ends from a single source. Use named port
connections so a mismatch is at least visible in the diff.

---

## AP-WIDTH-03 — Hand-typed width beside a parameter
**Severity: MEDIUM**

**Description.** `logic [3:0] addr;` next to `parameter DEPTH = 16`.

**Root cause.** It was right when written. It is a time bomb set to the first depth
change.

**Symptoms.** Changing `DEPTH` to 32 produces a FIFO that addresses only the first
16 entries and silently overwrites. No warning, because `[3:0]` is still legal.

**Detection.** Any literal bit range in a parameterised module. It should be
`$clog2(DEPTH)` or a `localparam` derived from it.

**Auto-fix.** `localparam int unsigned ADDR_W = $clog2(DEPTH);` then
`logic [ADDR_W-1:0] addr;`.

---

## AP-SIGN-01 — Signed compared against unsigned
**Severity: HIGH** | **`[slang]`** `-Wsign-compare`.
Proven: `tests/bad/ap_sign_compare.sv`.

**Description.** A comparison or arithmetic expression with one signed and one
unsigned operand.

**Root cause.** Verilog's rule: **if any operand is unsigned, the whole expression
is evaluated unsigned.** A signed `-1` becomes `255` in 8 bits, so `-1 < 1` is false.

**Symptoms.** A comparison that is backwards only for negative inputs. A saturation
limiter that clamps the wrong side. A signed threshold that never triggers.

**Detection.** `bin/rtl-lint` → `-Wsign-compare`, `-Warith-op-mismatch`.

**Auto-fix.** Make every operand the same signedness. If the value is genuinely
signed, declare every signal in the expression `signed`. Do not wrap it in
`$unsigned()` to quiet the tool — that preserves the bug and hides the evidence.

---

## AP-SIGN-02 — Untyped parameter is signed
**Severity: HIGH**

**Description.** `parameter WIDTH = 8;` — this is a **signed** `int`.

**Root cause.** An untyped parameter takes its type from its default value, and the
literal `8` is a signed integer.

**Symptoms.** Any arithmetic mixing `WIDTH` with an unsigned signal becomes a
signed-vs-unsigned expression (AP-SIGN-01) from a source that looks like a constant,
not an operand. Hard to spot because `WIDTH` does not look like data.

**Detection.** Every `parameter` in the module has an explicit type. Untyped is a
finding even when currently harmless.

**Auto-fix.** `parameter int unsigned WIDTH = 8;`

---

## AP-SIGN-03 — Size-cast of a bare literal is signed
**Severity: HIGH** | **`[slang]`** `-Warith-op-mismatch`

**Description.** `WIDTH'(1)` is signed, because the cast preserves the literal's
signedness.

```systemverilog
count_d = count_q + WIDTH'(1);      // WRONG -- warns, and sign-extends
count_d = count_q + WIDTH'(1'b1);   // right
```

**Root cause.** The size cast changes the width, not the signedness.

**Symptoms.** `-Warith-op-mismatch`, and on wide or signed targets an actual
sign-extension bug.

**Detection.** `bin/rtl-lint` → `-Warith-op-mismatch`. **This one cost a real debug
cycle while writing `golden_counter.sv`** and is recorded in
`hooks/slang-warnings.txt` for that reason.

**Auto-fix.** `WIDTH'(1'b1)`, or `{{(WIDTH-1){1'b0}}, 1'b1}`.

---

## AP-ARITH-01 — Sum overflows its result width
**Severity: HIGH** (BLOCKER on an address or control value) | **`[reasoning]`**

**Description.** Two N-bit values added into an N-bit result.

```systemverilog
logic [7:0] a_i, b_i, sum_o;
assign sum_o = a_i + b_i;    // true sum needs 9 bits. SILENT.
```

**Root cause.** An N-bit sum requires N+1 bits. Verilog wraps modulo 2**N without
comment.

**Symptoms.** Correct for small inputs, wraps for large ones. An accumulator that
resets itself. A length field that wraps so a packet is parsed as tiny. A classic
post-silicon escape, because directed tests use small numbers.

**Detection.** **No tool here will tell you.** For every `+`, state the maximum
magnitude of each operand under the spec, add them, and compare against the result
width. Verified: slang reports nothing for this.

**Auto-fix.** Widen the result (`logic [8:0] sum_o;`) and saturate or truncate
explicitly at the output. If wrap is intended, say so in a comment — otherwise the
next reviewer files this bug again.

---

## AP-ARITH-02 — Unsigned subtraction underflows
**Severity: HIGH** | **`[reasoning]`**

**Description.** `a - b` where `b > a` and both are unsigned.

**Root cause.** Unsigned subtraction wraps to a very large value rather than going
negative.

**Symptoms.** A FIFO level of 255 when it should be -1 (i.e. empty). A "remaining
bytes" count that jumps to maximum and drives an enormous burst. Frequently the
cause of a runaway transfer.

**Detection.** For every `-`, ask whether the result can go negative. In FIFO
occupancy, credit counters and "remaining" calculations the answer is usually yes.

**Auto-fix.** Guard it (`(a >= b) ? a - b : '0`), or make both operands signed with
one extra bit and clamp. Two's-complement pointer arithmetic (as in
`golden_fifo_sync.sv`'s `count_o = wr_ptr_q - rd_ptr_q`) is correct **only** because
the pointers carry the extra bit and wrap consistently — say so where you rely on it.

---

## AP-ARITH-03 — Unbounded accumulator
**Severity: HIGH** | **`[reasoning]`**

**Description.** An accumulator with no stated bound on the number of accumulations.

**Root cause.** The width was chosen for a typical case. The spec permits a longer
sequence.

**Symptoms.** Works in short tests, overflows in a long run — hours into operation,
or on the largest packet size. An averaging filter whose output goes catastrophically
wrong once per long interval.

**Detection.** For every accumulator, find the stated maximum sequence length and
compute the worst-case total. If the spec does not bound it, that is itself the
finding: `MANUAL_REVIEW_REQUIRED` with the question stated.

**Auto-fix.** Size for the worst case, or saturate and expose a sticky overflow status
bit so the condition is observable instead of silent.
