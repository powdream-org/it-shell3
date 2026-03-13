---
name: design-doc-revision
description: Kick off a new design document revision cycle for one or more modules
argument-hint: <daemon|protocol|ime-contract> [daemon|protocol|ime-contract] ...
disable-model-invocation: true
---

# Design Document Revision Cycle

Kick off a new Revision Cycle for: **$ARGUMENTS**

Validate each argument is one of: `daemon`, `protocol`, `ime-contract`.
If invalid, show valid options and stop.

## Target Registry

| Target | Team Directory | Doc Base Path |
|--------|---------------|---------------|
| `daemon` | `.claude/agents/daemon-team/` | `docs/modules/libitshell3/02-design-docs/daemon/` |
| `protocol` | `.claude/agents/protocol-team/` | `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/` |
| `ime-contract` | `.claude/agents/ime-team/` | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/` |

Verification team (all targets): `.claude/agents/verification/`

## Step 1: Read Workflow Guides

Read these files **in full** before doing anything else:

- `docs/work-styles/03-design-workflow.md`
- `docs/work-styles/02-team-collaboration.md`

These are authoritative. The rest of this skill provides target-specific
context only — it does NOT override or replace the workflow guides.

## Step 2: Discover State

For **each** target:

1. `ls -la` the team directory (NOT Glob — symlinks!).
2. List version dirs under `<doc base path>/draft/`. Latest = highest
   `vX.Y-rN` (sort by X, then Y, then N). If no `draft/` exists yet, this
   is the first revision — next version is `v1.0-r1`.
3. Next version = increment N (e.g., `v1.0-r3` → `v1.0-r4`). Exception: if
   the previous cycle ended with a stable declaration (a `vX.Y/` dir was
   created since the last draft), start a new draft series — the owner
   decides the next version label (e.g., `v1.1-r1` or `v2.0-r1`) at Step 3.
4. Gather inputs from the latest draft version dir and inbox:
   - `draft/vX.Y-r<last>/handover/` (any `handover-to-*` doc)
   - `inbox/handover/` (any `handover-for-*` doc, if stable was previously declared)
   - `draft/vX.Y-r<last>/review-notes/*.md`
   - `draft/vX.Y-r<last>/cross-team-requests/`, `inbox/cross-team-requests/`,
     and `draft/v<next>-r1/cross-team-requests/` (if next dir already exists)
5. Also read the current stable spec docs from `vX.Y/` (if stable exists),
   as these are the authoritative base for the next revision.
6. Read all found inputs.

For multi-target: deduplicate agents shared across teams (symlinks).

## Step 3: Present to Owner

Summarize: targets, merged team composition, version transitions (e.g.,
`draft/v1.0-r3` → `draft/v1.0-r4`, or if stable was declared: `v1.0 STABLE` →
`draft/v?.?-r1` pending owner decision), one-line per input found. Ask for
additional requirements. **Wait before proceeding.**

## Step 4: Prepare Next Version Directory

For **each** target:

1. Create `draft/vX.Y-r<next>/` directory (e.g., `draft/v1.0-r4/` or
   `draft/v1.1-r1/`) if it doesn't exist. Use the version label confirmed by
   the owner in Step 3.
2. Copy all spec documents (`[0-9]+-*.md`, excluding `TODO.md`) from the
   previous draft version dir (`draft/vX.Y-rN/`) into the new dir. Do NOT
   copy subdirectories (`handover/`, `review-notes/`, `verification/`,
   `design-resolutions/`, `research/`, `cross-team-requests/`).
3. Create `draft/vX.Y-r<next>/TODO.md`. For multi-target: secondary targets' TODO
   files cross-reference the primary TODO (protocol v0.8 + IME v0.7 precedent).

## Step 5: Execute Revision Cycle

Follow the workflow guides read in Step 1, starting from Section 3.2.
