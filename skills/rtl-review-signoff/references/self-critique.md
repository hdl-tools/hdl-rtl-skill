# Mandatory self-critique

Answer **all eleven** before any approval. Not a formality — this hook exists
because the failure mode it guards against is specific and well documented: once
a model has produced an answer, it defends that answer. Asking the questions
explicitly, in a separate pass, is what breaks the commitment.

**Rules**
- Answer every question. "Probably not" is not an answer — YES or NO.
- Every **YES** requires four lines: **Risk / Impact / Severity / Mitigation.**
- A NO must name its evidence: a tool result, or the specific construct that makes
  it impossible. "I don't think so" is a YES you have not investigated.
- Answer about the code in front of you, not about the pattern you intended.

---

### Q1 — Can this infer latches?
NO requires: `bin/rtl-lint` clean of `-Winferred-latch`, **and** that the lint ran
with full elaboration (`--lint-only` does not detect latches). Also check every
combinational block assigns its outputs a default on entry.

### Q2 — Can this create CDC issues?
Enumerate every clock. If there is exactly one clock and no asynchronous input,
NO. Otherwise list each crossing by name and its mechanism. A multi-bit crossing
through anything other than an async FIFO, a handshake, or a gray-coded counter is
an automatic YES at BLOCKER.
*No tool checked this. A NO here is `[reasoning]` and must say so.*

### Q3 — Can this truncate data?
NO requires `-Wwidth-trunc` and `-Wport-width-trunc` both clean. Then check by
hand the places slang cannot see: concatenation widths, and part-selects at
**boundary parameter values**, not just defaults.

### Q4 — Can signedness be incorrect?
NO requires `-Wsign-compare` and `-Warith-op-mismatch` clean, **plus**: no untyped
parameters feeding arithmetic, no `>>` on a signed value, no size-cast of a bare
integer literal (`WIDTH'(1)` is signed).

### Q5 — Can overflow occur?
**slang cannot answer this** — verified, an 8+8 sum into 8 bits is silent. So a NO
must be derived by hand: for every `+`, `-`, `*` and accumulator, state the
maximum magnitude the spec permits and compare it to the result width. If wrap is
intended, say so and confirm it is documented in the RTL.

### Q6 — Can reset sequencing fail?
Per clock domain, state: polarity, async or sync assert, and **how release is
synchronised**. A domain whose reset release you cannot account for is a YES. Also
check: any flop reset by one domain feeding a flop reset by another
(reset-domain crossing).

### Q7 — Can simulation differ from synthesis?
Check each: blocking `=` in a clocked block (**slang will not catch it**); an
explicit sensitivity list that may be incomplete; `casex`;
`full_case`/`parallel_case`; `initial` driving logic; `#delay`; X-optimism in a mux
or case. Any one present is a YES.

### Q8 — Can protocol deadlock occur?
Draw the wait-for graph. Any cycle is a YES. Specifically check R4 — `valid` must
not depend combinationally on `ready` — because two modules that each violate it
deadlock only once connected, which is after block-level signoff.

### Q9 — Can arbitration starve?
If there is no arbitration, NO. Otherwise walk the pointer or mask update by hand
including the **wrap** case, and confirm a continuously asserting requester is
granted within N grants. A priority encoder presented as round-robin is a YES.

### Q10 — Can parameters break edge cases?
Evaluate at the boundaries: `WIDTH=1`, `DEPTH=1`, `DEPTH=2`, `N=1`, `STAGES=1`, and
a non-power-of-two depth. Any value that produces an out-of-range select or a
degenerate structure **without an elaboration assertion that refuses it** is a YES.

### Q11 — Can corner cases fail?
The ones that are never in a directed test:
- Simultaneous events — load and increment, read and write when empty, flush and
  enable, full and empty together.
- First cycle out of reset.
- Sustained backpressure (`ready` low for many cycles).
- Maximum-rate input with no gaps.
- An input deasserting mid-transaction.
- Clock ratios at both extremes for multi-clock blocks.

---

## Output format

```
SELF-CRITIQUE
Q1  latches ......... NO   [slang] -Winferred-latch clean, full elaboration
Q2  CDC ............. NO   single clock domain, no async inputs
Q3  truncation ...... NO   [slang] width-trunc + port-width-trunc clean
Q4  signedness ...... YES
      Risk:       WIDTH'(1) is signed; added to an unsigned count_q
      Impact:     -Warith-op-mismatch; sign-extension on a wide parameter
      Severity:   HIGH
      Mitigation: use WIDTH'(1'b1)
Q5  overflow ........ YES
      Risk:       count_q + 1 at MAX_COUNT wraps
      Impact:     address wraps to 0, overwrites live data
      Severity:   BLOCKER
      Mitigation: SATURATE parameter, explicitly chosen per spec
Q6  reset .......... NO   single domain, async assert + sync release via u_rst_sync
...
```

**If every answer is NO on the first pass, you have not done the pass.**
Go back and name the evidence for each one. The expected outcome on real RTL is
two to four YES answers — that is the hook working, not the design failing.
