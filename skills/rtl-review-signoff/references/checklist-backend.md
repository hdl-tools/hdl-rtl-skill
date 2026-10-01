# Checklist: Backend and maintenance — categories 18–20

---

## 18. DFT Review

**Goal.** Every flop is controllable and observable on the scan chain, and nothing
in the RTL blocks test.

**Checks**
- **No RTL-generated clocks.** `assign gclk = clk & en;` is the classic DFT
  blocker: the gated flops are unreachable in scan mode. Use an enable on the
  flop, or an instantiated library clock-gate cell with a test-enable input.
- Every clock-gating cell has a `test_en` (or `scan_en`) OR-ed into its enable.
- **Async resets must be controllable in test mode.** A reset driven by internal
  logic cannot be held inactive during scan shift, so the chain cannot shift.
  Provide a `scan_mode` bypass to the top-level reset.
- No internally generated asynchronous set/reset on a flop from combinational
  logic.
- No latches — they need extra DFT handling (transparent-latch mode) and often a
  separate chain.
- No combinational feedback loops; ATPG cannot model them.
- No tri-state inside the chip; bus contention is untestable.
- Memories need a bypass path or a BIST wrapper, and the FIFO memory array is a
  memory.
- Black boxes and analog interfaces need a defined test-mode behaviour.
- Lockup latches / clock-domain handling at chain boundaries where a chain spans
  two domains.

**Fails when** a clock or async reset is generated from internal logic with no
test-mode override; a latch or combinational loop is present; a memory has no
bypass.

**Severity** BLOCKER for an RTL-generated clock with no test bypass. HIGH for an
uncontrollable async reset or an unintended latch. MEDIUM for a missing memory
bypass (usually handled at integration — note it as a deliverable).

**Fix** Replace generated clocks with enables or library gate cells with
`test_en`. Add a `scan_mode` input that forces resets inactive and makes clocks
directly driven.

---

## 19. Power Review

**Goal.** Nothing toggles when nothing is happening.

**Checks**
- Datapath flops that load unconditionally every cycle. Gate the load on the
  valid bit. `golden_pipeline_stage.sv` only updates `data_q_o` when `valid_i` —
  that is free clock gating for the synthesis tool.
- Wide buses that toggle while their valid bit is low. The downstream logic
  ignores the value but the wires still burn power.
- Clock enables coarse enough for the tool to infer a clock gate. Per-bit enables
  on a 256-bit register produce 256 gates instead of one.
- Counters and LFSRs that run when nothing consumes them.
- A combinational block whose output is used only under a condition, but which
  evaluates unconditionally — gate the inputs if it is large.
- Memories: is the enable asserted only on a real access? A RAM with a
  permanently asserted enable is often the largest single power consumer.
- Isolation and retention requirements if the block sits in a switchable power
  domain — state them, and note the UPF implications.
- Reset values chosen so the common idle state is all-zeros where that reduces
  switching into the next stage.

**Fails when** a wide register loads every cycle regardless of validity; a memory
enable is permanently asserted; a large block evaluates when its result is unused.

**Severity** HIGH for a memory enable always asserted, or a wide datapath
toggling continuously in idle. MEDIUM for missing load gating on a narrow
register. LOW for a missed micro-optimisation. INFO for a noted UPF deliverable.

**Fix** Add the enable condition to the `always_ff`. Keep the enable coarse (one
per register, not per bit) so the tool can infer a single clock gate.

---

## 20. Maintainability Review

**Goal.** The next engineer — including you in six months — can change this
safely.

**Checks**
- Module header states purpose and the contract it assumes of its caller.
- Naming follows `rtl-style-guide` — `_q`/`_d` present, so a reader can tell
  registered state from combinational next-state at a glance.
- No magic numbers. Every constant is a named `localparam` or has a comment
  saying where it came from.
- Widths derived (`$clog2`), never hand-typed.
- One responsibility per module. If the header needs "and", split it.
- Module length: past roughly 500 lines the next reader stops reading and starts
  guessing.
- Dead code removed, not commented out. Version control remembers it.
- No copy-pasted blocks that should be a `generate` loop, and no `generate` loop
  obscuring two genuinely different cases.
- Comments explain **why**. `count_q <= count_q + 1; // increment` is noise;
  `// wrap not saturate: the spec requires a modulo-N address` is not.
- Every deliberate deviation from the style guide is commented with its reason —
  otherwise it gets "fixed" back into the bug it was avoiding.
- Unused ports and signals removed **[slang: `-Wunused-port`,
  `-Wunused-but-set-variable`]**.
- **Reuse check:** does a golden template already do this? A hand-written FIFO
  where `golden_fifo_sync.sv` would serve is a finding — the template is reviewed
  and compiles; the new one is neither.

**Fails when** a reader cannot determine intent without the author; magic numbers
control behaviour; the module does several unrelated things.

**Severity** Normally LOW or INFO. MEDIUM when the unclarity is likely to cause a
future bug — an undocumented Q-format, an unexplained `-1` in an index, a
deviation from the style guide with no stated reason. Never BLOCKER.

**Fix** Name the constant. Write the why-comment. Split the module. Replace the
hand-rolled block with the golden template.
