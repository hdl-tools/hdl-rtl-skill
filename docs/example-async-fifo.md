# End-to-end example: "Create a parameterized asynchronous FIFO"

Every tool output below is **real**, captured from this repository on this machine with
`slang 9.0.0+54385bb`. Nothing here is illustrative.

---

## Stage 1 — Trigger detection

Request: `Create a parameterized asynchronous FIFO`

```
contains_explicit_rtl_keywords()  -> "FIFO" is an implicit RTL concept   +0.15
contains_implicit_rtl_concepts()  -> "asynchronous FIFO" -> CDC          +0.15
contains_module_definition()      -> no (generation, not review)          0.00
files involved                    -> will create .sv                    +0.50
is_testbench_only()               -> no                                   0.00
                                                              ------------------
                                                      confidence = 0.80
```

`>= 0.70` → **full workflow**, mandatory gate.

Three additional triggers fire on the word *asynchronous*:
- implicit trigger `cdc`
- implicit trigger `clock domain`
- retrieval rule: *"async fifo" → async FIFO template **+** synchroniser template **+**
  CDC checklist **+** `ap-cdc.md`*

And one requirement is immediately **missing**: *parameterized* over what? `WIDTH` and
`DEPTH` are the obvious reading. That assumption gets written down, not silently taken.

## Stage 2 — Context injection

| Priority | Injected | Why |
|---|---|---|
| 1 | `rtl-style-guide/SKILL.md` | Any generation. |
| 2 | `golden_fifo_async.sv` | Exact name match, score 3+2+2 = 7. |
| 2 | `golden_sync_2ff.sv` | Retrieval rule for async FIFO, score 5. |
| 4 | `checklist-reset-cdc.md` | CDC + two reset domains. |
| 5 | `ap-cdc.md` | Matched anti-pattern file. |
| 6 | `self-critique.md` | Before any approval. |

Within limits: 2 templates (cap 3), 1 anti-pattern file (cap 2).

## Stage 3 — Template retrieval

```
score = 3*exact_name_match + 2*structural_match + 2*risk_category_match + keyword_overlap

golden_fifo_async.sv   3 ("async fifo") + 2 (two clocks, multi-bit) + 2 (CDC) = 7   RETRIEVE
golden_sync_2ff.sv     0               + 2 (CDC primitive)         + 2       = 4+   RETRIEVE (rule)
golden_fifo_sync.sv    0               + 0 (wrong structure)       + 0       = 1    reject
```

Conflict resolution rule 1 — *structure beats wording* — is what matters here. Had the
request said "a FIFO between two clocks" with no "async", the structural match alone
still selects the async template. The physics does not care about the wording.

## Stage 4 — What generation looks like WITHOUT this system

To show what the gate is actually for, here is a from-memory async FIFO. It is the
realistic failure mode: it reads correctly and it compiles.

```systemverilog
localparam ADDR_W = $clog2(DEPTH);
logic [ADDR_W-1:0] wr_ptr_q, rd_ptr_q;              // (A)
logic [ADDR_W-1:0] wr_ptr_sync1_q, wr_ptr_sync_q;

always_ff @(posedge rd_clk or negedge rd_rst_n) begin
  if (!rd_rst_n) begin wr_ptr_sync1_q <= '0; wr_ptr_sync_q <= '0; end
  else begin wr_ptr_sync1_q <= wr_ptr_q;            // (B) BINARY pointer
             wr_ptr_sync_q  <= wr_ptr_sync1_q; end
end

assign rd_empty_o = (rd_ptr_q == wr_ptr_sync_q);
assign level_o    = wr_ptr_q - rd_ptr_sync_q;       // (C)

always_ff @(posedge rd_clk) begin                   // (D) full in READ domain
  if (!rd_rst_n) wr_full_o <= 1'b0;
  else wr_full_o <= ((wr_ptr_sync_q + 1'b1) == rd_ptr_q);
end
```

## Stage 5 — Review findings

### 5a. Deterministic evidence — the real result

```
$ bin/rtl-lint fifo_async_bad.sv
RTL-LINT: clean. 0 findings from slang (full elaboration, -Weverything).
RTL-LINT-SUMMARY BLOCKER=0 HIGH=0 MEDIUM=0 LOW=0 INFO=0 TOOL=slang
```

**Zero findings.** Then the gate:

```
$ hooks/rtl_gate.sh fifo_async_bad.sv
RTL GATE: tool-clean -- fifo_async_bad.sv  (BLOCKER=0 HIGH=0 MEDIUM=0 LOW=0 INFO=0, tool=slang)
A clean tool run is NOT a signoff. slang checks none of: CDC, reset release,
arithmetic overflow, FSM reachability, protocol deadlock, arbitration fairness,
blocking assignments in clocked blocks. Run the 20 categories and the 11
self-critique questions in skills/rtl-review-signoff/ before approving.
gate exit=0
```

**This is the pivotal moment of the entire example.** A naive flow stops here and
reports success. The gate explicitly refuses to let a clean tool run stand as a signoff,
and names the categories that hide this file's real bugs.

