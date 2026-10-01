---
name: rtl-review-signoff
description: "Mandatory RTL review and signoff for Verilog/SystemVerilog. Load before approving, committing, or presenting ANY generated or modified .v/.sv/.svh file, and whenever asked to review, audit, check, or debug RTL. Runs 20 review categories: functional intent, syntax, synthesizability, sequential, combinational, latch, FSM, case, reset, CDC, width, signedness, arithmetic, X/Z, parameter, protocol, lint, DFT, power, maintainability. Produces severity-classified findings (BLOCKER/HIGH/MEDIUM/LOW/INFO) and a signoff decision. Keywords: rtl review, code review verilog, signoff, lint, cdc, reset, width mismatch, latch, fsm, deadlock, review escape, tapeout."
metadata:
  type: mandatory-hook
  enforced-by: hooks/rtl_gate.sh
  evidence-tool: "slang (bin/rtl-lint) -- deterministic findings; everything else is reasoning"
---

# RTL Review Signoff

## Standing assumption

**The RTL is wrong until shown otherwise — including, especially, RTL you just
wrote yourself.** Your own generated code gets a *harder* review than a human's,
because you have no simulation waveform, no bring-up scar tissue, and a strong
bias toward believing your first answer.

Review as nine people in sequence. Each one is looking for something the others
are not:

| Reviewer | Asks |
|---|---|
| Senior RTL engineer | Does this synthesise to the hardware I think it does? |
| System architect | Does this implement the *specified* behaviour, or a plausible neighbour of it? |
| Verification engineer | What stimulus breaks this? What is untestable? |
| CDC engineer | Which signals cross domains, and is each crossing structurally safe? |
| Synthesis engineer | What will the tool build, where is the critical path, what gets optimised away? |
| Lint engineer | What does a ruleset flag, and is each waiver justified? |
| DFT engineer | Is every flop scannable and controllable? |
| Power engineer | What toggles when nothing is happening? |
| Silicon debug engineer | When this fails in the lab, what observable tells me why? |

---

## Non-negotiable process

```
1. GATHER EVIDENCE   bin/rtl-lint <files>        <- run it, do not imagine it
2. READ THE RTL      line by line, against the request
3. RUN 20 CATEGORIES references/checklist-*.md
4. SELF-CRITIQUE     references/self-critique.md  <- all 11 questions, every time
5. CLASSIFY          references/severity-rubric.md
6. DECIDE            signoff decision + reasons
```

**Step 1 is not optional and its output must be quoted, not paraphrased.** A
finding you did not get from a tool and cannot derive from the code in front of
you is a hallucination. Three tiers, and every finding must carry its tier:

- `[slang]` — proven by `bin/rtl-lint`. Quote the message and the option name.
- `[spyglass]` / `[vcs]` — from an opt-in deep run (`/rtl-cdc`, `/rtl-lint`).
- `[reasoning]` — your analysis. **Must be labelled `UNVERIFIED`.** CDC, reset
  sequencing, FSM reachability, protocol deadlock, arbitration fairness and
  arithmetic overflow are *all* in this tier — slang does not check any of them
  (verified by probe; see `hooks/slang-warnings.txt`).

If `bin/rtl-lint` reports `TOOL=none`, say so in the report. Do not present a
reasoning-tier review as though a tool had backed it.

---

## The 20 categories

Load the reference file for the group you are reviewing. For a full signoff,
load all five.

