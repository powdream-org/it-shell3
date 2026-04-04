# Implementation Skill Redesign: Fork-Based Step Isolation

**Goal:** Restructure the `/implementation` skill so that Steps 6-9 execute in
isolated fork contexts, returning structured JSON results instead of polluting
the team leader's context with intermediate work products.

**Architecture:** Steps 6-9 are extracted from `steps/` into standalone
`context: fork` skills under `isolated/`. The team leader's SKILL.md gains a
master transition table that replaces per-step State Update/Next sections.
Target resolution logic moves from SKILL.md into a `context: direct` skill under
`direct/`.

**Tech Stack:** Claude Code skill markdown files (`.md`), `context: fork`
frontmatter for isolated execution, JSON return contracts.

**Spec references:**

- `docs/superpowers/specs/2026-04-03-implementation-skill-redesign.md`

---

## Scope

**In scope:**

1. Master transition table added to SKILL.md
2. Cross-Cutting Rules updated (reduced delegation rules for fork era)
3. Four isolated fork skills created (`impl-execute`, `impl-simplify`,
   `impl-review`, `impl-fix`)
4. One direct skill created (`impl-resolve-target`)
5. Old step files `steps/06~09.md` deleted
6. Target resolution removed from SKILL.md, replaced with skill invocation
7. SKILL.md Step Index updated to reference new skill locations
8. Non-fork step files (01-05, 10-15) modified: State Update/Next sections
   removed, verification commands added to Gate sections
9. Success Criteria section added to SKILL.md

**Out of scope:**

- Changes to non-fork step content beyond State Update/Next removal and gate
  verification commands
- Changes to agent definition files (`.claude/agents/impl-team/`)
- Changes to other skills (`/triage`, `/simplify`,
  `/fix-code-convention-violations`)
- Modifications to `docs/work-styles/` or `docs/conventions/`
- Any Zig source code changes

## File Structure

| File                                                                | Action | Responsibility                                                                                                      |
| ------------------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------- |
| `.claude/skills/implementation/SKILL.md`                            | Modify | Add transition table, update Cross-Cutting Rules, update Step Index, remove target resolution, add success criteria |
| `.claude/skills/implementation/isolated/impl-execute/SKILL.md`      | Create | Fork skill for Step 6 (implementation phase)                                                                        |
| `.claude/skills/implementation/isolated/impl-simplify/SKILL.md`     | Create | Fork skill for Step 7 (simplify + convention)                                                                       |
| `.claude/skills/implementation/isolated/impl-review/SKILL.md`       | Create | Fork skill for Step 8 (spec compliance review)                                                                      |
| `.claude/skills/implementation/isolated/impl-fix/SKILL.md`          | Create | Fork skill for Step 9 (fix cycle)                                                                                   |
| `.claude/skills/implementation/direct/impl-resolve-target/SKILL.md` | Create | Direct skill for target resolution                                                                                  |
| `.claude/skills/implementation/steps/06-implementation.md`          | Delete | Content migrated to `isolated/impl-execute/SKILL.md`                                                                |
| `.claude/skills/implementation/steps/07-simplify.md`                | Delete | Content migrated to `isolated/impl-simplify/SKILL.md`                                                               |
| `.claude/skills/implementation/steps/08-spec-compliance.md`         | Delete | Content migrated to `isolated/impl-review/SKILL.md`                                                                 |
| `.claude/skills/implementation/steps/09-fix-cycle.md`               | Delete | Content migrated to `isolated/impl-fix/SKILL.md`                                                                    |
| `.claude/skills/implementation/steps/01-requirements-intake.md`     | Modify | Remove State Update/Next, add verification commands to Gate                                                         |
| `.claude/skills/implementation/steps/02-plan-writing.md`            | Modify | Remove State Update/Next, add verification commands to Gate                                                         |
| `.claude/skills/implementation/steps/03-plan-verification.md`       | Modify | Remove State Update/Next, add verification commands to Gate                                                         |
| `.claude/skills/implementation/steps/04-cycle-setup.md`             | Modify | Remove State Update/Next, add verification commands to Gate                                                         |
| `.claude/skills/implementation/steps/05-scaffold-and-build.md`      | Modify | Remove State Update/Next, add verification commands to Gate                                                         |
| `.claude/skills/implementation/steps/10-coverage-audit.md`          | Modify | Remove State Update/Next, add verification commands to Gate                                                         |
| `.claude/skills/implementation/steps/11-over-engineering-review.md` | Modify | Remove State Update/Next, add verification commands to Gate                                                         |
| `.claude/skills/implementation/steps/12-commit-and-report.md`       | Modify | Remove State Update/Next, add verification commands to Gate                                                         |
| `.claude/skills/implementation/steps/13-owner-review.md`            | Modify | Remove State Update/Next, add verification commands to Gate                                                         |
| `.claude/skills/implementation/steps/14-retrospective.md`           | Modify | Remove State Update/Next, add verification commands to Gate                                                         |
| `.claude/skills/implementation/steps/15-cleanup.md`                 | Modify | Remove State Update/Next, add verification commands to Gate                                                         |