### 5b. Reasoning-tier review — CDC category

Method from `checklist-reset-cdc.md`: enumerate every clock, then every crossing by name.

Clocks: `wr_clk`, `rd_clk` — unrelated. Crossings:

| Crossing | Mechanism found | Verdict |
|---|---|---|
| `wr_ptr_q` → read domain | 2-flop sync on a **binary** multi-bit pointer | **BLOCKER** |
| `rd_ptr_q` → write domain | same | **BLOCKER** |

```
[BLOCKER] CDC Review -- fifo_async_bad.sv:(B)
  What:  Binary multi-bit pointer through a 2-flop synchroniser (AP-CDC-06).
  Why:   wr_ptr 0111 -> 1000 changes four bits. Each resolves old-or-new
         independently, so the read domain can sample any of 16 values --
         including pointers that never existed. rd_empty_o is then computed
         from a fictional pointer: either a hang, or reading stale entries.
  Fix:   Maintain binary for addressing AND gray for crossing.
         gray = bin ^ (bin >> 1). Cross gray only; compare in gray space.
  Tier:  [reasoning] UNVERIFIED -- no CDC tool on this machine
```

```
[HIGH] CDC Review -- fifo_async_bad.sv:(D)
  What:  wr_full_o computed in the READ domain (AP-FIFO-05).
  Why:   Uses a stale write pointer, so full asserts LATE -> overflow.
         Each flag must live where it is conservative: full in the write
         domain, empty in the read domain.
  Fix:   Move the full computation into always_ff @(posedge wr_clk).
  Tier:  [reasoning] UNVERIFIED
```

```
[HIGH] CDC Review -- fifo_async_bad.sv:(C)
  What:  level_o exports an exact occupancy from an async FIFO.
  Why:   Neither domain can know the true level; each sees a delayed view.
         Any consumer doing exact-threshold logic on this is wrong.
  Fix:   Remove it, or export a conservative almost_full/almost_empty
         computed in the domain that can make it safe.
  Tier:  [reasoning] UNVERIFIED
```

### 5c. Reasoning-tier — FIFO structure

```
[BLOCKER] Functional Intent / Width -- fifo_async_bad.sv:(A)
  What:  Pointers ADDR_W wide, not ADDR_W+1 (AP-FIFO-01).
  Why:   With only address bits, wr_ptr == rd_ptr means BOTH empty and full.
         Indistinguishable. Broken as soon as it wraps once.
  Fix:   logic [ADDR_W:0] -- and use the extra bit in both comparisons.
  Tier:  [reasoning] UNVERIFIED
```

### 5d. Parameter review

```
[HIGH] Parameter Review
  What:  No elaboration assertion on DEPTH.
  Why:   Gray coding requires a power of two. DEPTH=12 produces invalid
         flags with no warning (AP-FIFO-04). Untyped parameters are also
         signed (AP-SIGN-02).
  Fix:   parameter int unsigned DEPTH, plus initial/$fatal on
         (DEPTH & (DEPTH-1)) != 0 and DEPTH < 4.
  Tier:  [reasoning] UNVERIFIED
```

### 5e. Self-critique — the 11 questions

```
Q1  latches ......... NO   [slang] -Winferred-latch clean, full elaboration
Q2  CDC ............. YES
      Risk:       binary pointers through both synchronisers
      Impact:     sampled pointer values that never existed -> hang or stale data
      Severity:   BLOCKER
      Mitigation: gray-code the crossing pointers
Q3  truncation ...... YES
      Risk:       level_o is [7:0]; wr_ptr - rd_ptr is ADDR_W wide
      Impact:     works at DEPTH<=256, silently wrong above
      Severity:   MEDIUM  (the signal should not exist at all -- see 5b)
      Mitigation: delete level_o
Q4  signedness ...... YES   untyped parameters WIDTH/DEPTH are signed int
Q5  overflow ........ YES   pointer arithmetic with no extra bit (see 5c)
Q6  reset ........... YES
      Risk:       two reset domains, neither synchronised; no rst_sync anywhere
      Impact:     domains leave reset at unrelated times; pointers disagree at
                  startup (AP-RST-03, AP-RST-04)
      Severity:   HIGH
      Mitigation: one reset synchroniser per domain
Q7  sim vs synth .... NO    non-blocking throughout, no casex, no pragmas
Q8  deadlock ........ YES   false empty/full can hang either side
Q9  starvation ...... NO    no arbitration
Q10 parameters ...... YES   DEPTH=12 breaks gray coding, nothing refuses it
Q11 corner cases .... YES   simultaneous read+write near wrap; first cycle
                            after reset with unsynchronised resets
```

**8 of 11 YES.** The self-critique is doing exactly what it is for. Compare: slang
found nothing.

### 5f. Gate decision

```
BLOCKER=2  HIGH=4  MEDIUM=1  LOW=0  INFO=0
cdc_confidence = 0.45   (two unrelated clocks, no documented relationship,
                         no CDC tool available)

gate():
  BLOCKER >= 1                  -> REJECTED
```

