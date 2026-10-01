# Anti-patterns: Protocol, FIFO, arbitration

**Entirely `[reasoning]` tier.** No tool here detects deadlock, starvation or a
handshake violation. These share a signature: **they need sustained load or
backpressure to appear**, and directed tests rarely provide either.

---

## AP-PROTO-01 — `valid` depends combinationally on `ready`
**Severity: BLOCKER**

**Description.** A source asserts `valid` only when it sees `ready`.

```systemverilog
assign m_valid_o = has_data && m_ready_i;   // WRONG
```

**Root cause.** Inverts the contract. `ready` may depend on `valid`; `valid` must
never depend on `ready` (rule R4 in `golden_ready_valid.sv`).

**Symptoms.** Two failure modes, depending on the partner. Against a sink that waits
for `valid` before asserting `ready`: **permanent deadlock**, nothing ever transfers.
Against a sink whose `ready` depends on `valid`: **combinational loop**, simulation
hangs or oscillates. Either way the module passes its own unit test, where the
testbench drives `ready` unconditionally.

**Detection.** Trace `valid`'s expression. If `ready` appears anywhere in it, this is
the bug. This single check catches more integration failures than any other item in
this library.

**Auto-fix.** Make `valid` a function of internal state only. If you need to break
the path, insert `golden_register_slice.sv` — that is what a skid buffer is for.

---

## AP-PROTO-02 — Retracted `valid`
**Severity: HIGH**

**Description.** `valid` is asserted, the sink is not ready, and the source drops
`valid` anyway.

**Root cause.** Treating `valid` as "I have data right now" rather than as a promise
held until accepted (rule R2).

**Symptoms.** Lost beats under backpressure only. Data arrives short by a few entries,
with no error. Invisible in any test where the sink is always ready.

**Detection.** Once `valid` is asserted, is there any path that clears it other than
an accepted beat (`valid && ready`)? A `valid` driven directly from a
not-yet-registered source is the usual shape.

**Auto-fix.** Register the beat. Clear `valid` only on `valid && ready`. Both golden
handshake templates do this structurally.

---

## AP-PROTO-03 — Payload changes while stalled
**Severity: HIGH**

**Description.** Data changes while `valid` is high and `ready` is low.

**Root cause.** The payload is wired from a source that keeps advancing, instead of
from a register held for the duration of the beat (rule R3).

**Symptoms.** Corrupted data under backpressure only. The sink captures whatever was
present on the cycle it finally accepted, which may be a later value than the one
`valid` originally announced.

**Detection.** Is the payload registered and held, or does it come straight from
upstream logic? If `valid` is registered but data is not, this is the bug.

**Auto-fix.** Register the payload in the same `always_ff` as `valid` and update it
only on an accepted beat.

---

## AP-PROTO-04 — Circular wait
**Severity: BLOCKER**

**Description.** A waits for B while B waits for A, possibly through several hops.

**Root cause.** Each module's wait condition is locally reasonable. The cycle only
exists in the composition, so no block-level review sees it.

**Symptoms.** A hard hang reached by a specific sequence — usually an error, an abort,
or two requests arriving together. Found at system integration, or in the lab.

**Detection.** Build the wait-for graph across module boundaries: for each blocking
condition, name what makes it true and which module produces it. Any cycle is a
deadlock. Shared resources and error paths are where cycles hide.

**Auto-fix.** Break the cycle: impose an ordering, add a timeout with a defined
recovery, or decouple with a buffer. A timeout alone is a mitigation, not a fix — say
which you have applied.

---

## AP-PROTO-05 — Leaked credit or token
**Severity: HIGH**

**Description.** A credit-based flow control scheme loses or duplicates credits on
some path.

**Root cause.** The return path misses a case — a flushed transaction, an error
response, a dropped packet — so credits are consumed without being returned.

**Symptoms.** Throughput degrades slowly over hours until the link stops. Recovers
after a reset, which makes it look like a different problem entirely. Duplicated
credits are worse: silent buffer overflow and data corruption.

**Detection.** For every credit consumed, find **every** path that returns it,
including error, flush, abort and timeout paths. The invariant is
`credits_outstanding + credits_available == TOTAL`, always. Write it as an assertion.

**Auto-fix.** Add the missing return. Add the invariant as a concurrent assertion so
the next edit cannot break it quietly.

---

## AP-FIFO-01 — Pointers too narrow to tell full from empty
**Severity: BLOCKER**

**Description.** Pointers sized `$clog2(DEPTH)` instead of `$clog2(DEPTH)+1`.

**Root cause.** With only address bits, `wr_ptr == rd_ptr` means both "empty" and
"full" and the two are indistinguishable.

**Symptoms.** A FIFO that reports empty when full, so the producer overwrites unread
data; or reports full when empty and hangs. Either way, broken as soon as it wraps.

**Detection.** Pointer width must be `$clog2(DEPTH)+1`. Both golden FIFOs declare
`logic [ADDR_W:0]`, not `[ADDR_W-1:0]` — note the deliberate off-by-one.

**Auto-fix.** Widen by one bit; use the extra bit in the flag comparison
(`golden_fifo_sync.sv` shows the exact expressions).

---

## AP-FIFO-02 — Separate up/down count register
**Severity: HIGH**

**Description.** Occupancy kept in its own counter incremented on write and
decremented on read, in separate branches.

