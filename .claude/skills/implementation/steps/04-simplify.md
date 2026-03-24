# Step 4: Code Simplify

## Anti-Patterns

- **Don't skip this step because "the code looks fine."** Fresh eyes (the three
  parallel agents) catch patterns the implementer and QA reviewer are blind to.
- **Don't argue with findings.** If a finding is a false positive or not worth
  fixing, skip it silently. Don't spend time debating.
- **Don't let simplify expand scope.** The agents may suggest new abstractions
  or utilities — only apply fixes that simplify existing code, not ones that add
  new infrastructure.

## Action

### 4a. Check context budget

If context window ≤ 25%, ask the owner to `/compact` before proceeding. Step 4
spawns 3 new agents while the implementer + QA are still alive (5 agents total).

### 4b. Run the `/simplify` skill

Invoke the `/simplify` skill. This launches three parallel review agents on the
current diff:

1. **Code Reuse** — finds duplicated logic that could use existing utilities
2. **Code Quality** — flags redundant state, copy-paste, leaky abstractions,
   unnecessary comments
3. **Efficiency** — catches unnecessary work, missed concurrency, hot-path
   bloat, memory issues

### 4c. Apply fixes

After all three agents report, aggregate findings and fix each issue directly.
The implementer applies the fixes (they own the source code).

Rules for applying fixes:

- Fix issues that genuinely simplify or improve the code
- Skip false positives without discussion
- Do NOT add new abstractions, utilities, or infrastructure — simplify only
- Do NOT change public API signatures (types, method names) — those are
  spec-defined

### 4d. Verify after fixes

If any code was changed:

```bash
(cd <target> && zig build test)
(cd <target> && zig build test -Doptimize=ReleaseSafe)
(cd <target> && zig fmt --check src/)
```

All must pass before proceeding.

**Note:** Simplify changes are tentative until Step 5 validates spec compliance.
If Step 5 rejects a simplify change (it introduced a spec violation), the
implementer reverts it.

## Gate

- [ ] `/simplify` skill completed (all three agents reported)
- [ ] Applicable fixes applied
- [ ] Tests pass in both Debug and ReleaseSafe (if code changed)
- [ ] `zig fmt --check` passes (if code changed)

## State Update

Update TODO.md:

- **Step**: 5 (Spec Compliance Review)
- Mark Step 4 as `[x]`

## Next

Read `steps/05-spec-compliance.md`.