| # | Category | Reference | Primary tier |
|---|---|---|---|
| 1 | Functional Intent | `checklist-core.md` | reasoning |
| 2 | Syntax | `checklist-core.md` | slang |
| 3 | Synthesizability | `checklist-core.md` | reasoning |
| 4 | Sequential Logic | `checklist-core.md` | mixed |
| 5 | Combinational Logic | `checklist-core.md` | mixed |
| 6 | Latch | `checklist-core.md` | **slang** |
| 7 | FSM | `checklist-core.md` | reasoning |
| 8 | Case Statement | `checklist-core.md` | slang |
| 9 | Reset | `checklist-reset-cdc.md` | reasoning |
| 10 | CDC | `checklist-reset-cdc.md` | reasoning |
| 11 | Width | `checklist-datapath.md` | **slang** |
| 12 | Signedness | `checklist-datapath.md` | **slang** |
| 13 | Arithmetic | `checklist-datapath.md` | reasoning |
| 14 | X/Z | `checklist-datapath.md` | reasoning |
| 15 | Parameter | `checklist-integration.md` | reasoning |
| 16 | Protocol | `checklist-integration.md` | reasoning |
| 17 | Lint | `checklist-integration.md` | slang |
| 18 | DFT | `checklist-backend.md` | reasoning |
| 19 | Power | `checklist-backend.md` | reasoning |
| 20 | Maintainability | `checklist-backend.md` | slang+reasoning |

**Never skip a category because the code "looks simple".** Categories 9, 10, 13,
16 and 19 are where post-silicon escapes come from, and none of them is visible
in a quick read.

---

## Severity, in one line each

Full definitions, thresholds and gate logic: `references/severity-rubric.md`.

| | Meaning | Gate |
|---|---|---|
| **BLOCKER** | Design is functionally wrong, unsynthesisable, or will not come up. | **REJECT** |
| **HIGH** | A real bug under identifiable conditions, or a structural CDC/reset risk. | Approve with required changes; **REJECT at >= 3** |
| **MEDIUM** | Latent risk, fragile construct, or missing protection. | Warn, record |
| **LOW** | Style or clarity issue with a maintenance cost. | Suggest |
| **INFO** | Observation, assumption recorded, or a note for the integrator. | Record |

---

## Signoff decision

Emit exactly one, with its reasons:

- **`APPROVED`** — zero BLOCKER, zero HIGH, every self-critique YES mitigated,
  and no `[reasoning]` finding left at low confidence.
- **`APPROVED_WITH_CHANGES`** — 1–2 HIGH, all with a concrete named fix. The
  changes are mandatory, not advisory.
- **`REJECTED`** — any BLOCKER, or >= 3 HIGH.
- **`MANUAL_REVIEW_REQUIRED`** — CDC or reset confidence below threshold, a
  genuinely ambiguous spec, or 3 auto-fix rounds exhausted. **This is a valid
  and respectable outcome. Escalating beats guessing.**

### Approval criteria — all must hold
1. `bin/rtl-lint` was actually run, and its output is quoted.
2. All 20 categories considered; any marked N/A says why in one line.
3. All 11 self-critique questions answered, each YES carrying
   Risk / Impact / Severity / Mitigation.
4. Every `[reasoning]` finding is labelled `UNVERIFIED`.
5. Every assumption made about an unstated requirement is written down.
6. For CDC: every crossing enumerated by name, with its mechanism.
7. For resets: polarity, sync/async, and release behaviour stated per domain.

**Never write `APPROVED` to be agreeable.** An approval that is wrong is worse
than a rejection that is annoying — it is the last gate before the bug reaches
silicon.

---

## Report format

```
RTL REVIEW -- <file>
Evidence: slang <version> | <N> findings | TOOL=<tool>

FINDINGS
[BLOCKER] <category> -- <file>:<line>
  What:  <the defect>
  Why:   <failure scenario: concrete inputs/state -> wrong behaviour>
  Fix:   <the specific change>
  Tier:  [slang -Wname] | [reasoning] UNVERIFIED

SELF-CRITIQUE   (references/self-critique.md)
  Q4 signedness ....... YES -> Risk/Impact/Severity/Mitigation
  Q1 latches .......... NO  (slang clean, -Winferred-latch)

ASSUMPTIONS
  - <unstated requirement I assumed, and what breaks if wrong>

DECISION: <APPROVED | APPROVED_WITH_CHANGES | REJECTED | MANUAL_REVIEW_REQUIRED>
  BLOCKER=<n> HIGH=<n> MEDIUM=<n> LOW=<n> INFO=<n>
  Reason: <one or two sentences>
```

A finding without a concrete failure scenario is not a finding — it is a
preference. Delete it or demote it to LOW.
