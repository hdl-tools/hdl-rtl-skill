---
name: rtl-workflow
description: "Orchestration for RTL work: when to load the style guide, retrieve a golden template, run the review hook, auto-fix, and re-review. Load at the start of any Verilog/SystemVerilog task — creating, modifying, reviewing, debugging or optimising RTL. Defines trigger rules and confidence scoring, the four workflows, bounded retry (MAX_REVIEW_LOOPS=3), context injection priority, and escalation to MANUAL_REVIEW_REQUIRED. Keywords: rtl workflow, verilog, systemverilog, module, review hook, auto fix, trigger, escalation, manual review, design flow."
metadata:
  type: orchestration
  enforced-by: hooks/rtl_gate.sh
---

# RTL Workflow

Four workflows, one shape. The shape mirrors a real engineering process because the
separation is what catches bugs:

```
Designer  ->  Peer review  ->  Lint  ->  CDC  ->  Signoff
```

The reason this works for an AI the same way it works for a team: **the reviewer must
not be the author's own first impulse.** Generation optimises for plausibility;
review optimises for failure modes. Running them as one pass gets you plausible code
reviewed by the thing that found it plausible. See `docs/hallucination-prevention.md`.

---

## 1. RTL creation

```
user request
   |
   v
[1] intent detection ............. trigger rules, section 5
   |
   v
[2] inject rtl-style-guide ....... always, before writing a line
   |
   v
[3] retrieve golden template ..... rtl-golden-templates scoring
   |     + inject matching anti-pattern file
   v
[4] generate RTL ................. adapt the template; do not write from memory
   |
   v
[5] REVIEW HOOK (mandatory) ...... bin/rtl-lint, then 20 categories,
   |                               then self-critique.md
   v
[6] severity gate ................ severity-rubric.md
   |
   +-- APPROVED ---------------------------------> output
   +-- APPROVED_WITH_CHANGES --> [7] auto-fix --+
   +-- REJECTED ---------------> [7] auto-fix --+
   |                                             |
   |                                             v
   |                                     [8] RE-REVIEW (full, not delta)
   |                                             |
   |                      loop < 3 and improving -+
   |                                             |
   +-- MANUAL_REVIEW_REQUIRED <-- loop == 3 -----+
```

Step 5 is not skippable and step 8 is a **full** re-review, not a check of the lines
you touched. A fix changes the design; the design is what gets reviewed.

## 2. RTL modification

```
user request + existing RTL
   |
   v
[1] read the existing file FULLY ... including the header contract
   |
   v
[2] inject rtl-style-guide ......... match the file's existing dialect and style,
   |                                 even where it differs from the guide
   v
[3] apply the minimal modification . smallest diff that satisfies the request
   |
   v
[4] REVIEW HOOK .................... review the WHOLE file, not just the diff
   |
   v
[5] gate -> auto-fix -> re-review .. as above
```

Two rules specific to modification:
- **Match the file, not the guide.** A file using `always @(posedge clk)` throughout
  gets another one, with the style note raised as LOW. Introducing `always_ff` into
  one block of a Verilog-2001 file is a worse outcome than the deviation.
- **Review the whole file.** A two-line change can break a CDC assumption fifty lines
  away. Diff-only review is how modification bugs escape.

## 3. RTL review (no generation)

```
user request ("review this", "is this right", a pasted module)
   |
   v
[1] bin/rtl-lint ............ evidence first, before forming an opinion
   |
   v
[2] 20 categories ........... all five checklist files
   |
   v
[3] self-critique.md ........ all 11 questions
   |
   v
[4] classify ................ every finding gets severity + tier + failure scenario
   |
   v
[5] signoff recommendation .. with explicit assumptions and UNVERIFIED labels
```

Running the tool **before** reading the code is deliberate: it anchors the review in
facts rather than in an impression formed from a first read.

## 4. RTL debug

