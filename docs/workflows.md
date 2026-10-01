# Workflows

Diagrams for the five flows. The authoritative rules — trigger tables, confidence
scoring, retry guards, context injection limits — live in `skills/rtl-workflow/SKILL.md`.
This file is the picture.

---

## 1. Creation

```
   user request
        |
        v
  +-----------------+   score < 0.15 -> not RTL, answer normally
  | trigger scoring |   0.15-0.39    -> answer, offer the review
  +--------+--------+   0.40-0.69    -> style guide, gate if code produced
           | >= 0.70
           v
  +-----------------------------------------------+
  | CONTEXT INJECTION  (priority order)           |
  |  1 rtl-style-guide          always            |
  |  2 golden template(s)       max 3, by score   |
  |  3 anti-pattern file(s)     max 2, matched    |
  +--------+--------------------------------------+
           v
  +-----------------+
  | generate RTL    |  adapt the template; never write from memory
  +--------+--------+
           v
  ####### Write/Edit *.sv  ->  hooks/rtl_gate.sh  #######
           |
           v
  +-----------------+
  | bin/rtl-lint    |  slang, FULL elaboration, -Weverything
  +--------+--------+
           v
  +-----------------------------+
  | 20 categories               |
  | 11 self-critique questions  |
  | severity rubric             |
  +--------+--------------------+
           v
      +----+----+
      | decide  |
      +----+----+
           |
  +--------+---------+-----------------+------------------+
  |                  |                 |                  |
APPROVED    APPROVED_WITH_CHANGES   REJECTED    MANUAL_REVIEW_REQUIRED
  |                  |                 |                  |
output              auto-fix  <--------+            report honestly,
                     |                               name the unknowns
                     v
              FULL re-review  --(loop<3, improving)--> decide
                     |
                     +--(loop==3 | regression | no progress | intent drift)
                                 -> MANUAL_REVIEW_REQUIRED
```

## 2. Modification

```
request + existing file
        |
        v
  read the file FULLY, header contract included
        |
        v
  inject style guide -- but MATCH THE FILE's dialect
        |            (a V2001 file gets another always @(posedge clk);
        |             the style note is LOW, not a reason to mix dialects)
        v
  apply the minimal change
        |
        v
  GATE -- reviews the WHOLE file, never just the diff
        |     (a two-line change can break a CDC assumption 50 lines away)
        v
  decide -> auto-fix -> full re-review  [as above]
```

## 3. Review only

```
"review this" / pasted module
        |
        v
  bin/rtl-lint FIRST          <- evidence before opinion, deliberately:
        |                        anchoring on a first read makes evidence
        v                        something to overcome rather than to use
  read the RTL against the contract
        |
        v
  20 categories (all five checklist files)
        |
        v
  11 self-critique questions
        |
        v
  classify: severity + tier + concrete failure scenario
        |
        v
  signoff recommendation + written assumptions + UNVERIFIED labels
```

## 4. Debug

```
symptom
   |
   v
 restate it precisely
   |   "fails after hours"  != "fails every time"  != "fails under load"
   v
 symptom -> candidate anti-patterns        <- the table in rtl-workflow SKILL.md
   |
   v
 bin/rtl-lint      (cheap; occasionally just answers it)
   |
   v
 FULL review hook  (the reported symptom is not necessarily the bug)
   |
   v
 root cause = the MECHANISM, not the line number
   |
   v
 fix -> FULL re-review     (a fix is new RTL)
```

## 5. Optimisation

```
 state the constraint WITH A NUMBER
   |
   v
 confirm the baseline reviews CLEAN     <- never optimise broken RTL
   |
   v
 ONE transform (retime / share / re-encode / gate)
   |
   v
 FULL review hook
   |
   v
 re-check the INTERFACE CONTRACT        <- the optimisation-specific failure:
         latency, throughput,              a register inserted to break a path
         handshake rules                   adds a cycle. If the contract did not
                                           say so, every consumer is now wrong.
```

---

## Where the gate must not fire

| Situation | Reason |
|---|---|
| `*_tb.sv`, `tb_*.sv`, `*_test.sv` | Testbenches have opposite rules — `#delay`, `initial`, blocking assignments are all correct there. |
| `.f`, `.tcl`, `.sdc`, docs, Makefiles | Not RTL. |
| Comment-only / whitespace-only diff | No logic changed. |
| Generated or vendor do-not-edit IP | Review on request; do not gate regeneration. |
| User says "skip review" | Their call. Say it once, then comply. |
| Talking about RTL with no code in play | A conversation is not a design. |

This list is load-bearing. A gate that fires on testbenches and comment changes gets
switched off — and then it protects nothing at all.
