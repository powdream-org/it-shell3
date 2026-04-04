---
name: impl-simplify
description: >
  Run code simplification and convention compliance checks, fix in-plan violations, report out-of-plan violations.
user-invocable: false
context: fork
---

# Step 7: Code Simplify & Convention Compliance

## Anti-Patterns

- **Don't skip this step because "the code looks fine."** Fresh eyes (the
  `/simplify` agents and development-reviewer) catch patterns the implementer
  and QA engineer are blind to.
- **Don't argue with findings.** If a finding is a false positive or not worth
  fixing, skip it silently. Don't spend time debating.
- **Don't let simplify expand scope.** The agents may suggest new abstractions
  or utilities — only apply fixes that simplify existing code, not ones that add
  new infrastructure.

## Action

### 7a. Update TODO.md

Update TODO.md: set **Step** to 7 (Code Simplify & Convention Compliance), mark
Step 6 as `[x]`.

### 7b. Check context budget

Run `/check-available-context-window`. If remaining <= 25%, ask the owner to
`/compact` before proceeding. Step 4 spawns multiple agents while existing
agents are still alive.

### 7c. Run the `/simplify` skill

Invoke the `/simplify` skill. This launches three parallel review agents on the
current diff:

1. **Code Reuse** — finds duplicated logic that could use existing utilities
2. **Code Quality** — flags redundant state, copy-paste, leaky abstractions,
   unnecessary comments, circular import patterns
3. **Efficiency** — catches unnecessary work, missed concurrency, hot-path
   bloat, memory issues

### 7d. Apply simplify fixes

After all three agents report, aggregate findings and fix each issue directly.
The implementer applies the fixes (they own the source code).

Rules for applying fixes:

- Fix issues that genuinely simplify or improve the code
- Skip false positives without discussion
- Do NOT add new abstractions, utilities, or infrastructure — simplify only
- Do NOT change public API signatures (types, method names) — those are
  spec-defined

### 7e. Run `/fix-code-convention-violations`

Invoke the `/fix-code-convention-violations` skill. This spawns the
development-reviewer to detect convention violations, then routes fixes to the
implementer (max 2 rounds).

**Convention violation classification:** For each violation found, determine
whether the violating code belongs to the current plan's scope:

- `in_current_plan: true` — the file/function was created or modified by this
  plan. Fix it immediately within this step.
- `in_current_plan: false` — the file/function predates this plan (existing
  code). Do NOT fix it here. Include it in `out_of_plan_violations` for the team
  leader to triage.

### 7f. Verify after all fixes

After both `/simplify` and `/fix-code-convention-violations` complete, spawn the
**devops** agent (`.claude/agents/impl-team/devops.md`):

```
Run full test suite to verify simplify and convention fixes:
mise run test:all -- --no-coverage
Report structured results.
```

All tests must pass before proceeding.

**Note:** Simplify and convention changes are tentative until Step 8 validates
spec compliance. If Step 8 rejects a change (it introduced a spec violation),
the implementer reverts it.

## Gate Verification

Each condition must be verified by the fork before returning. Execute the exact
commands listed.

- [ ] `/simplify` skill completed (all three agents reported)
- [ ] `/fix-code-convention-violations` completed
- [ ] All `in_current_plan: true` violations fixed
- [ ] Applicable simplify fixes applied
- [ ] Tests pass: `mise run test:all -- --no-coverage` → output contains "tests
      passed" and exit code 0
- [ ] Format clean: `(cd <target> && zig fmt --check src/)` → exit code 0
- [ ] Checkpoint commit performed: `git add -A && git commit` with all changed
      artifacts (TODO.md, source files)

## Return

Return a JSON object conforming to the fork return contract:

```json
{
  "step": 7,
  "gate": "PASS | FAIL",
  "checkpoint": "<commit-sha>",
  "payload": {
    "simplify_complete": true | false,
    "convention_complete": true | false,
    "tests_pass": true | false,
    "out_of_plan_violations": [
      {
        "file": "<path>",
        "line": "<number>",
        "rule": "<convention rule reference, e.g. zig-naming §3.2>",
        "current": "<current code or pattern>",
        "expected": "<what the convention requires>",
        "description": "<human-readable explanation of the violation>",
        "in_current_plan": false
      }
    ]
  }
}
```

**Field semantics:**

- `gate`: `PASS` if simplify completed, convention check completed, all
  `in_current_plan: true` violations are fixed, and tests pass. `FAIL` if tests
  fail after fixes or simplify/convention steps could not complete.
- `checkpoint`: The SHA of the checkpoint commit created at the end of the step.
- `simplify_complete`: `true` if the `/simplify` skill ran to completion with
  all three agents reporting.
- `convention_complete`: `true` if `/fix-code-convention-violations` ran to
  completion.
- `tests_pass`: `true` if `mise run test:all -- --no-coverage` passes with exit
  code 0.
- `out_of_plan_violations`: Array of convention violations found in code that
  predates the current plan. Empty array `[]` if none found. The fork fixes all
  `in_current_plan: true` violations internally — only `in_current_plan: false`
  items appear here. Each entry carries enough context for the team leader to
  invoke `/triage` with full 5W1H information.
