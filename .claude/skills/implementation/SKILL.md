---
name: implementation
description: >
  Drive an implementation cycle — transforming a stable design spec into
  production code with comprehensive test coverage. Use when the owner says
  "implement <target>", "start coding <target>", "build <target>", or when
  transitioning from design to code for any module or application. Also triggers
  on `/implement <target>`.
argument-hint: "<target>"
---

# Implementation Cycle

Target: **$ARGUMENTS**

## Target Resolution

Targets are resolved by **filesystem discovery** across all source directories.

### Step 1: Discover all targets

Targets live across three top-level directories with different structures:

```bash
# Libraries — each subdirectory is a target
ls -d modules/*/ 2>/dev/null

# Daemon — the directory itself is a target (contains build.zig + main.zig)
ls daemon/build.zig 2>/dev/null && echo "daemon/"

# Client apps — each subdirectory is a target
ls -d app/*/ 2>/dev/null
```

This produces paths like `modules/libitshell3-ime/`, `daemon/`, `app/macos/`.
These paths are the **target directories**.

### Step 2: Match argument to target

Fuzzy-match the argument against discovered target directory names. Examples
(not exhaustive — always discover from filesystem):

- `ime` → `modules/libitshell3-ime`
- `protocol` → `modules/libitshell3-protocol`
- `client` or `client-sdk` → `modules/libitshell3-client`
- `core` or `libitshell3` → `modules/libitshell3`
- `daemon` → `daemon`
- `macos` or `app` → `app/macos`

If no match or ambiguous, show all discovered targets and ask the user to
clarify. If the target directory does not exist yet, confirm with the user that
this is a new target before proceeding (Step 1 will create it).

The resolved path (e.g., `modules/libitshell3-ime`) is referred to as `<target>`
throughout all step files.

### Step 3: Resolve team directory

Implementation teams use a shared agent directory: `.claude/agents/impl-team/`.

Use `ls -la` on the team directory to discover members (may include symlinks).

## Entry Point — ALWAYS Start Here

**This is the first thing you do, whether starting fresh or resuming after
compaction.**

1. Check if `<target>/TODO.md` exists.
2. **If TODO.md exists** → Read it. The `Current State` section tells you:
   - Which step you are on
   - Which review round (if in review loops)
   - Active team name and team directory path
   - **If an active team is listed → `SendMessage` to verify members are alive
     BEFORE any other action. NEVER delete a team directory without confirmed
     non-response.**
   - Resume from the current step: Read the corresponding step file.
3. **If no TODO.md exists** → New cycle. Read `steps/01-requirements-intake.md`.

## Step Index

Each step file contains: anti-patterns, action instructions, gate conditions,
and TODO.md state update instructions. Read **only the current step's file** —
do not pre-read future steps.

| Step | File                                  | Summary                                      | Gate                                              |
| ---- | ------------------------------------- | -------------------------------------------- | ------------------------------------------------- |
| 1    | `steps/01-requirements-intake.md`     | Identify spec, plan, inputs; create TODO.md  | Owner approves, TODO.md created                   |
| 2    | `steps/02-scaffold-and-build.md`      | Create project skeleton; verify build chain  | `mise run test:macos` passes                      |
| 3    | `steps/03-implementation.md`          | Spawn implementer + QA; parallel work        | Both report complete, all tests pass              |
| 4    | `steps/04-simplify.md`                | Run `/simplify` (reuse, quality, efficiency) | Fixes applied, tests pass                         |
| 5    | `steps/05-spec-compliance.md`         | QA reviews all code against spec             | Clean pass or issue list produced                 |
| 6    | `steps/06-fix-cycle.md`               | Implementer fixes issues; QA re-validates    | All issues resolved → back to Step 5              |
| 7    | `steps/07-coverage-audit.md`          | Measure coverage; fill gaps                  | Targets met or exemption granted                  |
| 8    | `steps/08-over-engineering-review.md` | Principal architect reviews for KISS/YAGNI   | Clean → Step 9; code changed → back to Step 5     |
| 9    | `steps/09-commit-and-report.md`       | Commit code; report to owner                 | All gates green, code committed                   |
| 10   | `steps/10-owner-review.md`            | Owner evaluates; accepts or requests changes | Owner accepts → Step 11; changes → back to Step 3 |
| 11   | `steps/11-retrospective.md`           | Review cycle, update learnings, cleanup      | Learnings updated, artifacts deleted              |

## Regression Loop

Steps 5 → 6 → 7 → 8 form a verification chain. If Step 8 (Over-Engineering
Review) changes code, control returns to Step 5 (not Step 9). A single clean
pass through 5 → 7 → 8 must complete before reaching Step 9.

## Continuous Improvement Log

When the team leader encounters a procedural problem, spec-implementation
mismatch, improper facilitation, or skill gap at ANY point during the cycle,
immediately append it to
`<target>/retrospective/skill-improvement-proposals.md`. Create the file and
directory if they don't exist. Do not wait for the retrospective step — log
issues as they occur so they survive context compaction.

## Rationale & Reference

For **why** each phase exists (not **how** to execute it), see:

- `docs/work-styles/05-implementation-workflow.md` — Lifecycle, rationale,
  coverage standards, spec-to-code principles
- `docs/work-styles/02-team-collaboration.md` — Team rules, communication
- `docs/insights/implementation-learnings.md` — Zig toolchain lessons, testing
  strategy lessons