**DECISION: `REJECTED`** — and note that confidence alone would also have forced
`MANUAL_REVIEW_REQUIRED`, independently of the finding count.

## Stage 6 — Auto-fix, round 1

Per the retry guards, the fix must not be a symptom patch. The structure is wrong, so
retrieval rule 4 applies: **never silently substitute a near-miss.** The correct action
is to adopt `golden_fifo_async.sv`, which already encodes every fix:

| Finding | What the template does |
|---|---|
| Binary pointers (BLOCKER) | keeps `wr_bin_q` for addressing, `wr_gray_q` for crossing |
| Pointer width (BLOCKER) | `logic [ADDR_W:0]`, extra bit used in both comparisons |
| `full` in wrong domain (HIGH) | `full` under `@(posedge wr_clk)`, `empty` under `@(posedge rd_clk)`, under banner comments |
| `level_o` (HIGH) | not exported — documented as unknowable |
| Reset domains (HIGH) | separate `wr_rst_n` / `rd_rst_n` ports, making the requirement visible at the interface |
| `DEPTH` assertions (HIGH) | `$fatal` on non-power-of-two and on `DEPTH < 4` |
| `DEPTH=12` (HIGH) | refuses to elaborate |

The `DEPTH >= 4` assertion deserves a note: the full comparison slices
`rd_gray_sync_q[ADDR_W-2:0]`, which is illegal at `ADDR_W == 1`. That is a parameter
corner case found by the Width Review check *"part-selects within bounds for every legal
parameter value, not just the default"* — not by any tool.

**Intent preservation check:** the request was a parameterized async FIFO. The result is
parameterized on `WIDTH` and `DEPTH`. Intent preserved. Assumption recorded: *parameterized
means `WIDTH` and `DEPTH`; `DEPTH` is constrained to powers of two `>= 4`.*

## Stage 7 — Re-review (full, not delta)

```
$ bin/rtl-lint skills/rtl-golden-templates/templates/golden_fifo_async.sv
RTL-LINT: clean. 0 findings from slang (full elaboration, -Weverything).
RTL-LINT-SUMMARY BLOCKER=0 HIGH=0 MEDIUM=0 LOW=0 INFO=0 TOOL=slang
```

Tool clean — **as the broken version also was.** So the reasoning tier is re-run in full:

| Category | Verdict |
|---|---|
| CDC | Both crossings gray-coded. Two flops each, nothing between. `full` in write domain, `empty` in read domain. `ASYNC_REG` present. **PASS**, recorded as INFO. |
| Reset | Separate per-domain resets at the interface; `empty` resets to 1; memory deliberately unreset with the reason stated. **PASS** |
| Width | Pointers `ADDR_W+1`. `DEPTH >= 4` assertion protects the `[ADDR_W-2:0]` slice. **PASS** |
| Parameter | Both constraints are `$fatal` assertions, not comments. **PASS** |
| X/Z | Memory unreset, but pointers guarantee no read-before-write, and that is commented. **PASS** |

Self-critique, second pass: Q2 CDC → **NO**, with the mechanism named per crossing and
still marked `[reasoning]`. Q5 overflow → **NO**, pointer arithmetic carries the extra
bit. Q10 parameters → **NO**, illegal values refuse to elaborate.

## Stage 8 — Signoff

```
BLOCKER=0  HIGH=0  MEDIUM=0  LOW=0  INFO=3
self-critique: complete, no unmitigated YES
cdc_confidence = 0.85   (both clocks are ports, both crossings enumerated,
                         each mechanism identified and checked structurally)
tool = slang

DECISION: APPROVED_WITH_CHANGES
```

**Not `APPROVED`.** Three reasons, all stated rather than smoothed over:

1. **No CDC tool ran.** Every CDC conclusion is `[reasoning] UNVERIFIED`.
   `severity-rubric.md` is explicit: a reasoning-only CDC conclusion is **not**
   sufficient for tape-out, however confident it reads. Required before tape-out:
   `/rtl-cdc` with the project's goal set.
2. **INFO deliverables are owed to other people**, and they are not optional:
   - SDC: false-path or max-delay constraints on both pointer crossings.
   - `ASYNC_REG` must survive this flow's synthesis — vendor spelling varies.
   - The memory array needs a BIST/bypass path at integration (DFT Review).
3. **Recorded assumption:** "parameterized" was read as `WIDTH` and `DEPTH`. If the
   requester meant parameterised synchroniser depth or almost-full thresholds, that is a
   different module.

---

## What this example demonstrates

**The tool was clean on both the broken and the correct FIFO.** Everything that
distinguished them came from the reasoning tier — which is only trustworthy because it
is (a) forced by a hook rather than chosen, (b) procedural rather than impressionistic,
(c) labelled `UNVERIFIED` so nobody mistakes it for proof, and (d) allowed to end in
`MANUAL_REVIEW_REQUIRED` instead of being pressured into an approval.

One loop was used of three. The fix was adoption of a verified template rather than a
patch, which is why one round sufficed: patching four structural bugs in place is how a
second round becomes a third and then an escalation.
