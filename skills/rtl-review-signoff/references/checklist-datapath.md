# Checklist: Datapath — categories 11–14

Categories 11 and 12 are the strongest `[slang]` categories in the whole review:
quote the tool. Categories 13 and 14 are `[reasoning]` — slang does **not** detect
arithmetic overflow (verified: 8-bit + 8-bit assigned to 8 bits produces no
diagnostic at all).

---

## 11. Width Review

**Goal.** No bits lost, no bits invented, anywhere.

**Checks**
- `bin/rtl-lint` → `-Wwidth-trunc` (assignment) and `-Wport-width-trunc`
  (instance port). **[slang]**
- Every assignment: LHS width vs RHS width.
- Every instance port connection, in both directions.
- Concatenations: count the bits by hand and compare to the target.
- Replication counts are elaboration-time constants.
- Part-selects within bounds for **every** legal parameter value, not just the
  default. `x[ADDR_W-2:0]` is illegal when `ADDR_W == 1` — this is exactly why
  `golden_fifo_async.sv` asserts `DEPTH >= 4`.
- Shift amounts cannot exceed the operand width.
- Comparison operands the same width; the narrower is zero-extended, which is
  rarely what was meant when it was signed.
- Widths derived with `$clog2`, never hand-typed. A hand-typed `[3:0]` beside a
  `DEPTH` parameter is a bug waiting for the first depth change.
- Index widths: a `DEPTH`-entry memory needs `$clog2(DEPTH)` address bits, and the
  pointer that distinguishes full from empty needs one more.

**Fails when** slang reports either truncation warning; a part-select goes out of
range at any legal parameter value; a width is hand-typed where it should be
derived.

**Severity** HIGH for any truncation on a data or address path. BLOCKER if the
truncated value is an address or a count that controls memory access. MEDIUM for a
harmless widening that obscures intent.

**Fix** Resize explicitly and visibly — `WIDTH'(expr)`, or a concatenation with the
pad spelled out. If truncation is intended, say so in a comment *and* make it
explicit; an intentional truncation that looks accidental will be "fixed" by the
next engineer.

---

## 12. Signedness Review

**Goal.** Signed and unsigned never silently mix.

**Checks**
- `bin/rtl-lint` → `-Wsign-compare` and `-Warith-op-mismatch`. **[slang]**
- Any expression mixing a `signed` and an unsigned operand: in Verilog, **one
  unsigned operand makes the whole expression unsigned**, so a negative value
  becomes a large positive one. This is the mechanism behind most
  "the comparison is backwards" bugs.
- Comparisons: `-1 < 1` is false if either side is unsigned.
- Right shift: `>>` is logical, `>>>` is arithmetic. A signed value shifted with
  `>>` loses its sign.
- Parameters: an untyped `parameter WIDTH = 8` is **signed**, because the literal
  is a signed int. Type them: `parameter int unsigned WIDTH = 8`.
- Size casts: `WIDTH'(1)` is **signed** — the bare literal carries its signedness
  through the cast. Write `WIDTH'(1'b1)`. This cost a real debug cycle while
  building the golden templates; see `hooks/slang-warnings.txt`.
- `$signed()` / `$unsigned()` used deliberately, not scattered to silence a warning.

**Fails when** slang reports either option; a signed value is shifted with `>>`; an
untyped parameter participates in signed arithmetic.

**Severity** HIGH for a mixed-sign comparison or arithmetic on a real data path.
MEDIUM where the values are provably non-negative — but prove it, do not assume it.

**Fix** Make every operand explicitly the same signedness. Do not silence the
warning with a cast that changes the value; fix the declaration.

---

## 13. Arithmetic Review

**Goal.** Overflow, underflow and rounding are decided on purpose.

**`[reasoning]` tier — slang will not help you here.**

**Checks**
- Every `+`: can the true sum exceed the result width? An N-bit sum needs N+1
  bits. Either widen the result, or document that wrap is intended.
- Every `-`: can the result go negative? In unsigned arithmetic it wraps to a huge
  value. Guard it, or make the result signed.
- Every `*`: an N×M product needs N+M bits.
- Accumulators: what bounds the total over the longest sequence the spec allows?
  State the bound.
- Counters: wrap or saturate — a specification decision with no safe default.
  `golden_counter.sv` makes it an explicit parameter for exactly this reason.
- Division/modulo: power-of-two constants only, otherwise an explicit unit.
- Rounding: truncation (toward zero) vs round-half-up vs round-half-even. State
  which, and check the DC offset it introduces if the value feeds an analog path.
- Fixed point: track the binary point explicitly in signal names or comments. An
  undocumented Q-format is a guaranteed integration bug.
- Pointer arithmetic in FIFOs: the extra bit must be part of the arithmetic, not
  bolted on afterwards.

**Fails when** a sum, product or difference can exceed its result width under
inputs the spec permits, and neither widening nor a documented wrap exists.

**Severity** BLOCKER if overflow corrupts an address or a control value. HIGH for a
data-path overflow reachable with legal inputs. MEDIUM if reachable only outside
the specified input range — and say what that range is.

**Fix** Widen the intermediate result, then saturate or truncate explicitly at the
output. Show the width arithmetic in a comment:
`// 8b * 8b = 16b product, truncated to 12b after rounding`.

---

## 14. X/Z Review

**Goal.** Unknowns are visible in simulation and impossible in silicon.

**Checks**
- Every flop whose value is read before the first write has a reset.
- No `casex` — it treats X in the selector as don't-care and *hides* X bugs.
- No comparison against X or Z (`=== 1'bx`) in synthesisable code.
- No `full_case`/`parallel_case`: these make synthesis assume unreachability that
  simulation does not enforce, so an X that simulation propagates becomes a
  defined-but-wrong value in gates. A documented escape mechanism, not a theory.
- Tri-state only at a real pad; no internal `Z`.
- Uninitialised memory reads: the pointers must prevent reading an unwritten
  location (they do in both golden FIFOs — check yours).
- X-optimism: a `case` or mux may resolve X to a definite value in simulation while
  gates propagate it, or the reverse. Where this matters, add an assertion rather
  than relying on either behaviour.
- For bring-up: is there an observable that distinguishes "X propagated" from
  "logic computed zero"? If not, a lab failure is much harder to diagnose.

**Fails when** a flop is read before being written and has no reset; `casex`
appears; a pragma substitutes for logic.

**Severity** BLOCKER for X on a control path or an FSM state. HIGH for `casex` or a
pragma. MEDIUM for an unreset datapath flop whose valid bit *is* reset.

**Fix** Reset the flop, or gate every read on a reset valid bit. Replace `casex`
with explicit `case` plus `default`. Add an assertion where X-optimism matters.
