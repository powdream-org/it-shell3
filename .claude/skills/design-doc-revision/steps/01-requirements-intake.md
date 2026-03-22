# Step 1: Requirements Intake

## Anti-Patterns

- Do NOT skip TODO.md creation — it is the state checkpoint for the entire
  cycle.
- Do NOT use Glob to discover team members — use `ls -la` (symlinks!).

## Action

### 1a. Discover state for each target

For each target in the Target Registry:

1. `ls -la` the team directory to discover all members (including symlinks).
2. List version dirs under `<doc base path>/draft/`. Latest = highest `vX.Y-rN`.
   If no `draft/` exists, this is the first revision → next version is
   `v1.0-r1`.
3. Next version = increment N (e.g., `v1.0-r3` → `v1.0-r4`). Exception: if the
   previous cycle declared stable (a `vX.Y/` dir exists), start a new draft
   series — the owner decides the version label at step 1b.
4. Gather inputs from the latest draft version dir and inbox:
   - `draft/vX.Y-r<last>/handover/` (any `handover-to-*` doc)
   - `inbox/handover/` (any `handover-for-*` doc)
   - `draft/vX.Y-r<last>/review-notes/*.md`
   - `draft/vX.Y-r<last>/cross-team-requests/`, `inbox/cross-team-requests/`,
     and `draft/v<next>-r1/cross-team-requests/` (if next dir already exists)
5. Read the current stable spec docs from `vX.Y/` (if stable exists).
6. Read all found inputs.

For multi-target: deduplicate agents shared across teams (symlinks).

### 1b. Present to owner

Summarize: targets, merged team composition, version transitions, one-line per
input found. Ask for additional requirements. **Wait for owner response before
proceeding.**

### 1c. Prepare next version directory

For each target:

1. Create `draft/vX.Y-r<next>/` if it doesn't exist.
2. Copy spec documents (`[0-9]+-*.md`, excluding `TODO.md`) from the previous
   draft. Do NOT copy subdirectories.
3. Create `TODO.md` with the strict format below.

### 1d. Create TODO.md

Use this exact structure:

```markdown
# {Target} vX.Y-rN TODO

## Current State

- **Step**: 2 (Discussion)
- **Verification Round**: 0
- **Active Team**: (none)
- **Team Directory**: (none)

## Progress

- [x] Step 1: Requirements Intake — done
- [ ] Step 2: Team Discussion & Consensus
- [ ] Step 3: Resolution & Verification
- [ ] Step 4: Assignment & Writing
- [ ] Step 5: Verification (Round 1)
- [ ] Step 6: Fix Round Decision
- [ ] Step 7: Commit & Report
- [ ] Step 8: Retrospective
```

### 1e. Context check

Before spawning in Step 2, check if the remaining context window is **25% or
below**. If so, ask the owner: _"Context window is X% remaining. Run `/compact`
before spawning? (yes / no)"_ Wait for owner to run `/compact` and confirm.

## Gate

- [ ] Owner has approved scope and version label
- [ ] Next version directory created with spec docs copied
- [ ] TODO.md created with Current State pointing to Step 2

## State Update

TODO.md is created with Current State already set to Step 2 — no additional
update needed.

## Next

Read `steps/02-discussion.md`.
