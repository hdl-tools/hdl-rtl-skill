# Anti-patterns: Clock domain crossing

**Every entry here is `[reasoning]` tier.** slang performs no clock-domain
analysis of any kind (verified). These bugs are found by review or by an opt-in
SpyGlass CDC run (`/rtl-cdc`) — never by the default gate.

CDC bugs share a signature that makes them uniquely expensive: they are
*probabilistic*. The design passes every simulation, passes bring-up, and fails at
a customer months later at a rate of once per billion cycles. Treat every finding
here as more serious than its severity suggests.

---

## AP-CDC-01 — Multi-bit bus through a 2-flop synchroniser
**Severity: BLOCKER** | The single most common CDC bug.

**Description.** A multi-bit signal is passed through a per-bit two-flop
synchroniser and used as a value in the destination domain.

```systemverilog
// WRONG
always_ff @(posedge dst_clk) begin
  count_sync1_q <= src_count_q;   // 8 bits, all changing independently
  count_sync_q  <= count_sync1_q;
end
```

**Root cause.** Each bit's setup relationship to the destination clock is
independent. When the source changes `0111` → `1000`, four bits change at once;
each one independently resolves to old or new. The destination can sample `1111`,
`0000`, or any of the other 14 combinations — **values that never existed in the
source domain**.

**Symptoms.** Passes every simulation (which has no metastability model).
Occasional impossible values — a FIFO level above its depth, an address outside
the map, a length field of zero. Rate scales with the frequency ratio. Often first
seen as "data corruption" chased in the wrong block entirely.

**Detection.** List every signal wider than one bit whose driver and reader clocks
differ. For each, name the mechanism. If the mechanism is "a synchroniser", this is
the bug. The `_sync1_q`/`_sync_q` naming pattern on a vector is the visual tell.

**Auto-fix.** **Do not add flops.** Replace the mechanism:
- Streaming data → async FIFO (`golden_fifo_async.sv`).
- Occasional value → req/ack handshake, data held stable until acknowledged.
- Monotonic counter → gray code it, then a vector synchroniser *is* correct.

**Why gray code is the exception.** One bit changes per increment, so the worst
case is sampling one increment stale — a valid value, and always conservative.
This applies only to gray-coded monotonic counters.

---

## AP-CDC-02 — No synchroniser at all
**Severity: BLOCKER**

**Description.** An asynchronous input is used directly in logic, or registered
once and used.

**Root cause.** A single flop sampling an unrelated signal can go metastable; its
output is undefined for an unbounded time. Fanning that output to several loads
means different loads see different values from the same flop.

**Symptoms.** Rare unexplained state corruption. An FSM in a state no transition
can reach. Failures correlated with temperature or voltage — the classic
metastability signature, because the resolution time constant shifts.

**Detection.** Trace every module input back: is it in this clock's domain? Inputs
from a pad, a different block, or a configuration register in another domain all
need synchronising. A single `always_ff` stage on an async input is this bug.

**Auto-fix.** Insert `golden_sync_2ff.sv` (3 stages if the ratio is large). If the
payload is multi-bit, this becomes AP-CDC-01 — use a FIFO or handshake.

---

## AP-CDC-03 — Combinational logic inside the synchroniser chain
**Severity: HIGH**

**Description.** Logic between the two flops.

```systemverilog
// WRONG
sync1_q <= async_in;
sync_q  <= sync1_q & enable;    // logic between the stages
```

**Root cause.** The second flop exists to give the first flop's metastable output a
full clock period to resolve. Inserting logic consumes that budget, so the second
flop can itself go metastable. You have paid for two flops and bought one.

**Symptoms.** Identical to having one flop: rare, temperature-dependent
corruption. Easy to miss in review because the chain *looks* like two stages.

**Detection.** For each synchroniser, confirm stage N's input is *only* stage N-1's
output. Any operator between them is the bug. `golden_sync_2ff.sv` uses a shift
register specifically so this is structurally impossible.

**Auto-fix.** Move the logic after the final stage: `assign out = sync_q & enable;`.

---

## AP-CDC-04 — Reconvergence of separately synchronised bits
**Severity: HIGH**

**Description.** Two related signals are synchronised through separate chains and
then combined in the destination domain.

```systemverilog
// WRONG -- req and addr_valid are related, synchronised separately
sync_2ff u_a (.d(req),        .q(req_s));
sync_2ff u_b (.d(addr_valid), .q(addr_valid_s));
assign start = req_s && addr_valid_s;   // arrive on different cycles
```

**Root cause.** Each chain independently resolves to old or new, so two signals
that changed in the same source cycle can arrive one destination cycle apart. Each
synchroniser is individually correct; the *combination* is wrong. This is why
AP-CDC-01 cannot be fixed by "synchronising each bit properly".

**Symptoms.** A one-cycle glitch on the combined signal. Spurious triggers.
Intermittent, load-dependent, and invisible when you probe either input alone.

**Detection.** For each synchronised signal, find where it is used. If two
synchronised signals meet in one expression, and they are functionally related,
this is the bug.

**Auto-fix.** Synchronise **one** signal and derive the rest from it in the
destination domain: cross a single `req` and have the receiver read the data only
after `req_s` is seen. Or use a FIFO so the whole payload crosses atomically.

---

## AP-CDC-05 — Pulse narrower than the destination clock period
**Severity: HIGH**

**Description.** A single-cycle pulse from a fast domain is synchronised into a
slow domain.

**Root cause.** The destination samples on its own edges. A pulse shorter than one
destination period can fall entirely between two edges and is simply never seen.
The synchroniser is correct; the pulse was never there to sample.

**Symptoms.** Lost events, not corrupted ones. An interrupt that occasionally does
not fire; a counter that misses increments. Rate depends on the frequency ratio, so
it disappears when someone changes a clock for debug.

**Detection.** For every pulse crossing a domain, compare the source pulse width
against the destination clock period. Any pulse not guaranteed to span at least
one destination period is this bug. Dangerous in both directions if either clock
can be reconfigured.

**Auto-fix.** Convert the pulse to a level change in the source domain — toggle a
flop on each event — synchronise the toggle, then edge-detect it in the
destination. For a stream of events, use a FIFO; a toggle handshake drops events
that arrive faster than the destination can consume.

---

## AP-CDC-06 — Binary counter crossing a domain
**Severity: BLOCKER** | A specialisation of AP-CDC-01, listed separately because it
appears in otherwise careful FIFO code.

**Description.** FIFO pointers, or any counter, synchronised as binary.

**Root cause.** Binary increment changes multiple bits. `0111` → `1000` changes
four. The destination can read any of 16 values, so `full` or `empty` can be
computed from a pointer that never existed.

**Symptoms.** An async FIFO that very rarely reports full when it is nearly empty,
or empty when it holds data — producing either a hang or silent overwriting.
Typically found after months in the field.

**Detection.** In any dual-clock FIFO, confirm the pointer registered into the
synchroniser is the **gray** one, not the binary one. Both exist in a correct
design (`golden_fifo_async.sv` keeps `wr_bin_q` for addressing and `wr_gray_q` for
crossing) and it is easy to wire the wrong one.

**Auto-fix.** Maintain both: binary for memory addressing, gray for crossing.
`gray = bin ^ (bin >> 1)`. Cross the gray version only, and compare in gray space
— never convert back and do arithmetic.
