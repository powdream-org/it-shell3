---
name: impl-execute
description: >
  Execute the implementation phase: spawn implementer and QA engineer, wire tests, build and run.
user-invocable: false
context: fork
---

# Step 6: Implementation Phase

## Anti-Patterns

- **Don't proxy messages between agents.** They talk peer-to-peer. See
  `02-team-collaboration.md` Section 5.
- **Don't micromanage.** Tell agents WHAT to build (spec references, file
  assignments), not HOW to write each line. "Change line 43 to X" is
  micromanagement — "implement the processKey pipeline per spec §2" is
  delegation.
- **Don't reuse agent names from a previous context without checking for stale
  shutdown requests.** Stale requests from pre-compaction context can cause
  premature exit. Use fresh names or verify clean state.
- **Don't use `= undefined` for buffers.** Zig's `= undefined` is genuine UB
  (unlike C's indeterminate value). Use `@splat(0)` or zero-initialization for
  buffers that may be read before full initialization. (Lesson Z3)
- **Don't let agents invent behavior for spec gaps.** When a spec gap is
  discovered, the agent must STOP work on that area, report the gap to the team
  leader, and wait for an owner decision.
- **Don't treat the plan as the spec.** The plan is a task breakdown. The design
  spec is the architectural authority (see Document Authority in SKILL.md).
- **Don't let either agent touch the other's files.** File ownership is strict:
  - Implementer: `src/**/*.zig` EXCEPT `src/testing/spec/`
  - QA engineer: `src/testing/spec/*_spec_test.zig` ONLY (new files only)
  - Team leader does NOT wire imports — devops handles `src/testing/root.zig`
- **Don't reduce QA engineer to a reviewer-only role.** QA engineer's primary
  job in Step 6 is writing spec behavior tests — one test per scenario in the
  spec's scenario matrix. QA engineer must report a test list with per-test spec
  requirement citations, not just a completion note. If QA engineer only reviews
  code without writing tests, the step has failed.
- **Don't trust Plan 1-4 code as spec-compliant.** Plans 1-4 predate the current
  verification chain. Existing code may contain spec violations.
- **Don't let QA engineer read implementation source code.** QA engineer derives
  tests from the spec alone. Reading the implementation introduces bias — tests
  end up confirming what the code does rather than what the spec says.
- **Don't assume agents know project conventions.** The agent definition and
  spawn prompt must both reference convention docs explicitly. Conventions not
  read before coding become rework in Step 7.
- **Don't serialize parallelizable tasks into one implementer.** If the plan's
  dependency graph shows independent task groups, spawn one implementer per
  group. Queuing all tasks behind a single agent wastes time.

## Action

### 6a. Update TODO.md

Update TODO.md: set **Step** to 6 (Implementation Phase), mark Step 5 as `[x]`.

### 6b. Check context budget

Run `/check-available-context-window`. If remaining <= 25%, ask the owner to
`/compact` before spawning agents.

### 6c. Prepare spawn context

Gather these for each agent:

**For the implementer:**

- TODO.md `## Spec` section (contains spec paths, plan path, PoC paths)
- File assignments from the plan
- `docs/insights/implementation-learnings.md` (Zig toolchain lessons)

**For the QA engineer:**

- TODO.md `## Spec` section (contains spec paths)
- Scenario matrix from the spec (or plan's test matrix)
- Test output directory: `<target>/src/testing/spec/`

### 6d. Spawn implementer and QA engineer in parallel

Spawn both agents simultaneously from `.claude/agents/impl-team/`. They work
independently — the implementer writes source code from the spec/plan; the QA
engineer writes spec behavior tests from the spec/scenario matrix.

**Implementer** (`.claude/agents/impl-team/implementer.md`):

```
You are implementing module <module>. Source dir: <target>/src/.
Read TODO.md's ## Spec section for all spec paths, plan path, and PoC paths.
Also read: docs/insights/implementation-learnings.md
MANDATORY: Read ALL docs/conventions/zig-*.md files before writing any code.
Convention violations caught later are expensive rework.
CRITICAL: The design spec is the architectural authority, not the plan. If the
plan's descriptions contradict the spec, the spec wins. Verify every public API
against the spec section that defines it.
FILE OWNERSHIP: You own all files under src/ EXCEPT src/testing/spec/ — do NOT
create or modify any file in src/testing/spec/.
Read the spec and plan, then begin implementation. Report when all source files
and inline unit tests are complete.
```

**QA Engineer** (`.claude/agents/impl-team/qa-engineer.md`):

```
You are writing spec behavior tests for module <module>.
Read TODO.md's ## Spec section for all spec paths.
Output dir: <target>/src/testing/spec/.
MANDATORY: Read docs/conventions/zig-testing.md and docs/conventions/zig-documentation.md
before writing tests.
CRITICAL: Derive ALL test cases from the design spec and scenario matrix — NOT
from the implementation code. You must NOT read implementation source files.
FILE OWNERSHIP: You own ONLY src/testing/spec/*_spec_test.zig — do NOT create
or modify any file outside this directory.
Read the spec and scenario matrix, then write all spec behavior tests. Report
the complete test list with spec requirement citations when done.
```

### 6e. Wait for completion

Wait for both agents to report completion. Do NOT proceed until both are done.

### 6f. Wire tests, build, and run tests

Spawn the **devops** agent (`.claude/agents/impl-team/devops.md`):

```
Wire QA engineer's spec test files into the test infrastructure, then build and
run all tests.
1. List all *_spec_test.zig files in <target>/src/testing/spec/
2. Update src/testing/root.zig to @import each new file
3. Run: mise run test:all -- --no-coverage
4. Run: (cd <target> && zig fmt --check src/)
Report structured results.
```

**Expected:** Some QA engineer spec tests may FAIL. This is normal — spec tests
are derived from the spec independently of the implementation. Failures
indicate:

- Implementation doesn't match the spec → implementation bug
- Test assumes wrong API surface → test needs adjustment
- Spec ambiguity → log as spec gap

**If tests don't compile:** Coordinate between implementer and QA engineer to
resolve API mismatches. Check which side matches the spec — that side is
correct; the other must adjust.

**If tests compile but some fail:** Proceed to gate evaluation. Failures feed
into the spec compliance review at Step 8.

### 6g. Monitor progress

During each agent's active phase:

- Answer questions from the agent (relay to owner if beyond your scope)
- Log any spec gaps discovered to TODO.md's "Spec Gap Log" section
- Do NOT intervene unless asked or unless you observe clear spec violations

### 6h. Keep team alive

Do NOT disband the team. All agents (implementer, QA engineer, QA reviewer,
development-reviewer, devops) continue into subsequent steps. They are disbanded
in Step 12.

## Gate Verification

Each condition must be verified by the fork before returning. Execute the exact
commands listed.

- [ ] Implementer reports all source files complete with inline unit tests
- [ ] QA engineer reports all spec behavior tests with per-test requirement
      citations
- [ ] Devops has wired spec tests into `src/testing/root.zig`
- [ ] Code compiles: `(cd <target> && zig build)` → exit code 0
- [ ] Format clean: `(cd <target> && zig fmt --check src/)` → exit code 0
- [ ] Tests executed: `mise run test:all -- --no-coverage` → command completes
      (failures acceptable at this stage; record pass/fail/skip counts)
- [ ] Spec gaps (if any) logged in TODO.md
- [ ] Checkpoint commit performed: `git add -A && git commit` with all changed
      artifacts (TODO.md, source files, test files)

## Return

Return a JSON object conforming to the fork return contract:

```json
{
  "step": 6,
  "gate": "PASS | FAIL",
  "checkpoint": "<commit-sha>",
  "payload": {
    "compilation": "PASS | FAIL",
    "tests_executed": true | false,
    "test_summary": {
      "passed": "<number>",
      "failed": "<number>",
      "skipped": "<number>"
    },
    "spec_gaps": [
      {
        "file": "<path>",
        "line": "<number>",
        "spec_section": "<section name>",
        "description": "<what the spec requires vs what is implemented>",
        "severity": "divergence"
      }
    ]
  }
}
```

**Field semantics:**

- `gate`: `PASS` if code compiles AND tests were executed (failures are
  acceptable). `FAIL` if code does not compile or agents could not complete.
- `checkpoint`: The SHA of the checkpoint commit created at the end of the step.
- `compilation`: `PASS` if `zig build` succeeds, `FAIL` otherwise.
- `tests_executed`: `true` if `mise run test:all -- --no-coverage` ran to
  completion (regardless of test results), `false` if it could not run.
- `test_summary`: Counts from the test run. All zeros if tests were not
  executed.
- `spec_gaps`: Array of spec gaps discovered during implementation. Empty array
  `[]` if none found. Each entry must cite the spec section and describe the
  divergence.