```
symptom report
   |
   v
[1] restate the symptom precisely ... "fails after hours" is a different bug class
   |                                  from "fails every time"
   v
[2] symptom -> candidate list ....... rtl-anti-patterns, symptom-first
   |
   v
[3] bin/rtl-lint .................... cheap, and sometimes just answers it
   |
   v
[4] full review hook ................ the reported symptom is not necessarily the bug
   |
   v
[5] root cause ...................... name the mechanism, not the location
   |
   v
[6] fix + FULL re-review ............ a fix is new RTL
```

**Symptom-to-category shortcuts** (start here, do not stop here):

| Symptom | Look first at |
|---|---|
| Intermittent, rate scales with clock ratio | `ap-cdc.md` |
| Fails at bring-up, fine once running | `ap-reset.md` |
| Hangs, needs power cycle | `ap-fsm.md` (AP-FSM-01/04), `ap-protocol.md` (AP-PROTO-04) |
| Wrong only for large values | `ap-datapath.md` (AP-WIDTH-01, AP-ARITH-01) |
| Wrong only for negative values | `ap-datapath.md` (AP-SIGN-01) |
| Fails only under sustained load | `ap-protocol.md` (AP-ARB-01, AP-PROTO-02/03) |
| Works in sim, fails in gates or on the board | `ap-simsynth.md` |
| Degrades slowly over hours | `ap-protocol.md` (AP-PROTO-05) |
| Timing failure on an unexpected path | `ap-structural.md` (AP-LATCH-01) |

## 5. RTL optimisation

```
[1] measure or state the actual constraint .. timing / area / power, with a number
   |
   v
[2] confirm the baseline REVIEWS CLEAN ...... never optimise broken RTL
   |
   v
[3] apply ONE transform .................... retime, share, re-encode, gate
   |
   v
[4] full review hook ....................... optimisation breaks protocols
   |                                         (especially latency and throughput)
   v
[5] confirm the contract is unchanged ...... latency, throughput, handshake rules
```

The failure mode specific to optimisation: a transform that improves timing and
silently changes latency. Inserting a register to break a path adds a cycle; if the
interface contract did not say so, every consumer is now wrong. Re-check the contract
explicitly, every time.

---

## 6. Trigger rules

### Explicit triggers — always act
File extension `.v` `.sv` `.svh` `.vh`, or the words: `verilog`, `systemverilog`,
`rtl`, `hdl`, `module`, `always_ff`, `always_comb`, `synthesis`, `synthesisable`,
`netlist`, `testbench` (review only, see exclusions).

### Implicit triggers — RTL concepts without the word "verilog"
`fsm`, `state machine`, `fifo`, `queue`, `arbiter`, `round robin`, `cdc`,
`clock domain`, `synchronizer`, `synchroniser`, `metastability`, `handshake`,
`ready_valid`, `ready/valid`, `backpressure`, `axi`, `ahb`, `apb`, `wishbone`,
`register slice`, `skid buffer`, `pipeline`, `pipeline stage`, `counter`, `timer`,
`reset`, `rst_n`, `clock gating`, `scan`, `dft`, `atpg`, `lint`, `width mismatch`,
`latch`, `one-hot`, `gray code`, `tapeout`, `post-silicon`.

### Review triggers — run the hook even with no code generation
"review", "check", "audit", "look at", "is this right", "will this work",
"any bugs", "sanity check", "sign off", "approve", "ready to commit",
or any pasted block containing `module`/`endmodule`.

### Debug triggers — add anti-patterns, symptom-first
"doesn't work", "intermittent", "sometimes fails", "hangs", "stuck", "deadlock",
"corrupted", "glitch", "works in sim but not", "fails on the board",
"passes simulation but", "only under load", "after a few hours".

### Modification triggers — read first, review the whole file
"change", "add", "update", "fix", "refactor", "extend", "parameterise", "port to",
"make it", "convert to", plus any edit to an existing RTL file.

