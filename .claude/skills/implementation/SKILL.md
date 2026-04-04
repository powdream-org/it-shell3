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

Invoke `/impl-resolve-target` with `$ARGUMENTS`. This resolves the target
argument to a filesystem path and team directory. The resolved path is referred
to as `<target>` throughout all step and skill files.

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

Read **only the current step's file or skill** — do not pre-read future steps.
Steps 6-9 execute in isolated fork context; the team leader dispatches them and
reads the JSON gate result. All other steps are executed by the team leader
directly.

| Step | Location                              | Execution     |
| ---- | ------------------------------------- | ------------- |
| —    | `direct/impl-resolve-target/SKILL.md` | direct        |
| 1    | `steps/01-requirements-intake.md`     | team leader   |
| 2    | `steps/02-plan-writing.md`            | team leader   |
| 3    | `steps/03-plan-verification.md`       | team leader   |
| 4    | `steps/04-cycle-setup.md`             | team leader   |
| 5    | `steps/05-scaffold-and-build.md`      | team leader   |
| 6    | `isolated/impl-execute/SKILL.md`      | context: fork |
| 7    | `isolated/impl-simplify/SKILL.md`     | context: fork |
| 8    | `isolated/impl-review/SKILL.md`       | context: fork |
| 9    | `isolated/impl-fix/SKILL.md`          | context: fork |
| 10   | `steps/10-coverage-audit.md`          | team leader   |
| 11   | `steps/11-over-engineering-review.md` | team leader   |
| 12   | `steps/12-commit-and-report.md`       | team leader   |
| 13   | `steps/13-owner-review.md`            | team leader   |
| 14   | `steps/14-retrospective.md`           | team leader   |
| 15   | `steps/15-cleanup.md`                 | team leader   |

## Master Transition Table

The team leader's sole procedure for step transitions: read gate → look up table
→ update TODO.md state → commit → execute next.

| From | Gate Source    | Gate Result                       | TODO.md State Update | Next                    | Proceed   |
| ---- | -------------- | --------------------------------- | -------------------- | ----------------------- | --------- |
| 1    | file check     | TODO.md created                   | Step → 2 or 3        | 02 / 03                 | auto      |
| 2    | file check     | Plan written                      | Step → 3             | 03                      | auto      |
| 3    | verifier       | All clean                         | Step → 4             | 04                      | auto      |
| 4    | agent check    | Agents verified                   | Step → 5             | 05                      | auto      |
| 5    | build output   | Build passes                      | Step → 6             | dispatch /impl-execute  | auto      |
| 6    | fork JSON      | `gate: PASS`                      | Step → 7             | dispatch /impl-simplify | auto      |
| 6    | fork JSON      | `gate: FAIL`                      | (escalate)           | owner decides           | **owner** |
| 7    | fork JSON      | `gate: PASS`, violations: `[]`    | Step → 8             | dispatch /impl-review   | auto      |
| 7    | fork JSON      | `gate: PASS`, violations: `[...]` | Step → 7.5           | /triage                 | **owner** |
| 7.5  | triage done    | Owner dispositioned               | Step → 8             | dispatch /impl-review   | auto      |
| 8    | fork JSON      | `gate: CLEAN`                     | Step → 10            | 10                      | auto      |
| 8    | fork JSON      | `gate: ISSUES`                    | Step → 8.5           | /triage                 | **owner** |
| 8.5  | triage done    | fix items exist                   | Step → 9             | dispatch /impl-fix      | auto      |
| 8.5  | triage done    | all skip/defer                    | Step → 10            | 10                      | auto      |
| 9    | fork JSON      | `gate: PASS`                      | Step → 8, Fix Iter++ | dispatch /impl-review   | auto      |
| 9    | fork JSON      | `gate: FAIL`                      | (escalate)           | owner decides           | **owner** |
| 10   | command output | Coverage ≥ targets                | Step → 11            | 11                      | auto      |
| 10   | command output | Coverage < targets                | (escalate)           | owner decides           | **owner** |
| 11   | reviewer       | No code changed                   | Step → 12            | 12                      | auto      |
| 11   | reviewer       | Code changed                      | Step → 8, Round++    | dispatch /impl-review   | auto      |
| 12   | gate checks    | All green                         | Step → 13            | 13                      | auto      |
| 13   | owner          | Accepts                           | Step → 14            | 14                      | **owner** |
| 13   | owner          | Requests changes                  | Step → 6, new Round  | dispatch /impl-execute  | **owner** |
| 14   | retro output   | Complete                          | Step → 15            | 15                      | auto      |
| 15   | cleanup        | Done                              | (end)                | —                       | auto      |