**Root cause.** A simultaneous read and write is handled by only one branch, or by
both in a way that nets out wrongly.

**Symptoms.** The level drifts from reality over time, so `full` and `empty`
eventually disagree with the pointers. Appears only after many simultaneous
read/write cycles — i.e. under real load.

**Detection.** Any FIFO with a `count` register that is not derived from the pointers.
Check the simultaneous case explicitly.

**Auto-fix.** Derive occupancy from the pointer difference —
`count_o = wr_ptr_q - rd_ptr_q` — so there is one source of truth that cannot drift
(see `golden_fifo_sync.sv`).

---

## AP-FIFO-03 — Unguarded write-when-full / read-when-empty
**Severity: HIGH**

**Description.** `wr_en_i` increments the pointer without checking `full_o`.

**Root cause.** Trusting the caller to honour the flags.

**Symptoms.** A write when full advances the write pointer past the read pointer, so
the FIFO reports **empty** while holding a full buffer of data, and the next read
returns stale entries. One protocol violation corrupts the FIFO permanently.

**Detection.** The pointer update condition must be `wr_en_i && !full_o`, not
`wr_en_i`. Both golden FIFOs use an explicit `do_write` / `do_read` term for exactly
this.

**Auto-fix.** Guard both pointers. Optionally add a sticky error flag so a caller
violation is observable rather than silently absorbed.

---

## AP-FIFO-04 — Non-power-of-two depth with wrap-by-truncation
**Severity: HIGH**

**Description.** `DEPTH = 12` in a FIFO whose pointers wrap by natural overflow.

**Root cause.** Truncating pointer arithmetic wraps at `2**ADDR_W`, not at `DEPTH`.
Gray coding additionally requires a power-of-two sequence.

**Symptoms.** Entries 12–15 addressed but never intended; flags wrong near the wrap;
in an async FIFO the gray comparison is simply invalid.

**Detection.** Any FIFO without a power-of-two assertion. Both golden FIFOs `$fatal`
at elaboration.

**Auto-fix.** Add the assertion and round the depth up. Supporting arbitrary depths
needs explicit modulo wrap and a different flag scheme — a different module, not a
tweak.

---

## AP-FIFO-05 — Flag computed in the wrong clock domain
**Severity: HIGH**

**Description.** In an async FIFO, `full` computed in the read domain or `empty` in the
write domain.

**Root cause.** Each flag must be computed where it is *conservative*. `full` in the
write domain uses a stale read pointer, so it says full slightly early — safe.
Computed in the read domain it would use a stale write pointer and say full slightly
**late** — overflow.

**Symptoms.** Rare overflow or underflow under sustained high rate, with a
frequency-ratio dependence. Corrupted data, no error.

**Detection.** `full` must be in an `always_ff @(posedge wr_clk)`, `empty` in
`@(posedge rd_clk)`. `golden_fifo_async.sv` separates them under banner comments so
this is visible at a glance.

**Auto-fix.** Move each flag into its own domain. Never export an exact occupancy from
an async FIFO — neither domain can know it.

---

## AP-ARB-01 — Priority encoder presented as round-robin
**Severity: HIGH**

**Description.** A plain lowest-index-wins priority encoder, documented or assumed to
be fair.

**Root cause.** Fixed priority is much easier to write, and looks identical in a code
read when the rotation state is absent or unused.

**Symptoms.** **Starvation.** Requester 0 asserting continuously means requester N-1
is never granted. Under light load every requester is served and all tests pass; under
sustained load the high-index agent times out. A canonical escape, because load tests
are usually last and often cut.

**Detection.** A real round-robin has **state** — a mask or pointer register that
advances with each grant. No state means no fairness. Then walk the wrap case by hand.

**Auto-fix.** Use `golden_rr_arbiter.sv`. Do not patch a priority encoder with a
rotation bolted on; the mask update and the wrap interaction are where the bugs are.

---

## AP-ARB-02 — Rotation advances on an unconsumed grant
**Severity: HIGH**

**Description.** The pointer advances every cycle a grant is asserted, whether or not
the grant was used.

**Root cause.** Missing the distinction between "granted" and "grant consumed".

**Symptoms.** The pointer races ahead of actual service, so agents are skipped and
fairness is lost — a round-robin that behaves randomly. Worse than fixed priority,
because it is not even predictable.

**Detection.** The pointer update must be gated on a consume signal.
`golden_rr_arbiter.sv` takes `update_i` explicitly for this reason.

**Auto-fix.** Gate the update on the downstream accept.

---

## AP-ARB-03 — Grant not one-hot
**Severity: HIGH**

**Description.** More than one grant can be asserted in the same cycle.

**Root cause.** Two priority paths OR-ed together instead of being mutually exclusive —
the usual shape when a masked and an unmasked result are combined.

**Symptoms.** Two masters drive the shared resource at once: bus contention, mixed
transactions, corrupted data.

**Detection.** Trace the construction. In `golden_rr_arbiter.sv` one-hotness is
structural — `lowest_one()` returns at most one bit, and the two paths are selected by
a mux, never OR-ed. Add `assert property ($onehot0(grant_o));`.

**Auto-fix.** Select between the two priority results with a mux, never an OR. Add the
one-hot assertion so a future edit cannot break it silently.
