---
name: rtl-anti-patterns
description: "Catalogue of known Verilog/SystemVerilog RTL bug patterns with root cause, symptoms, detection and fix. Load when reviewing or debugging RTL, when a design misbehaves intermittently, or before generating CDC, reset, FSM, FIFO, arbiter or datapath logic. Covers CDC failures, reset failures, FSM failures, width mismatch, signedness, arithmetic overflow, latch inference, multiple drivers, protocol deadlock, combinational loops, simulation vs synthesis mismatch, X propagation, async reset release, FIFO bugs, arbitration starvation. Keywords: bug, anti-pattern, debug, intermittent failure, metastability, deadlock, starvation, latch, glitch, post-silicon escape, review escape."
metadata:
  type: retrieval
  detectable-subset: "8 of these are proven detectable by slang -- see tests/bad/ and tests/run_tests.sh"
---

# RTL Anti-Pattern Library

Fifteen bug categories, grouped into seven files. Each entry carries
**Description / Root cause / Symptoms / Detection / Auto-fix / Severity.**

**What makes this list trustworthy:** nine of these patterns have a
corresponding file in `tests/bad/` that **provably triggers** the named
diagnostic — `tests/run_tests.sh` fails if detection ever regresses. The rest are
explicitly marked `[reasoning]`, meaning no tool on this machine detects them and
review is the only line of defence. Knowing which is which is the point.

---

## Index

