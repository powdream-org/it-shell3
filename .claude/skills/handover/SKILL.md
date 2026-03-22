---
name: handover
description: Write or update a handover document at the end of a review cycle. Use when the owner declares a review complete and says "handover", "write handover", "wrap up", or asks to finalize a revision cycle. Also use after owner review cleanup sessions. Works for both creating new handovers and updating existing ones.
argument-hint: "[target keyword]"
tools: [Bash, Glob, Grep, Read, Write, Edit, AskUserQuestion]
---

# Handover

Target: **$ARGUMENTS**

## Target Resolution

Discover all doc topics that have a `draft/` directory:

```bash
find docs/modules -name "draft" -type d | sort
```

If the argument is provided, match it against the discovered paths (fuzzy —
"protocol" matches `server-client-protocols`, "ime behavior" matches `behavior`,
etc.). If ambiguous, ask the user to clarify.

If the argument is empty, infer the target from conversation context. Then use
AskUserQuestion to confirm: state the inferred target and whether this is a
**new** handover or an **update** to an existing one. Do not proceed without
explicit confirmation.

## Required Reads

Read these before doing anything else:

1. `docs/conventions/artifacts/documents/03-handover.md` — format, exclusion
   rules, post-handover procedure. This is the authoritative guide.
2. `docs/work-styles/03-design-workflow/02-review-cycle.md` §4.3 — when and
   where handover is written.
3. `docs/insights/design-principles.md` — existing P/A/L entries. Without
   knowing what already exists, you cannot judge whether this cycle's insights
   are new or reinforce existing principles. The post-handover update step
   depends on this.

## Execution

Find the latest `draft/vX.Y-rN/` under the resolved target path. If a handover
already exists there, this is an update — read the existing file first.

Follow the guides for everything else: gathering artifacts, structuring the 5
sections, placing the file, and updating design-principles.md afterward.
