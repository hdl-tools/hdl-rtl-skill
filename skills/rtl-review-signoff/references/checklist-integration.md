# Checklist: Integration — categories 15–17

---

## 15. Parameter Review

**Goal.** The module is correct at **every** legal parameter value, not just the
default it was written and tested with.

**Checks**
- For each parameter, write down its legal range and then evaluate the module at
  the **boundaries**, not the middle:
  - `WIDTH = 1` — does `[WIDTH-2:0]` still exist? It does not.
  - `DEPTH = 1`, `DEPTH = 2` — do the pointer comparisons still distinguish full
    from empty?
  - `N = 1` for an arbiter — is a one-entry mask still meaningful?
  - `STAGES = 1` for a synchroniser — that is no longer a synchroniser.
- Non-power-of-two values where the logic assumes binary wrap. Gray-coded FIFO
  pointers are **wrong** at depth 12.
- **Every assumption must be an elaboration-time assertion**, not a comment,
  and the `initial` block carrying it is guarded so it never becomes
  synthesised logic:
  ```systemverilog
  // synthesis translate_off
  initial begin
    if ((DEPTH & (DEPTH-1)) != 0)
      $fatal(1, "DEPTH must be a power of two (got %0d)", DEPTH);
  end
  // synthesis translate_on
  ```
  A comment saying "DEPTH must be a power of two" is not a check. Every golden
  template with a constraint asserts it this way.
- `parameter` vs `localparam`: anything **derived** must be `localparam`. A
  derived value left as a `parameter` can be overridden inconsistently with what
  it was derived from, and the module breaks in a way that compiles cleanly.
- Parameters are typed (`int unsigned`, `bit`, `logic [W-1:0]`). An untyped
  parameter inherits signedness from its literal.
- Overrides use named association (`#(.WIDTH(8))`), never positional.
- A parameter that changes the *interface* width is propagated to every port and
  every internal signal derived from it.

**Fails when** any legal parameter value produces an out-of-range select, a broken
flag, or a degenerate structure, and nothing refuses to elaborate.

**Severity** BLOCKER if a documented-legal value produces broken hardware. HIGH if
a plausible value does and there is no assertion. MEDIUM for a missing assertion on
a constraint that is currently respected by all callers.

**Fix** Add the guarded `initial`/`$fatal` assertion. Convert derived parameters
to `localparam`. Where the boundary case is genuinely unsupported, assert it out
rather than leaving it to be discovered.

---

## 16. Protocol Review

**Goal.** The interface obeys its contract in every ordering, including under
sustained backpressure — which directed tests almost never produce.

**Checks — ready/valid** (full contract in `golden_ready_valid.sv`)
- **R1** Transfer occurs only on `valid && ready` at a clock edge.
- **R2** `valid` is never retracted before the beat is accepted.
- **R3** Payload is stable while `valid && !ready`.
- **R4** `valid` does **not** depend combinationally on `ready`. `ready` may
  depend on `valid`. Violating this is how two individually-correct modules
  deadlock when connected, or form a combinational loop.
- **R5** Both deassert at reset, and no transfer occurs during reset.
- Throughput: trace a continuous `valid` into a continuous `ready` and count the
  beats. A one-deep stage gives 50%; only a skid buffer gives 100%
  (`golden_register_slice.sv`). A module documented as full throughput that is
  actually half is a HIGH finding.

**Checks — deadlock**
- Draw the dependency: does A wait on B while B waits on A? Any cycle in the
  wait-for graph is a deadlock.
- Credit/token schemes: are tokens ever created or destroyed on an error path? A
  leaked credit deadlocks the link hours into operation.
- Can a FIFO fill while the only drain is gated by something that needs the FIFO
  to drain?
- Timeout or recovery path for anything that can wait indefinitely.

**Checks — AXI / AHB / APB**
- AXI: the five channels are independent; `AWVALID` must not wait for `WVALID`.
  Write response only after the last beat. `BID`/`RID` must match the request.
  Burst must not cross a 4KB boundary. `WLAST` on the final beat exactly.
- AHB: `HREADY` timing, and `HRESP` error handling with the correct two-cycle
  response.
- APB: the setup/access phases, and `PREADY` wait states.
- For any standard bus, cite the specific rule you are checking. "Looks
  AXI-compliant" is not a review — name the clauses you verified.

**Checks — arbitration**
- Fairness: can a continuously asserting requester be starved? Walk the pointer
  update, including the wrap case (`golden_rr_arbiter.sv` documents this).
- Grant is one-hot. Prove it from the construction, not by inspection.
- The rotation advances only when a grant is **consumed**, not every cycle.

**Fails when** any contract rule is violated; a wait-for cycle exists; throughput
does not match the documented claim; a requester can starve.

**Severity** BLOCKER for a reachable deadlock or a `valid`-depends-on-`ready`
combinational loop. HIGH for starvation, retracted `valid`, unstable payload, or
throughput below the documented figure. MEDIUM for a missing timeout.

**Fix** Name the violated rule, then make the structural change. For R4, register
the signal (that is exactly what a register slice is for). For starvation, use the
golden arbiter rather than patching a priority encoder.

**`[reasoning]` tier throughout.** slang checks none of this.

---

## 17. Lint Review

**Goal.** Clean under a real ruleset, with every waiver justified.

**Checks**
- `bin/rtl-lint` run and quoted. **[slang]**
- Deeper run available on request: `/rtl-lint` (vcs) and `/rtl-cdc` (SpyGlass).
  If neither tool is installed, say so — do not imply a lint signoff that did not
  happen.
- No unused signals or ports **[slang: `-Wunused-port`,
  `-Wunused-but-set-variable`]**. An unused port usually means a missing
  connection, not harmless dead code.
- No undriven signals **[slang: `-Wunassigned-variable`]**.
- No implicit nets — `` `default_nettype none `` makes these hard errors.
- No unreachable code or constant-true conditions.
- Every waiver names the rule, the reason, and the reviewer. A blanket waiver file
  is not a justification.
- An **unclassified** slang warning is reported as MEDIUM and added to
  `hooks/slang-warnings.txt`. Never dropped because it is unfamiliar.

**Fails when** any finding has no justification; a waiver exists without a reason;
the tool was not actually run.

**Severity** Inherit from the severity map in `hooks/slang-warnings.txt`. Any
slang `severity: error` is BLOCKER regardless of option name.

**Fix** Fix the code, not the ruleset. Waive only with a written reason and a named
owner.