| ID | Anti-pattern | File | Severity | Detectable |
|---|---|---|---|---|
| AP-CDC-01 | Multi-bit bus through a 2-flop synchroniser | `ap-cdc.md` | BLOCKER | `[reasoning]` |
| AP-CDC-02 | No synchroniser at all on an async input | `ap-cdc.md` | BLOCKER | `[reasoning]` |
| AP-CDC-03 | Combinational logic inside a synchroniser chain | `ap-cdc.md` | HIGH | `[reasoning]` |
| AP-CDC-04 | Reconvergence of separately synchronised bits | `ap-cdc.md` | HIGH | `[reasoning]` |
| AP-CDC-05 | Pulse narrower than the destination clock period | `ap-cdc.md` | HIGH | `[reasoning]` |
| AP-CDC-06 | Binary (not gray) counter across a domain | `ap-cdc.md` | BLOCKER | `[reasoning]` |
| AP-RST-01 | Reset polarity contradicts the signal name | `ap-reset.md` | BLOCKER | `[reasoning]` |
| AP-RST-02 | No reset on FSM state | `ap-reset.md` | BLOCKER | `[reasoning]` |
| AP-RST-03 | Unsynchronised async reset **release** | `ap-reset.md` | HIGH | `[reasoning]` |
| AP-RST-04 | One raw reset fanned out to several domains | `ap-reset.md` | HIGH | `[reasoning]` |
| AP-RST-05 | Reset-domain crossing | `ap-reset.md` | HIGH | `[reasoning]` |
| AP-RST-06 | Logic in the reset path | `ap-reset.md` | MEDIUM | `[reasoning]` |
| AP-RST-07 | Wrong reset value on a status flag | `ap-reset.md` | HIGH | `[reasoning]` |
| AP-FSM-01 | Missing illegal-state recovery | `ap-fsm.md` | HIGH | partial `[slang]` |
| AP-FSM-02 | `case` without `default` | `ap-fsm.md` | HIGH | **`[slang]`** |
| AP-FSM-03 | Unreachable state | `ap-fsm.md` | MEDIUM | `[reasoning]` |
| AP-FSM-04 | State with no exit (deadlock) | `ap-fsm.md` | BLOCKER | `[reasoning]` |
| AP-FSM-05 | One-block FSM mixing state and outputs | `ap-fsm.md` | MEDIUM | `[reasoning]` |
| AP-WIDTH-01 | Silent truncation on assignment | `ap-datapath.md` | HIGH | **`[slang]`** |
| AP-WIDTH-02 | Truncation at an instance port | `ap-datapath.md` | HIGH | **`[slang]`** |
| AP-WIDTH-03 | Hand-typed width beside a parameter | `ap-datapath.md` | MEDIUM | `[reasoning]` |
| AP-SIGN-01 | Signed compared against unsigned | `ap-datapath.md` | HIGH | **`[slang]`** |
| AP-SIGN-02 | Untyped parameter is signed | `ap-datapath.md` | HIGH | partial `[slang]` |
| AP-SIGN-03 | Size-cast of a bare literal is signed | `ap-datapath.md` | HIGH | **`[slang]`** |
| AP-ARITH-01 | Sum overflows its result width | `ap-datapath.md` | HIGH | `[reasoning]` |
| AP-ARITH-02 | Unsigned subtraction underflows | `ap-datapath.md` | HIGH | `[reasoning]` |
| AP-ARITH-03 | Unbounded accumulator | `ap-datapath.md` | HIGH | `[reasoning]` |
| AP-LATCH-01 | Incomplete combinational block | `ap-structural.md` | HIGH | **`[slang]`** |
| AP-STRUCT-01 | Multiple drivers | `ap-structural.md` | BLOCKER | **`[slang]`** |
| AP-STRUCT-02 | Implicit net from a typo | `ap-structural.md` | BLOCKER | **`[slang]`** w/ `default_nettype none` |
| AP-STRUCT-03 | Signal read but never driven | `ap-structural.md` | HIGH | **`[slang]`** |
| AP-LOOP-01 | Combinational loop | `ap-structural.md` | BLOCKER | partial `[slang]` |
| AP-PROTO-01 | `valid` depends combinationally on `ready` | `ap-protocol.md` | BLOCKER | `[reasoning]` |
| AP-PROTO-02 | Retracted `valid` | `ap-protocol.md` | HIGH | `[reasoning]` |
| AP-PROTO-03 | Payload changes while stalled | `ap-protocol.md` | HIGH | `[reasoning]` |
| AP-PROTO-04 | Circular wait (deadlock) | `ap-protocol.md` | BLOCKER | `[reasoning]` |
| AP-PROTO-05 | Leaked credit or token | `ap-protocol.md` | HIGH | `[reasoning]` |
| AP-FIFO-01 | Pointers too narrow to tell full from empty | `ap-protocol.md` | BLOCKER | `[reasoning]` |
| AP-FIFO-02 | Separate up/down count register | `ap-protocol.md` | HIGH | `[reasoning]` |
| AP-FIFO-03 | Unguarded write-when-full / read-when-empty | `ap-protocol.md` | HIGH | `[reasoning]` |
| AP-FIFO-04 | Non-power-of-two depth with wrap-by-truncation | `ap-protocol.md` | HIGH | `[reasoning]` |
| AP-FIFO-05 | Flag computed in the wrong clock domain | `ap-protocol.md` | HIGH | `[reasoning]` |
| AP-ARB-01 | Priority encoder presented as round-robin | `ap-protocol.md` | HIGH | `[reasoning]` |
| AP-ARB-02 | Rotation advances on an unconsumed grant | `ap-protocol.md` | HIGH | `[reasoning]` |
| AP-ARB-03 | Grant not one-hot | `ap-protocol.md` | HIGH | `[reasoning]` |
| AP-SIM-01 | Blocking `=` in a clocked block | `ap-simsynth.md` | HIGH | `[reasoning]` |
| AP-SIM-02 | Incomplete explicit sensitivity list | `ap-simsynth.md` | HIGH | `[reasoning]` |
| AP-SIM-03 | `full_case` / `parallel_case` pragma | `ap-simsynth.md` | HIGH | `[reasoning]` |
| AP-SIM-04 | `initial` block driving logic | `ap-simsynth.md` | HIGH | `[reasoning]` |
| AP-SIM-05 | `#delay` in RTL | `ap-simsynth.md` | BLOCKER | `[reasoning]` |
| AP-X-01 | `casex` hides X | `ap-simsynth.md` | HIGH | `[reasoning]` |
| AP-X-02 | Flop read before written, no reset | `ap-simsynth.md` | HIGH | `[reasoning]` |
| AP-X-03 | X-optimism in a mux or case | `ap-simsynth.md` | MEDIUM | `[reasoning]` |

**Read the "Detectable" column before trusting a clean review.** Of 53 entries, 9
are mechanically proven. Everything marked `[reasoning]` is only as good as the
review that looked for it — which is why the review hook is mandatory and why CDC
and reset carry a confidence threshold that can escalate to
`MANUAL_REVIEW_REQUIRED`.

---

## How to use this during a review

1. Before generating: read the file matching what you are about to build. The
   Common-mistakes list in the matching golden template is the short version.
2. During review: for each category in `rtl-review-signoff`, scan the relevant
   anti-pattern file for the specific shapes rather than reading generally.
3. During debug: go **symptom-first**. Each file's symptoms are written as what you
   would actually observe — "works in sim, fails on the board", "fails only under
   sustained load", "fails after hours" — because that is how the bug arrives.
