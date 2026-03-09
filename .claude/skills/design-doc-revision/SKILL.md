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
2. List version dirs under doc base path. Latest = highest `v0.X` or `vN`.
3. Next version = increment minor.
4. Gather inputs from latest version:
   - `v<latest>/handover/handover-to-v<next>.md`
   - `v<latest>/review-notes/*.md`
   - `v<latest>/cross-team-requests/` and `v<next>/cross-team-requests/`
5. Read all found inputs.

For multi-target: deduplicate agents shared across teams (symlinks).

## Step 3: Present to Owner

Summarize: targets, merged team composition, version transitions, one-line per
input found. Ask for additional requirements. **Wait before proceeding.**

## Step 4: Prepare Next Version Directory

For **each** target:

1. Create `v<next>/` directory (if it doesn't exist).
2. Copy all spec documents (`*.md` excluding `TODO.md`) from `v<latest>/` into
   `v<next>/`. Do NOT copy subdirectories (`handover/`, `review-notes/`,
   `verification/`, `design-resolutions/`, `research/`, `cross-team-requests/`).
3. Create `v<next>/TODO.md`. For multi-target: secondary targets' TODO files
   cross-reference the primary TODO (protocol v0.8 + IME v0.7 precedent).

## Step 5: Execute Revision Cycle

Follow the workflow guides read in Step 1, starting from Section 3.2.