## Tasks

### Task 1: Add master transition table and transition rules to SKILL.md

**Files:** `.claude/skills/implementation/SKILL.md`

**Spec:** Spec Section 3 (Master Transition Table), Section 4 (Transition Rules)

**Depends on:** None

**Verification:**

- SKILL.md contains the full transition table from spec Section 3 with all rows
  (Steps 1-15 including 7.5 and 8.5)
- SKILL.md contains all 7 transition rules from spec Section 4
- The transition table includes all columns: From, Gate Source, Gate Result,
  TODO.md State Update, Next, Proceed
- Fork steps (6-9) reference fork JSON as gate source
- Non-fork steps reference command output or file check as gate source

### Task 2: Update SKILL.md Cross-Cutting Rules

**Files:** `.claude/skills/implementation/SKILL.md`

**Spec:** Spec Section 5 (Delegation Rules), Section 6 (Triage Quality Rules)

**Depends on:** Task 1

**Verification:**

- Delegation rules distinguish fork steps (6-9, structurally enforced) from
  non-fork steps (10-11, explicit constraints)
- Team leader MAY/MUST delegate lists from spec Section 5 are present for Steps
  10-11
- Triage quality rules from spec Section 6 are present (all 4 rules)
- Prior delegation rules that are now structurally enforced by fork are removed
  or replaced with a reference to fork isolation

### Task 3: Create four isolated fork skills

**Files:**

- `.claude/skills/implementation/isolated/impl-execute/SKILL.md`
- `.claude/skills/implementation/isolated/impl-simplify/SKILL.md`
- `.claude/skills/implementation/isolated/impl-review/SKILL.md`
- `.claude/skills/implementation/isolated/impl-fix/SKILL.md`

**Spec:** Spec Section 1 (Fork-Based Step Isolation), Section 2 (Fork Return
Contract), Section 7 (Directory Structure)

**Depends on:** None

**Verification:**

- Each skill file has `context: fork` in its frontmatter
- Each skill file contains the Anti-Patterns, Action, and Gate content from the
  corresponding old step file (06, 07, 08, 09)
- Each skill file does NOT contain State Update or Next sections (those are in
  the master transition table)
- Each skill file defines its JSON return contract matching the schema in spec
  Section 2
- The JSON envelope (`step`, `gate`, `checkpoint`, `payload`) matches the common
  envelope schema
- Each skill's `payload` fields match the per-step schema in spec Section 2
- `/impl-simplify` classifies violations via `in_current_plan` field; only
  `in_current_plan: false` items appear in `out_of_plan_violations`
- `/impl-review` includes `category` field (`CODE`, `TEST`, `CONV`) for routing
- `/impl-fix` includes `rounds_used`, `resolved`, `unresolved` fields
- `/impl-execute` includes `spec_gaps` array
- Gate verification commands are executed within the fork (not by the team
  leader)
- Checkpoint commits (code only) are performed within the fork

### Task 4: Create target resolution direct skill

**Files:** `.claude/skills/implementation/direct/impl-resolve-target/SKILL.md`

**Spec:** Spec Section 7 (Directory Structure — `direct/` directory)

**Depends on:** None

**Verification:**

- Skill file exists at
  `.claude/skills/implementation/direct/impl-resolve-target/SKILL.md`
- Contains the complete target resolution logic currently in SKILL.md (Steps 1-3
  of Target Resolution: discover all targets, match argument, resolve team
  directory)
- Frontmatter does NOT include `context: fork` (it runs in the team leader's
  context directly)
- The content is functionally equivalent to the current Target Resolution
  section in SKILL.md — no logic added or removed

### Task 5: Delete old step files (06-09)

**Files:**

- `.claude/skills/implementation/steps/06-implementation.md` (delete)
- `.claude/skills/implementation/steps/07-simplify.md` (delete)
- `.claude/skills/implementation/steps/08-spec-compliance.md` (delete)
- `.claude/skills/implementation/steps/09-fix-cycle.md` (delete)

**Spec:** Spec Migration Plan Task 5

**Depends on:** Task 3

**Verification:**

- All four files are deleted from the `steps/` directory
- No dangling references to these files remain in SKILL.md (checked in Task 7)

### Task 6: Remove target resolution from SKILL.md, add invocation reference

**Files:** `.claude/skills/implementation/SKILL.md`

**Spec:** Spec Migration Plan Task 6, Spec Section 7 (Directory Structure)

**Depends on:** Task 4

**Verification:**

- The "Target Resolution" section (Steps 1-3 with discovery commands, fuzzy
  matching, team directory resolution) is removed from SKILL.md
