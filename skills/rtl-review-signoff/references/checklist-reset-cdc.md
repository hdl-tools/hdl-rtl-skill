# Checklist: Reset and CDC — categories 9–10

**Both categories are entirely `[reasoning]` tier.** slang performs no reset
analysis and no clock-domain analysis of any kind (verified by probe —
`hooks/slang-warnings.txt`). Every finding here must be labelled `UNVERIFIED`
unless an opt-in SpyGlass run (`/rtl-cdc`) backed it.

These two categories produce more post-silicon escapes than all the others
combined, because both failure modes are *intermittent* and both are invisible in
a functional simulation that happens to line the clocks up favourably.

---

## 9. Reset Review

**Goal.** Every flop comes up in a defined state, every domain leaves reset
safely, and no logic depends on reset timing that is not guaranteed.

**Checks**

*Polarity and style*
- Name matches polarity: `rst_n` is active low and used as `if (!rst_n)`. A
  signal named `rst_n` tested as `if (rst_n)` is a BLOCKER.
- One reset style per domain — do not mix async-assert and sync-only flops within
  a domain without a stated reason.
- Async assert / **sync de-assert** is the default correct choice:
  `always_ff @(posedge clk or negedge rst_n)`, with `rst_n` itself produced by a
  reset synchroniser in that domain.

*Release — the part that is usually missed*
- **Reset release must be synchronous to each domain's clock.** An async reset
  released near a clock edge violates the flop's recovery/removal time and
  different flops leave reset on different cycles. An FSM whose state bits leave
  reset one cycle apart starts in an illegal encoding.
- Each clock domain needs **its own** reset synchroniser. A single raw async reset
  fanned out to three domains releases at three unrelated times.
- Reset assertion must be long enough to cover every domain's slowest clock.
- **Reset-domain crossing:** a flop reset by domain A feeding a flop reset by
  domain B, where the two resets release independently, is a real failure mode —
  the receiver may latch data from a transmitter still in reset.

*Coverage and values*
- Every flop holding control state has a reset. Datapath flops may skip reset if
  their valid bit is reset — say so explicitly.
- Reset values are the specified idle state. A FIFO's `empty` must reset to **1**
  (see `golden_fifo_async.sv`); resetting it to 0 claims the FIFO holds data.
- Memory arrays deliberately **not** reset — and the pointers must make that safe.
- No logic in the reset path: `if (!rst_n && enable)` is a finding.

**Fails when** reset is released asynchronously into any domain; a domain has no
synchroniser; polarity contradicts the name; a control flop has no reset; a reset
value is not the specified idle state.

**Severity**
- BLOCKER — polarity inverted; FSM state has no reset; reset release
  unsynchronised in a domain containing an FSM.
- HIGH — missing reset synchroniser; reset-domain crossing; wrong reset value on
  a flag such as `empty`.
- MEDIUM — datapath flop without reset where the valid bit is reset (note it).
- LOW — inconsistent reset style with no functional consequence.

**Fix** Instantiate a reset synchroniser per domain (async assert, two-flop sync
de-assert). State in the module header, per domain: polarity, async/sync, and
release behaviour. If you cannot determine the reset architecture from the code
in front of you, that is `MANUAL_REVIEW_REQUIRED` — do not guess it.

---

## 10. CDC Review

**Goal.** Enumerate *every* clock-domain crossing by name and prove each one
structurally safe. "I looked and it seemed fine" is not a CDC review.

**Method — do this literally**
1. List every clock in the module.
2. For each signal, name the domain that drives it and every domain that reads it.
3. Any signal whose driver and reader domains differ **is a crossing**. Write it
   down by name. A crossing you did not list is a crossing you did not review.
4. For each listed crossing, name its mechanism and check it below.

**Checks by crossing type**

*Single control bit*
- Two-flop synchroniser minimum (`golden_sync_2ff.sv`), three for high MTBF or a
  large frequency ratio.
- **Nothing combinational between the stages.** Logic there re-opens the
  metastability window the second flop exists to close.
- The source must be stable for at least one destination clock period. A pulse
  shorter than that is simply lost — widen it in the source domain first
  (toggle + edge detect in the destination).

*Multi-bit — the dangerous one*
- **A bus through a 2-flop synchroniser is a BLOCKER.** The bits settle on
  different cycles and the destination samples a value that never existed in the
  source. This is the single most common CDC bug.
- Legal mechanisms, and only these: an async FIFO with gray-coded pointers
  (`golden_fifo_async.sv`); a req/ack handshake where the data is held stable
  until acknowledged; a gray-coded monotonic counter.
- **The gray-code exception:** a multi-bit 2-flop sync *is* correct for a
  gray-coded counter, because exactly one bit changes per increment, so the worst
  case is a stale-but-valid value. This exception applies only to gray-coded
  monotonic counters. Do not generalise it.

*Async FIFO specifics*
- Pointers gray coded, one extra bit for full/empty disambiguation.
- Exactly one synchroniser per direction, nothing between the flops.
- `full` computed in the **write** domain only; `empty` in the **read** domain
  only. Each flag belongs to the domain that can make it more conservative.
- No arithmetic on a synchronised pointer before it is compared.
- Occupancy is **not** exactly knowable in either domain. Any logic that needs an
  exact level is a bug.

*Structural*
- `ASYNC_REG` (or the flow's equivalent) on every synchroniser chain, so STA and
  the CDC checker both see it and retiming leaves it alone.
- A false-path or max-delay constraint exists for each crossing, or is called out
  as a required deliverable.
- No combinational logic converging from two domains into one cone — the output
  glitches regardless of synchronisers downstream.
- No reconvergence: two separately synchronised bits recombined in the
  destination domain arrive on different cycles, and the combination is wrong even
  though each bit individually is fine.

**Fails when** any crossing has no mechanism; a bus crosses through a plain
synchroniser; logic sits inside a synchroniser chain; separately synchronised
signals reconverge; a flag is computed in the wrong domain.

**Severity**
- BLOCKER — multi-bit bus through a 2-flop sync; no synchroniser at all;
  combinational convergence of two domains.
- HIGH — single flop instead of two; logic inside the chain; reconvergence of
  separately synchronised bits; pulse narrower than the destination period;
  flag computed in the wrong domain.
- MEDIUM — missing `ASYNC_REG`; missing STA constraint (note as a deliverable).
- INFO — crossing correct; mechanism recorded for the integrator.

**Fix** Replace the mechanism with the right one from the list above — do not try
to repair an unsafe crossing in place. For a bus, that means an async FIFO or a
handshake, not a third flop.

**Confidence rule.** If you cannot see every clock's source, or the module takes
clocks whose relationship is not documented, your CDC confidence is **below
threshold**: emit `MANUAL_REVIEW_REQUIRED` and list the specific unknowns. CDC is
the category where a confident wrong answer is most expensive — the bug ships,
passes every test, and fails at a customer.
