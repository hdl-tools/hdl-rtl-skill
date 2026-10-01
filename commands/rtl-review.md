---
description: Full 20-category RTL review and signoff on one or more Verilog/SystemVerilog files
---

Run a complete RTL review signoff on: $ARGUMENTS

Follow `skills/rtl-review-signoff/SKILL.md` exactly, in this order:

1. **Evidence first.** Run `bin/rtl-lint <files>` and quote its output verbatim.
   Do not form an opinion before you have the tool result.
2. **Read the RTL** line by line against the request or the module's own header
   contract.
3. **All 20 categories**, loading every checklist file in
   `skills/rtl-review-signoff/references/`. Mark any N/A category with a
   one-line reason.
4. **All 11 self-critique questions** from `references/self-critique.md`. Every
   YES gets Risk / Impact / Severity / Mitigation.
5. **Classify** per `references/severity-rubric.md`.
6. **Decide**: APPROVED / APPROVED_WITH_CHANGES / REJECTED /
   MANUAL_REVIEW_REQUIRED, with the counts and the reason.

Tag every finding with its tier: `[slang]` (quote the option name),
`[spyglass]`, or `[reasoning]` — and label every reasoning-tier finding
**UNVERIFIED**. slang checks none of CDC, reset release, arithmetic overflow,
FSM reachability, protocol deadlock, arbitration fairness, or blocking
assignments in clocked blocks.

If `bin/rtl-lint` reports `TOOL=none`, say so and cap the outcome at
APPROVED_WITH_CHANGES. Never present a reasoning-only review as a signoff.
