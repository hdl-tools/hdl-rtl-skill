---
description: Run deterministic RTL lint (slang, optionally VCS) and map findings to severities
---

Run RTL lint on: $ARGUMENTS

1. `bin/rtl-lint $ARGUMENTS` — slang with full elaboration and `-Weverything`,
   severities mapped from `hooks/slang-warnings.txt`.
2. Report each finding with its severity, category, location and the slang
   option name that produced it.
3. If a finding comes back as `Unclassified`, add it to
   `hooks/slang-warnings.txt` with a severity and category so it is classified
   next time. Never drop an unfamiliar warning.

**Do not substitute `--lint-only` for the full elaboration.** It is faster and
it silently loses `-Winferred-latch` and multiple-driver detection — latch
inference being the single highest-value check here. This is verified and
recorded in `hooks/slang-warnings.txt`.

A clean lint is **not** a signoff. For that, use `/rtl-review`.