### Where the review hook must NOT run
| Situation | Why |
|---|---|
| Testbench-only file (`*_tb.sv`, `tb_*.sv`, `*_test.sv`) | Different rules entirely. `#delay`, `initial` and blocking assignments are all correct there. Running the RTL rules produces pure noise. |
| Filelists (`.f`), scripts (`.tcl`, `.sdc`), docs, Makefiles | Not RTL. |
| Comment-only or whitespace-only diff | No logic changed. |
| Generated or vendor IP marked do-not-edit | Not yours to change; review it on request, but do not gate edits that are regeneration. |
| User explicitly says "skip review" / "no review" | Their call. Say once that the gate is off, then comply. |
| Discussing RTL concepts with no code in play | Answer the question. A conversation is not a design. |

Noise is the enemy here. A gate that fires on testbenches and comment changes gets
switched off, and then it protects nothing.

### Confidence scoring

```python
def rtl_confidence(request, files):
    score = 0.0
    if any(f.endswith(('.v','.sv','.svh','.vh')) for f in files):  score += 0.50
    if contains_module_definition(request):                        score += 0.30
    if contains_always_blocks(request):                            score += 0.20
    if contains_explicit_rtl_keywords(request):                    score += 0.25
    if contains_implicit_rtl_concepts(request):                    score += 0.15
    if is_testbench_only(files):                                   score -= 0.60
    if is_non_rtl_file(files):                                     score -= 0.80
    return clamp(score, 0.0, 1.0)
```

| Score | Action |
|---|---|
| >= 0.70 | Full workflow. Style guide + templates + mandatory review hook. |
| 0.40 – 0.69 | Load the style guide. Run the review hook if any code is produced. |
| 0.15 – 0.39 | Answer directly. Mention the review hook is available. |
| < 0.15 | Not RTL. Do nothing special. |

**On a tie, run the review.** A review nobody needed costs a few seconds. A missed
one costs a respin.

---

## 7. Review retry

```python
MAX_REVIEW_LOOPS = 3

def review_and_fix(rtl, intent):
    history = []
    for loop in range(MAX_REVIEW_LOOPS):
        result = run_review(rtl)                   # bin/rtl-lint + 20 cats + critique
        history.append(result)

        if result.decision in ("APPROVED", "MANUAL_REVIEW_REQUIRED"):
            return result

        # --- loop guards, in order of how badly they fail ---

        # (a) regression: a "fix" made things worse. Revert and escalate.
        if loop > 0 and worse_than(result, history[loop-1]):
            return escalate(history, "auto-fix introduced a regression; reverted",
                            rtl=history[loop-1].rtl)

        # (b) no progress: same findings as last time. More loops will not help.
        if loop > 0 and same_findings(result, history[loop-1]):
            return escalate(history, "auto-fix made no progress on the same findings")

        # (c) intent drift: the fix changed what the module DOES.
        if not preserves_intent(rtl, intent):
            return escalate(history, "fix altered functional intent; reverted",
                            rtl=history[loop-1].rtl if loop else None)

        rtl = apply_fixes(rtl, result.findings)

    return escalate(history, f"{MAX_REVIEW_LOOPS} loops exhausted")


def escalate(history, reason, rtl=None):
    return Result(decision="MANUAL_REVIEW_REQUIRED",
                  reason=reason,
                  remaining=history[-1].unresolved,
                  attempts=[h.summary for h in history],
                  rtl=rtl)
```

**Why each guard exists**
- **Bounded at 3.** Two fix rounds is where genuine progress stops. Beyond that the
  model is rewriting rather than fixing, and each rewrite needs its own full review.
- **Regression check.** The most damaging outcome is a "fix" that trades a reported
  bug for an unreported one. Compare finding sets, not counts — one BLOCKER replacing
  three LOWs is worse, not better.
- **Same-findings check.** Identical findings twice means the fix strategy does not
  work. Repeating it a third time wastes a loop that could have been an escalation.
- **Intent preservation.** The worst auto-fix is one that silences a warning by
  changing behaviour: narrowing a signal to stop a truncation warning *implements the
  truncation*. Before any fix, restate what the module must do; after, confirm it
  still does.

**`MANUAL_REVIEW_REQUIRED` is a success, not a failure.** Presenting RTL with
unresolved CDC concerns as approved is the failure.

---

## 8. Context injection

**Priority order.** Under pressure, drop from the bottom:

