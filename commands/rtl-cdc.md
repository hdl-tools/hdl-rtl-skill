---
description: Deep clock-domain-crossing analysis, upgrading CDC findings from reasoning to tool-backed
---

Run CDC analysis on: $ARGUMENTS

1. `bin/rtl-cdc $ARGUMENTS`.
2. **Regardless of whether a tool was found**, do the structural review, because
   it catches the most common CDC bug without any tool:
   - Enumerate every clock by name.
   - For every signal, name its driving domain and each reading domain.
   - Every signal whose driver and reader domains differ **is a crossing** —
     list it explicitly. A crossing you did not list is one you did not review.
   - For each crossing, name its mechanism and check it against
     `skills/rtl-review-signoff/references/checklist-reset-cdc.md` and
     `skills/rtl-anti-patterns/patterns/ap-cdc.md`.
3. Report each crossing with its mechanism and verdict. Correct crossings are
   INFO findings — record them so the integrator inherits the list.

If `bin/rtl-cdc` reports `NOT_AVAILABLE`, say so plainly and keep every CDC
finding labelled `[reasoning] UNVERIFIED`. Per `severity-rubric.md` a
reasoning-only CDC conclusion is not sufficient for tape-out.

If you cannot see a clock's source, or two clocks have no documented
relationship, CDC confidence is below threshold: emit
`MANUAL_REVIEW_REQUIRED` and list the specific unknowns.
