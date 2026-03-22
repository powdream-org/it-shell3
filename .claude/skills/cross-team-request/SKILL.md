---
name: cross-team-request
description: Use when writing a cross-team request (CTR) targeting another team's design docs. Determines correct placement directory and filename convention based on target team state.
argument-hint: "[source-team] [target-topic]"
tools: [Bash, Glob, Grep, Read, Write, Edit, AskUserQuestion]
---

# Cross-Team Request

Source: **$ARGUMENTS**

## Required Read

Read before doing anything else:

`docs/conventions/artifacts/documents/07-cross-team-requests.md` — placement
rules (Case A/B/C), filename conventions, file format. This is the authoritative
guide.

## Target State Check

Determine which case applies by inspecting the target topic directory:

```bash
ls docs/modules/{target-module}/02-design-docs/{target-topic}/draft/
```

- **Has `vX.Y-rN/` directories** → Case A (active draft)
- **Directory does not exist** → Case B (new topic, create seed `r0`)
- **Only stable `vX.Y/` exists, no draft** → Case C (idle, use `inbox/`)

## Post-Write Checklist

After writing the CTR file, verify:

1. Ran `ls` on target topic's `draft/` before choosing placement?
2. `-from-v{X.Y}` suffix present ONLY if Case C (inbox)?
3. If Case B: `handover-to-r1.md` also created in `draft/v1.0-r0/handover/`?