| Priority | Inject | When |
|---|---|---|
| 1 | `rtl-review-signoff/SKILL.md` + `severity-rubric.md` | Any review. Non-negotiable. |
| 2 | `rtl-style-guide/SKILL.md` | Any generation or modification. |
| 3 | The matching golden template | Generation, per the retrieval table. |
| 4 | The checklist file(s) for the categories in play | Review. |
| 5 | The matching anti-pattern file | Generation and review of that construct. |
| 6 | `self-critique.md` | Before any approval. Short; always fits. |
| 7 | Other templates and anti-pattern files | Only if clearly relevant. |

**Mapping**

| Task | Inject |
|---|---|
| RTL generation | style guide |
| RTL review | review-signoff + all five checklists + severity rubric + self-critique |
| FIFO generation | FIFO template + `ap-protocol.md` |
| CDC logic | `golden_sync_2ff.sv` + `checklist-reset-cdc.md` + `ap-cdc.md` |
| Async FIFO | `golden_fifo_async.sv` + `golden_sync_2ff.sv` + `checklist-reset-cdc.md` + `ap-cdc.md` |
| FSM generation | `golden_fsm.sv` + `ap-fsm.md` |
| Arbiter | `golden_rr_arbiter.sv` + `ap-protocol.md` (ARB section) |
| Handshake | `golden_ready_valid.sv` + `ap-protocol.md` (PROTO section) |
| Debug | `rtl-anti-patterns/SKILL.md` index + the symptom-matched file |

**Limits**
- At most **3** golden templates (retrieval cap) and **2** anti-pattern files.
- Load a checklist file when its categories are in play; load all five for a signoff.
- Never load all seven anti-pattern files at once. The index plus the matched file is
  the whole point of having an index.

**Compression, in order of preference**
1. Load the specific checklist file, not the whole review skill tree.
2. Load the index table from `rtl-anti-patterns/SKILL.md` and only the matched file.
3. For templates, the header block (Purpose / When to use / Review focus / Common
   mistakes) carries most of the value — read the body only when adapting the code.
4. Compress the *findings*, never the *checks*. A skipped check is a missed bug; a
   terse finding is still a finding.

---

## 9. Confidence and escalation

Hallucination in RTL review has one specific shape: **a confident claim about
something no tool verified.** The defence is to track where each conclusion came from
and escalate when the answer is not actually available.

```python
THRESHOLD = 0.70

def assess(review):
    if review.cdc.confidence   < THRESHOLD: escalate("CDC unanalysable")
    if review.reset.confidence < THRESHOLD: escalate("reset architecture unknown")
    if review.spec.ambiguous:               ask_or_document_assumption()
    if review.multiple_valid_readings:      document_all_and_pick_one_explicitly()
    if review.tool == "none":               cap_at("APPROVED_WITH_CHANGES")
```

**What lowers confidence**

| Signal | Effect |
|---|---|
| A clock whose source or relationship is not visible | CDC confidence → below threshold |
| More than one clock and no documented relationship | CDC → below threshold |
| A reset whose generation is outside the file | reset → below threshold |
| Submodules not available (`--ignore-unknown-modules` did real work) | cap at `APPROVED_WITH_CHANGES` |
| `bin/rtl-lint` reports `TOOL=none` | cap at `APPROVED_WITH_CHANGES`, say so |
| The request permits two different behaviours | document both, pick one explicitly |
| A protocol named but not specified ("AXI-like") | name the clauses checked, flag the rest |

**Expert review recommendations.** When escalating, say *who* should look and at
*what* — "CDC engineer: the `cfg_update` crossing at line 84 has no visible
mechanism and I cannot see `cfg_clk`'s source" is actionable. "Needs human review"
is not.

**Risk reporting.** Every escalation carries: what is uncertain, why it could not be
resolved here, what would resolve it (a tool run, a spec clause, a file), and what
breaks if the optimistic reading is wrong.

**Never resolve uncertainty by picking the plausible answer and sounding sure.** That
is precisely the failure this entire repository exists to prevent.
