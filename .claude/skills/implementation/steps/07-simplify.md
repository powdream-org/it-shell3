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

## Gate

- [ ] `/simplify` skill completed (all three agents reported)
- [ ] `/fix-code-convention-violations` completed
- [ ] Applicable fixes applied
- [ ] `mise run test:all -- --no-coverage` passes

## State Update

Update TODO.md:

- **Step**: 8 (Spec Compliance Review)
- Mark Step 7 as `[x]`

Checkpoint: commit all changed artifacts (TODO.md, source files).

## Next

**Auto-proceed** — no owner input required.

Read `steps/08-spec-compliance.md`.
