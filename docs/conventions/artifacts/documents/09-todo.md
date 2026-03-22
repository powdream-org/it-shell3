# TODO Documents

## Location and Naming

```
draft/vX.Y-rN/TODO.md
```

One TODO per draft version. Created at the start of the Revision Cycle (Step 1
Requirements Intake) and updated at every step transition.

## Purpose

The TODO is the **state checkpoint** for the revision cycle. It tells the team
leader:

1. **Where am I?** — Which step is current
2. **What round?** — Which verification round (if in verification loop)
3. **Who is alive?** — Active team name and directory (for compaction recovery)
4. **What's done?** — Progress checkboxes

It is the **first thing read** when resuming after compaction or session loss.
The `design-doc-revision` skill's Entry Point reads TODO.md before any other
action.

## File Format

```markdown
# {Target} vX.Y-rN TODO

## Current State

- **Step**: {N} ({Step Name})
- **Verification Round**: {N}
- **Active Team**: {team-name} or (none)
- **Team Directory**: {~/.claude/teams/team-name} or (none)

## Progress

- [x] Step 1: Requirements Intake
- [x] Step 2: Team Discussion & Consensus
- [x] Step 3: Resolution & Verification
- [ ] Step 4: Assignment & Writing
- [ ] Step 5: Verification (Round 1)
- [ ] Step 6: Fix Round Decision
- [ ] Step 7: Commit & Report
- [ ] Step 8: Retrospective
```

## Current State Section

The `Current State` section is the **machine-readable state** of the cycle.
Every step transition MUST update all four fields:

| Field                  | When to update                                                   |
| ---------------------- | ---------------------------------------------------------------- |
| **Step**               | At every step transition. Format: `{N} ({Step Name})`            |
| **Verification Round** | Increment when entering Step 5. Reset to 0 when entering Step 7. |
| **Active Team**        | Set when spawning a team. Clear to `(none)` when disbanding.     |
| **Team Directory**     | Set when spawning a team. Clear to `(none)` when disbanding.     |

**Why Active Team and Team Directory matter:** After compaction, the team leader
loses awareness of spawned agents. These fields allow immediate recovery —
`SendMessage` to the team directory to verify members are alive instead of
blindly deleting.

## Progress Section

Steps map 1:1 to the `design-doc-revision` skill step files. For verification
rounds beyond Round 1, add additional entries:

```markdown
- [x] Step 5: Verification (Round 1)
- [x] Step 6: Fix Round Decision (→ fix round)
- [x] Step 4: Assignment & Writing (Round 2)
- [ ] Step 5: Verification (Round 2)
```

## Rules

1. **Steps map to skill step files.** Each Progress item corresponds to a step
   in `.claude/skills/design-doc-revision/steps/`.

2. **Update Current State at every step transition.** This is not optional. The
   skill's Entry Point depends on this being accurate.

3. **Update checkboxes as you go.** Mark steps `[x]` when their Gate conditions
   are met.

4. **Cancelled steps use strikethrough.** Use `~~Step N: Name~~ — {Reason}`. Do
   not delete cancelled steps.

5. **No prose in TODO.** Keep it to Current State, Progress checkboxes, and
   cancelled step annotations. Context belongs in handover documents.

## Example

```markdown
# Protocol v1.0-r7 TODO

## Current State

- **Step**: 5 (Verification)
- **Verification Round**: 2
- **Active Team**: (none)
- **Team Directory**: (none)

## Progress

- [x] Step 1: Requirements Intake
- [x] Step 2: Team Discussion & Consensus
- [x] Step 3: Resolution & Verification
- [x] Step 4: Assignment & Writing
- [x] Step 5: Verification (Round 1) — 3 confirmed issues
- [x] Step 6: Fix Round Decision (→ fix round)
- [x] Step 4: Assignment & Writing (Round 2)
- [ ] Step 5: Verification (Round 2)
- [ ] Step 6: Fix Round Decision
- [ ] Step 7: Commit & Report
- [ ] Step 8: Retrospective
```

## Anti-Patterns

| Anti-pattern                              | Problem                                                                                                 | Correct approach                                              |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| No TODO.md                                | New session has no idea where to resume                                                                 | Always create at Step 1 Requirements Intake                   |
| Missing Current State section             | After compaction, team leader cannot determine which step to resume from                                | Always include Current State with all 4 fields                |
| Not updating Active Team / Team Directory | After compaction, team leader assumes agents are dead and deletes team directory, creating real zombies | Update these fields every time a team is spawned or disbanded |
| TODO with prose paragraphs                | Hard to scan, mixes tracking with documentation                                                         | Checkboxes only; prose goes in handover                       |
| Deleting completed steps                  | Loses history of what was done                                                                          | Keep completed steps with `[x]` marks                         |
| Never updating checkboxes                 | TODO diverges from reality                                                                              | Update after each step's Gate is met                          |
| Not updating after verification rounds    | Stale TODO fails as resumption point across sessions                                                    | Mark each round's steps complete immediately                  |
