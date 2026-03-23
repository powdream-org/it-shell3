---
name: design-doc-revision
description: Kick off or resume a design document revision cycle for one or more modules
argument-hint: "<target> [target] ..."
disable-model-invocation: true
---

# Design Document Revision Cycle

Targets: **$ARGUMENTS**

## Target Resolution

Targets are resolved by **filesystem discovery**, not a hardcoded list.

### Step 1: Discover all topics

```bash
find docs/modules -path "*/02-design-docs/*/draft" -type d | sort
```

This produces paths like
`docs/modules/libitshell3-ime/02-design-docs/behavior/draft`. The **topic name**
is the directory immediately before `draft/` (e.g., `behavior`, `daemon`,
`interface-contract`, `server-client-protocols`).

### Step 2: Match arguments to topics

For each argument, fuzzy-match against discovered topic names:

- `daemon` → `daemon`
- `protocol` → `server-client-protocols`
- `ime-contract` → `interface-contract`
- `ime-behavior` or `behavior` → `behavior`

If no match or ambiguous, show all discovered topics and ask the user to
clarify.

### Step 3: Resolve team directory

| Topic pattern                                | Team Directory                  |
| -------------------------------------------- | ------------------------------- |
| Under `libitshell3/02-design-docs/`          | `.claude/agents/daemon-team/`   |
| Under `libitshell3-protocol/02-design-docs/` | `.claude/agents/protocol-team/` |
| Under `libitshell3-ime/02-design-docs/`      | `.claude/agents/ime-team/`      |

Use `ls -la` on the team directory to discover members (symlinks!).

Verification agents (all targets): `.claude/agents/verification/`

### Adding new topics

When a new `draft/` directory appears under any module's `02-design-docs/`, it
is automatically discoverable. The only manual update needed is adding a team
directory mapping if a new module is created (not a new topic within an existing
module).

## Entry Point — ALWAYS Start Here

**This is the first thing you do, whether starting fresh or resuming after
compaction.**

1. For each target, check if `draft/vX.Y-rN/TODO.md` exists (use the latest
   `vX.Y-rN` directory).
2. **If TODO.md exists** → Read it. The `Current State` section tells you:
   - Which step you are on
   - Which verification round (if in verification)
   - Active team name and team directory path
   - **If an active team is listed → `SendMessage` to verify members are alive
     BEFORE any other action. NEVER delete a team directory without confirmed
     non-response.**
   - Resume from the current step: Read the corresponding step file.
3. **If no TODO.md exists** → New cycle. Read `steps/01-requirements-intake.md`.

## Step Index

Each step file contains: action instructions, inline anti-patterns, gate
conditions, and TODO.md state update instructions. Read **only the current
step's file** — do not pre-read future steps.

| Step | File                              | Summary                                                        | Gate                                        |
| ---- | --------------------------------- | -------------------------------------------------------------- | ------------------------------------------- |
| 1    | `steps/01-requirements-intake.md` | Discover state, present to owner, prepare dirs, create TODO.md | Owner approves, dirs ready, TODO.md created |
| 2    | `steps/02-discussion.md`          | Spawn team, peer-to-peer debate, consensus                     | Consensus reporter delivers unprompted      |
| 3    | `steps/03-resolution.md`          | Resolution doc written, all members verify, disband            | All members confirm, team disbanded         |
| 4    | `steps/04-writing.md`             | Leader assigns, spawn writers, writing gate                    | All assigned docs written, team disbanded   |
| 5    | `steps/05-verification.md`        | Phase 1 + Phase 2, verdicts collected                          | All issues have verdict                     |
| 6    | `steps/06-fix-round.md`           | Record issues, decide: fix round or clean                      | Fix → Step 4; Clean → Step 7                |
| 7    | `steps/07-commit-and-report.md`   | Commit, report to owner, STOP                                  | Commit done, owner notified                 |
| 8    | `steps/08-owner-review.md`        | Owner reviews docs, team leader supports                       | Owner signals review completion             |
| 9    | `steps/09-retrospective.md`       | Review cycle, propose skill improvements                       | Improvements applied or none needed         |

## Continuous Improvement Log

When the team leader encounters a procedural problem, improper facilitation, or
skill gap at ANY point during the cycle, immediately append it to
`draft/vX.Y-rN/retrospective/skill-improvement-proposals.md`. Create the file
and directory if they don't exist. Do not wait for the retrospective step — log
issues as they occur.

## Rationale & Reference

For **why** each step exists (not **how** to execute it), see:

- `docs/work-styles/03-design-workflow/` — Lifecycle, rationale, anti-patterns
- `docs/work-styles/02-team-collaboration.md` — Team rules, communication
