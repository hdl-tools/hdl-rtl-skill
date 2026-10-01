---
name: rtl-golden-templates
description: "Reviewed, compile-verified Verilog/SystemVerilog reference implementations to start from instead of writing RTL from memory. Load when asked to create or modify a counter, timer, synchronizer, CDC crossing, FSM, state machine, ready/valid handshake, register slice, skid buffer, pipeline stage, sync FIFO, async FIFO, queue, or round-robin arbiter. Every template is slang-clean and carries its own review focus and common-mistake list. Keywords: fifo, async fifo, cdc, synchronizer, 2ff, fsm, state machine, arbiter, round robin, ready valid, handshake, skid buffer, register slice, pipeline, counter, timer, golden reference, template."
metadata:
  type: retrieval
  verified-with: "slang 9.0.0 -- tests/run_tests.sh proves all 11 elaborate with zero diagnostics"
---

# Golden RTL Templates

Eleven reference implementations in `templates/`. **Every one is proven to
elaborate with zero slang diagnostics** by `tests/run_tests.sh` — that is the
whole point. A template that does not compile is worse than no template, because
it gets copied confidently.

**Start from a template rather than writing from memory.** Writing a fresh async
FIFO from recall is how gray-code pointers turn into binary ones. Adapting a
verified file is a smaller, more reviewable change than generating a new one.

Each template's header carries five fields you should read before adapting it:
**Purpose / When to use / Review focus / Common mistakes / Retrieval triggers.**

---

## Retrieval table

| Template | Use for | Must-review | Triggers |
|---|---|---|---|
| `golden_counter.sv` `.v` | counters, timers, timeouts, credit counters, address generators | Width (does WIDTH hold MAX_COUNT), Arithmetic (wrap vs saturate), Parameter | counter, timer, timeout, tick, credit, address generator, saturate, wrap |
| `golden_sync_2ff.sv` `.v` | **one bit** of control crossing clock domains | CDC (dest clock, no logic between flops, STAGES>=2, source stability) | cdc, synchronizer, 2ff, metastability, async signal, resync |
| `golden_fsm.sv` | any control sequencer | FSM (reachability, liveness, illegal-state recovery), Case, Reset | fsm, state machine, moore, mealy, sequencer, controller, next state |
| `golden_ready_valid.sv` | a simple buffered handshake **and the written 5-rule contract** | Protocol (all 5 rules), CDC (must be one domain) | ready valid, handshake, backpressure, flow control, stream, beat |
| `golden_register_slice.sv` | breaking a timing path **without** losing throughput | Protocol, throughput measurement under backpressure | register slice, skid buffer, pipeline register, timing closure, elastic buffer |
| `golden_fifo_sync.sv` | buffering within **one** clock domain | Width (ADDR_W derived), overflow/underflow guards, Reset | fifo, sync fifo, queue, buffer, ring buffer, rate matching |
| `golden_fifo_async.sv` | **multi-bit** data crossing clock domains | **CDC (the critical one)**, Reset (two domains), Parameter (power of two, >=4) | async fifo, cdc fifo, dual clock fifo, gray code pointer, multi-bit cdc |
| `golden_rr_arbiter.sv` | sharing a resource among N requesters fairly | Fairness (walk the wrap case), one-hot grant, Reset (mask=all ones) | arbiter, round robin, fairness, starvation, grant, shared bus |
| `golden_pipeline_stage.sv` | fixed-latency datapath stage with valid propagation | Reset (valid must clear), X/Z, Power (gate the load) | pipeline, pipe stage, valid propagation, bubble, flush, retiming |

---

## Retrieval rules

Rules fire in order; a later rule adds to the set, it does not replace it.

| Request contains | Retrieve |
|---|---|
| "fifo" (unqualified) | `golden_fifo_sync.sv` **and** ask whether the two sides share a clock. The answer changes everything. |
| "async fifo", "dual clock fifo", "cdc fifo" | `golden_fifo_async.sv` **+** `golden_sync_2ff.sv` **+** CDC checklist **+** `patterns/ap-cdc.md` |
| "cdc", "synchronizer", "clock domain" | `golden_sync_2ff.sv` **+** CDC checklist **+** `patterns/ap-cdc.md`. If the payload is multi-bit, add `golden_fifo_async.sv`. |
| "fsm", "state machine", "sequencer" | `golden_fsm.sv` **+** `patterns/ap-fsm.md` |
| "arbiter", "round robin", "fairness" | `golden_rr_arbiter.sv` **+** `patterns/ap-protocol.md` |
| "ready/valid", "handshake", "backpressure" | `golden_ready_valid.sv` (for the contract) **+** `golden_register_slice.sv` (if throughput matters) **+** `patterns/ap-protocol.md` |
| "register slice", "skid buffer", "break timing" | `golden_register_slice.sv` |
| "pipeline", "pipe stage" | `golden_pipeline_stage.sv`. If backpressure is involved, `golden_register_slice.sv` instead — a pipeline stage cannot stall correctly. |
| "counter", "timer", "timeout" | `golden_counter.sv` |
| ".v", "verilog-2001", "no systemverilog" | the `.v` variant, **plus** a note that the `.sv` version is strictly safer |

### Scoring, when several could apply

```
score = 3*exact_name_match          # "async fifo" -> golden_fifo_async
      + 2*structural_match          # multi-bit + two clocks -> async fifo
      + 2*risk_category_match       # mentions CDC -> retrieve CDC templates
      + 1*keyword_overlap
      - 2*dialect_mismatch          # .v requested, only .sv exists
```

Retrieve the top score, plus **every** template scoring within 2 of it. Cap at
three templates: beyond that the context cost outweighs the benefit and the
important one gets diluted.

### Conflict resolution

1. **Structure beats wording.** A request for "a FIFO between two clocks" gets the
   async FIFO no matter what the user called it. The physics does not care about
   the wording.
2. **Safety beats convenience.** When one candidate is safe and one is simpler,
   retrieve the safe one and explain the cost. A 2-flop sync is simpler than an
   async FIFO and wrong for a bus.
3. **Explicit dialect wins.** `.v` asked for means `.v` delivered — plus a one-line
   note that the `.sv` version is safer, said once, not argued.
4. **Never silently substitute.** If the right template does not exist, say so and
   write from the style guide. Do not retrieve a near-miss and quietly adapt it;
   a half-adapted FIFO is worse than a fresh one.
5. **Contradictory requirements** ("full throughput, one flop, no skid buffer") →
   state the contradiction and ask. Do not pick.

---

## Adapting a template

1. **Keep the header.** Update Purpose to the specific use; keep Review focus and
   Common mistakes — they are the reason the next reviewer trusts the file.
2. **Keep the parameter assertions.** They are the only thing standing between a
   gray-coded FIFO and someone instantiating it at depth 12.
3. **Keep `` `default_nettype none ``.** One line that makes typos compile errors.
4. **Change one thing at a time**, and re-run `bin/rtl-lint` after each.
5. **Note the deviation.** If you depart from the template, say why in a comment.
   Otherwise someone restores the template behaviour and reintroduces whatever you
   were working around.
6. **Re-review from scratch.** An adapted template is new RTL. The original's
   clean review does not transfer.

## Adding a template

A new file is not a template until `tests/run_tests.sh` passes with it present —
zero slang diagnostics, full elaboration. Add the five header fields, add a row to
the retrieval table above, and add its trigger keywords to this skill's
`description` so it can actually be found.
