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
   If a plan already exists, Step 1 will direct you to skip Step 2 and go
   straight to Step 3 (Plan Verification).

## Step Index

Each step file contains: anti-patterns, action instructions, gate conditions,
and TODO.md state update instructions. Read **only the current step's file** —
do not pre-read future steps.

| Step | File                                  | Summary                                              | Gate                                               |
| ---- | ------------------------------------- | ---------------------------------------------------- | -------------------------------------------------- |
| 1    | `steps/01-requirements-intake.md`     | Identify spec, plan, inputs; create TODO.md          | TODO.md created, ROADMAP updated                   |
| 2    | `steps/02-plan-writing.md`            | Write implementation plan via `/writing-impl-plan`   | Plan written and reviewed                          |
| 3    | `steps/03-plan-verification.md`       | Verify plan against spec/code via review team        | All verifiers clean pass                           |
| 4    | `steps/04-cycle-setup.md`             | Collect inputs, verify agents, owner approval        | Owner approved, ROADMAP updated                    |
| 5    | `steps/05-scaffold-and-build.md`      | Create project skeleton; verify build chain          | `mise run test:macos` passes                       |
| 6    | `steps/06-implementation.md`          | Implementer + QA engineer parallel; devops builds    | Code compiles, tests executed                      |
| 7    | `steps/07-simplify.md`                | `/simplify` + `/fix-code-convention-violations`      | Fixes applied, tests pass                          |
| 8    | `steps/08-spec-compliance.md`         | QA reviewer + development-reviewer dual review       | Clean pass or `[CODE]`/`[TEST]`/`[CONV]` list      |
| 9    | `steps/09-fix-cycle.md`               | Route issues to implementer/QA engineer; re-validate | All issues resolved → back to Step 8               |
| 10   | `steps/10-coverage-audit.md`          | Measure coverage; fill gaps                          | Targets met or exemption granted                   |
| 11   | `steps/11-over-engineering-review.md` | Principal architect reviews for KISS/YAGNI           | Clean → Step 12; code changed → back to Step 8     |
| 12   | `steps/12-commit-and-report.md`       | Commit code; report to owner                         | All gates green, code committed                    |
| 13   | `steps/13-owner-review.md`            | Owner evaluates; accepts or requests changes         | Owner accepts → Step 14; changes → back to Step 6  |
| 14   | `steps/14-retrospective.md`           | Review cycle, update learnings                       | Learnings updated, SIPs processed                  |
| 15   | `steps/15-cleanup.md`                 | Delete artifacts, update ROADMAP.md                  | ROADMAP updated, artifacts deleted, pushed          |

## Regression Loop

Steps 8 → 9 → 10 → 11 form a verification chain. If Step 11 (Over-Engineering
Review) changes code, control returns to Step 8 (not Step 12). A single clean
pass through 8 → 10 → 11 must complete before reaching Step 12.

## Document Authority

Three documents govern each implementation cycle with strict precedence:

1. **Design spec** (highest) — the architectural authority. Defines WHAT to
   build: types, APIs, delivery mechanisms, behavioral contracts.
2. **Implementation plan** — a task breakdown. Defines HOW to organize the work:
   file structure, task ordering, dependencies. Plans reference spec sections
   for core API design — not code snippets.
3. **Code** (lowest) — the output. Must conform to the spec. When the plan
   contradicts the spec, the spec wins.

Every agent — implementer, QA engineer, QA reviewer, development-reviewer,
devops, principal architect — must verify their work against the spec, not the
plan.

## Cross-Cutting Rules

These apply to ALL steps, not just one:

- **Use skills for artifacts.** CTRs use `/cross-team-request`. ADRs use `/adr`.
  Plans use `/writing-impl-plan`. SIPs use `/sip`. Do not manually create or
  edit artifact files — skills handle placement, naming, and format
  automatically.
- **Team leader is a facilitator, not a doer.** Never write code, plans, or CTRs
  directly. Delegate to subagents or skills. Describe WHAT needs to change, not
  HOW to change each line.
- **Spec is the authority.** When code disagrees with spec and there is no ADR
  or design resolution, the spec wins. Specific rules:
  - Do not dismiss divergences as "out of scope." Every divergence must be
    investigated — "out of scope for this plan" is a conclusion AFTER
    investigation, not a reason to skip it.
  - Do not treat "the plan covers it" as investigation. The plan fixing a
    divergence does not explain WHY the code diverges.
  - Do not infer "intentional deferral" from circumstantial evidence (git
    timestamps, plan scope, ROADMAP). Only explicit decision documents (ADR,
    design resolution, owner instruction) justify divergence from spec.
- **Model selection.** Writing tasks (plans, CTRs, ADRs, spec tests) use opus.
  Plan verification uses the impl-plan-review-team (opus + effort: max).
  Verification tasks (spec checking, compliance review) may use sonnet.
- **Mechanical gates auto-proceed.** If all gate conditions can be verified by
  reading files and running commands (file exists, tests pass, agents present),
  auto-proceed with a one-line status summary. Only pause for owner approval
  when a gate involves a trade-off or decision requiring human judgment
  (coverage exemption, scope change, unusual constraints).
- **Don't shortcut skills.** When a step says "invoke /triage" or "invoke
  /simplify", execute the skill's full procedure. "The information already
  exists elsewhere" or "this is redundant" is not grounds to skip steps
  within a skill. Skills define their own quality bar — the team leader
  does not override it.
- **Don't skip checkpoint commits.** Each step's checkpoint creates a rollback
  point. Without them, a crash or context loss requires reconstructing all
  work from scratch. Commit before proceeding to the next step.
- **All step instructions are obligations, not just gates.** Gates are pass/fail
  conditions, but Action and State Update sections carry equal authority.
  "It's not in the gate" is not a reason to skip an instruction.
## Continuous Improvement Log

When you encounter a procedural problem at any step, run `/sip <description>`
immediately. Do not wait for the retrospective step.

## Rationale & Reference

For **why** each phase exists (not **how** to execute it), see:

- `docs/work-styles/05-implementation-workflow.md` — Lifecycle, rationale,
  coverage standards, spec-to-code principles
- `docs/work-styles/02-team-collaboration.md` — Team rules, communication
- `docs/insights/implementation-learnings.md` — Zig toolchain lessons, testing
  strategy lessons