- SKILL.md contains a reference to invoke `direct/impl-resolve-target/SKILL.md`
  instead
- The Entry Point section still works (it references target resolution for
  initial resolution before checking TODO.md)

### Task 7: Update SKILL.md Step Index

**Files:** `.claude/skills/implementation/SKILL.md`

**Spec:** Spec Section 7 (Directory Structure — Step Index table)

**Depends on:** Task 3, Task 4, Task 5

**Verification:**

- Step Index table matches the spec's Step Index format with three columns:
  Step, Location, Execution
- Steps 1-5 reference `steps/01~05.md` with execution `team leader`
- Step 6 references `isolated/impl-execute/SKILL.md` with execution
  `context: fork`
- Step 7 references `isolated/impl-simplify/SKILL.md` with execution
  `context: fork`
- Step 8 references `isolated/impl-review/SKILL.md` with execution
  `context: fork`
- Step 9 references `isolated/impl-fix/SKILL.md` with execution `context: fork`
- Steps 10-15 reference `steps/10~15.md` with execution `team leader`
- Target resolution references `direct/impl-resolve-target/SKILL.md` with
  execution `direct`
- No references to deleted files (`steps/06~09.md`) remain anywhere in SKILL.md
- The old Step Index table (with File, Summary, Gate columns) is replaced

### Task 8: Modify non-fork step files

**Files:**

- `.claude/skills/implementation/steps/01-requirements-intake.md`
- `.claude/skills/implementation/steps/02-plan-writing.md`
- `.claude/skills/implementation/steps/03-plan-verification.md`
- `.claude/skills/implementation/steps/04-cycle-setup.md`
- `.claude/skills/implementation/steps/05-scaffold-and-build.md`
- `.claude/skills/implementation/steps/10-coverage-audit.md`
- `.claude/skills/implementation/steps/11-over-engineering-review.md`
- `.claude/skills/implementation/steps/12-commit-and-report.md`
- `.claude/skills/implementation/steps/13-owner-review.md`
- `.claude/skills/implementation/steps/14-retrospective.md`
- `.claude/skills/implementation/steps/15-cleanup.md`

**Spec:** Spec Section 8 (Non-Fork Step File Changes)

**Depends on:** Task 1

**Verification:**

- Every non-fork step file has its `## State Update` section removed entirely
- Every non-fork step file has its `## Next` section removed entirely
- Gate sections include exact verification commands per spec Section 8 format
  (command + expected output condition)
- State update values and next-step routing now exist only in the master
  transition table (Task 1)
- No step file references another step file directly (e.g., "Read
  `steps/08-spec-compliance.md`" is removed)
- Step files retain their Anti-Patterns, Action, and Gate sections

### Task 9: Add success criteria to SKILL.md

**Files:** `.claude/skills/implementation/SKILL.md`

**Spec:** Spec Success Criteria section

**Depends on:** All other tasks

**Verification:**

- SKILL.md contains a Success Criteria section with all 8 criteria from the spec
- Criteria are verifiable (observable in the next implementation cycle)
- The section is positioned after the transition table and rules sections

## Dependency Graph

```
Task 1 ─────────────────────────────┬──── Task 2
  │                                 │
  │                                 └──── Task 8
  │
Task 3 ──── Task 5
  │
Task 4 ──── Task 6
  │
  └──── Task 7 (depends on 3, 4, 5)
  │
  └──── Task 9 (depends on all)
```

Parallel groups:

- **Group A** (no dependencies): Tasks 1, 3, 4
- **Group B** (after Task 1): Tasks 2, 8
- **Group C** (after Task 3): Task 5
- **Group D** (after Task 4): Task 6
- **Group E** (after Tasks 3, 4, 5): Task 7
- **Group F** (after all): Task 9

## Summary

| Task | Files                                                          | Spec Section                                                                  |
| ---- | -------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| 1    | SKILL.md                                                       | §3 Master Transition Table, §4 Transition Rules                               |
| 2    | SKILL.md                                                       | §5 Delegation Rules, §6 Triage Quality Rules                                  |
| 3    | `isolated/impl-{execute,simplify,review,fix}/SKILL.md` (4 new) | §1 Fork-Based Step Isolation, §2 Fork Return Contract, §7 Directory Structure |
| 4    | `direct/impl-resolve-target/SKILL.md` (1 new)                  | §7 Directory Structure                                                        |
| 5    | `steps/06~09.md` (4 deleted)                                   | Migration Plan Task 5                                                         |
| 6    | SKILL.md                                                       | Migration Plan Task 6, §7 Directory Structure                                 |
| 7    | SKILL.md                                                       | §7 Directory Structure (Step Index)                                           |
| 8    | `steps/01~05.md`, `steps/10~15.md` (11 modified)               | §8 Non-Fork Step File Changes                                                 |
| 9    | SKILL.md                                                       | Success Criteria                                                              |