## Transition Rules

1. **Gate satisfaction is binary.** All conditions met = satisfied. Any
   condition not met = not satisfied. No "close enough" or "essentially met".

2. **Fork steps: gate from JSON.** The team leader reads the `gate` field from
   the fork's JSON result. The fork has already executed verification commands.
   The team leader does not re-run them.

3. **Non-fork steps: gate from command output.** For Steps 1-5 and 10-15, the
   team leader executes the verification command specified in the step file and
   reads the output directly.

4. **Gate not satisfied → `owner` proceed.** When any gate condition is not met,
   the team leader escalates to the owner. The team leader does not decide
   whether the gap is acceptable.

5. **`auto` proceed = no owner interaction.** Proceed immediately with a
   one-line status update. Do not ask "Should I continue?", "Ready to proceed?",
   or any variant.

6. **`owner` proceed = wait for explicit signal.** Do not prompt, suggest, or
   nudge. Present the situation and wait.

7. **State update before commit.** The TODO.md state update is applied BEFORE
   the checkpoint commit. The fork commits code; the team leader commits state.

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
  exists elsewhere" or "this is redundant" is not grounds to skip steps within a
  skill. Skills define their own quality bar — the team leader does not override
  it.
- **Don't skip checkpoint commits.** Each step's checkpoint creates a rollback
  point. Without them, a crash or context loss requires reconstructing all work
  from scratch. Commit before proceeding to the next step.
- **All step instructions are obligations, not just gates.** Gates are pass/fail
  conditions, but Action sections carry equal authority. "It's not in the gate"
  is not a reason to skip an instruction.

## Delegation Rules

Fork structurally enforces delegation for Steps 6-9 — the team leader cannot
access intermediate code, test output, or agent coordination within those steps.

For Steps 10-11 (un-forked), delegation rules remain as explicit constraints:

**Team leader MAY directly:**

- Read/write TODO.md
- Look up the transition table
- Invoke fork skills and `/triage`
- Run git commands (add, commit, status, diff)
- Run gate verification commands (Steps 10-11 only)

**Team leader MUST delegate (Steps 10-11):**

- Code editing → implementer sub-agent
- Test editing → QA engineer sub-agent
- Coverage measurement → devops sub-agent
- Triage presentation → `/triage` skill

## Triage Quality Rules

Triage occurs at Steps 7.5 and 8.5. These rules apply to both:

1. **Every `/triage` invocation follows the full procedure.** No exception for
   small issue counts, later rounds, or "obvious" issues.

2. **Grouping by root cause, not by symptom.** Issues that share the same
   underlying cause belong in the same group. Solo groups are allowed only when
   genuinely unrelated to all others.

3. **Sub-agent preparation is mandatory.** The sub-agent reads quality examples
   and prepares 5W1H presentations. The team leader does not present issues
   directly from the fork JSON.

4. **Triage is invoked, not inlined.** When a transition says "/triage", the
   team leader invokes the skill. Presenting issues in any other format violates
   this rule.

## Continuous Improvement Log

When you encounter a procedural problem at any step, run `/sip <description>`
immediately. Do not wait for the retrospective step.

## Success Criteria

This skill redesign is successful if in each implementation cycle:

- Zero instances of team leader asking permission at auto-proceed gates
- Zero instances of team leader directly editing code
- Zero instances of gate conditions passed without verification
- All triage invocations follow the full procedure
- All convention violations routed per the location table (not self-triaged)
- Fork steps (6-9) return valid JSON conforming to the defined schema
- Team leader's fork step processing consists only of: JSON gate read →
  transition table lookup �� state update → commit
- Steps 10-11: team leader executes gate verification commands directly

## Rationale & Reference

For **why** each phase exists (not **how** to execute it), see:

- `docs/work-styles/05-implementation-workflow.md` — Lifecycle, rationale,
  coverage standards, spec-to-code principles
- `docs/work-styles/02-team-collaboration.md` — Team rules, communication
- `docs/insights/implementation-learnings.md` — Zig toolchain lessons, testing
  strategy lessons
