# Anti-patterns: Reset

All `[reasoning]` tier — slang performs no reset analysis. Reset bugs have a
characteristic signature: **the design works once it is running.** Everything
fails at bring-up or after a reset event, which is why they are so often found on
the bench rather than in simulation.

---

## AP-RST-01 — Polarity contradicts the name
**Severity: BLOCKER**

**Description.** `if (rst_n)` applying reset, or `if (!rst)` where `rst` is active
high.

**Root cause.** A name says one thing and the code does the other. Usually from
porting a block between projects with opposite conventions.

**Symptoms.** Permanently held in reset (dead block, no activity at all), or never
reset (random power-up state, non-deterministic boot). Both are immediately
obvious at bring-up — this one is cheap to find and catastrophic to miss.

**Detection.** For every reset, match name to use: `rst_n` → `if (!rst_n)`;
`rst` → `if (rst)`. Also check the edge: `negedge rst_n` / `posedge rst`.

**Auto-fix.** Fix the usage, not the name — the name is the interface contract.

---

## AP-RST-02 — No reset on FSM state
**Severity: BLOCKER**

**Description.** `state_q` has no reset branch, or the reset branch is missing from
one of several state bits.

**Root cause.** Treating state like datapath, where skipping reset is sometimes
legitimate. It never is for state.

**Symptoms.** Non-deterministic boot. In simulation, state is X and the FSM may
never leave `default`. In silicon it powers up to an arbitrary encoding — possibly
illegal — and if `default` does not recover (AP-FSM-01), the block is dead until
power cycle.

**Detection.** Every `always_ff` holding FSM state has a reset branch assigning a
named idle state. Partial reset of a multi-bit state register is the subtle variant.

**Auto-fix.** `if (!rst_n) state_q <= ST_IDLE;`

---

## AP-RST-03 — Unsynchronised async reset release
**Severity: HIGH** | The reset bug that survives review most often.

**Description.** A raw asynchronous reset is connected directly to flops with no
synchroniser, so its **de-assertion** is asynchronous to the clock.

```systemverilog
// WRONG -- rst_n_async comes straight from a pad
always_ff @(posedge clk or negedge rst_n_async) ...
```

**Root cause.** Assertion can be asynchronous safely — that is the point of an
async reset. **Release cannot.** If reset de-asserts near a clock edge it violates
the flop's recovery/removal time, and different flops (different paths, different
delays) leave reset on *different cycles*.

**Symptoms.** Intermittent bad startup, maybe one boot in a thousand. An FSM whose
state bits leave reset one cycle apart starts in an illegal encoding. Often
"fixed" by an unrelated change that shifts the reset path delay, then returns
after a P&R run.

**Detection.** Trace each reset back to its source. If it comes from a pad, a PLL
lock, or another domain and reaches flops without passing through a reset
synchroniser, this is the bug. Look for a `rst_sync` instance per domain — its
absence is the tell.

**Auto-fix.** Insert a reset synchroniser per domain: async assert, two-flop
synchronous de-assert.

```systemverilog
always_ff @(posedge clk or negedge rst_n_async) begin
  if (!rst_n_async) rst_sync_q <= 2'b00;
  else              rst_sync_q <= {rst_sync_q[0], 1'b1};
end
assign rst_n = rst_sync_q[1];   // async assert, sync release
```

---

## AP-RST-04 — One raw reset fanned out to several domains
**Severity: HIGH**

**Description.** A single async reset drives flops in two or more clock domains
with no per-domain synchroniser.

**Root cause.** Each domain's release timing is independent of the others. Domain A
may start running several of its cycles before domain B.

**Symptoms.** CDC-looking failures only at startup. A FIFO whose write side comes
up first and writes before the read side initialises its pointer — then both report
plausible but inconsistent state.

**Detection.** Count clock domains, count reset synchronisers. These must match.
`golden_fifo_async.sv` takes `wr_rst_n` and `rd_rst_n` separately precisely to make
this visible at the interface.

**Auto-fix.** One reset synchroniser per domain, each clocked by its own clock,
all fed from the common async reset.

---

## AP-RST-05 — Reset-domain crossing
**Severity: HIGH**

**Description.** A flop reset by reset A drives a flop reset by reset B, and the two
releases are independent.

**Root cause.** The receiving flop can leave reset while the transmitter is still
held, so it latches whatever the reset value happens to be, treating it as data.
Conversely the transmitter can run while the receiver is still reset, losing beats.

**Symptoms.** Startup-only data corruption or lost transactions. Disappears after
the first few cycles, so it is easy to dismiss as a testbench artefact.

**Detection.** Map each flop to its reset. Any signal crossing from one reset domain
to another needs either a shared reset, an ordered release, or a valid bit that is
reset in the receiver's domain.

**Auto-fix.** Prefer a single reset domain where the clocks allow. Otherwise gate
the receiver's capture on a valid bit reset in the receiver's own domain, or
sequence the releases explicitly and document the required order.

---

## AP-RST-06 — Logic in the reset path
**Severity: MEDIUM** (BLOCKER if it makes reset uncontrollable in test mode)

**Description.** `if (!rst_n && enable)`, or a reset built from combinational logic.

**Root cause.** Reset becomes a data-dependent signal. It can glitch, it is slow,
and it is not controllable during scan shift — which also makes it a DFT blocker.

**Symptoms.** Blocks that occasionally fail to reset. Scan chains that will not
shift because reset cannot be held inactive.

**Detection.** The reset expression in every `always_ff` must be exactly the reset
signal, nothing else. Any `&&`, `||` or function call there is the bug.

**Auto-fix.** Move the condition into the synchronous body:
`if (!rst_n) q <= '0; else if (enable) q <= d;`

---

## AP-RST-07 — Wrong reset value on a status flag
**Severity: HIGH**

**Description.** A flag resets to a value that claims a state the hardware is not in.

**Root cause.** Resetting everything to zero as a reflex. For `empty`, zero means
"this FIFO holds data" — a lie immediately after reset.

**Symptoms.** A consumer reads a FIFO on the first cycle after reset and gets
garbage from uninitialised memory. Or `full` resets high and the producer never
writes.

**Detection.** For every status output, ask what the value means and whether it is
true at reset. `empty` → 1. `full` → 0. `busy` → 0. `ready` → depends on the
protocol, so state it. `golden_fifo_async.sv` resets `rd_empty_o` to 1 and says so.

**Auto-fix.** Set each reset value to the genuine idle condition, and comment the
non-obvious ones.
