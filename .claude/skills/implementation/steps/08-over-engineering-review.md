# Step 8: Over-Engineering Review

## Anti-Patterns

- **Don't activate this reviewer early.** The over-engineering reviewer sees the
  code AFTER implementation + spec compliance + coverage are complete. See
  `05-implementation-workflow.md` §4.3 for why.
- **Don't let the reviewer rewrite code.** They report findings — the
  implementer fixes. The reviewer re-validates.
- **Don't skip the regression loop.** If ANY code changes during this step,
  control returns to Step 5, not Step 9. No exceptions.

## Action

### 8a. Check context budget

If context window ≤ 25%, ask the owner to `/compact` before spawning the
over-engineering reviewer. This step may trigger a regression loop back to Step
5, which further accumulates context.

### 8b. Spawn the over-engineering reviewer

The principal architect has been dormant until now. Activate them:

```
Review all source files in <target>/src/ for over-engineering.
The design spec is at: <spec paths>.
Current coverage: <line%>, <branch%>, <function%> (from Step 7).
Note: removing code may drop coverage below targets, triggering a re-audit.

Check for:
- Types, fields, methods, or features beyond what the spec requires
- Unnecessarily complex implementations (simpler alternative exists)
- Code for hypothetical future requirements (YAGNI)
- Unused functions, types, or imports (dead code)
- Helper functions or utilities for one-time operations (premature abstraction)
- Buffer sizes not justified by spec or measurement
- Unnecessary build steps, targets, or dependencies

For each finding, report:
- file:line reference
- What the code does
- Which principle it violates (spec scope / KISS / YAGNI / dead code / etc.)
- Suggested fix (simplification or removal)

If no findings: report "Clean pass."
```

### 8c. Process findings

- **If clean pass** → Proceed to Step 9.
- **If findings exist** → Send to the implementer for fixing.

### 8d. Fix findings (if any)

Send findings to the implementer:

```
The over-engineering reviewer found these issues. Fix each one.
Remove or simplify as directed. Do NOT add new code while fixing.

Findings:
<paste finding list>
```

After the implementer fixes, the over-engineering reviewer re-validates.

### 8e. Check for code changes

**Critical decision point:**

- If any code was changed during this step → **return to Step 5**. The full
  verification chain (Compliance → Coverage → Over-Engineering) must pass clean
  in a single run before commit.
- If no code was changed (clean pass on first review) → proceed to Step 9.

**Why:** Over-engineering fixes remove or simplify code. This can break spec
compliance or reduce coverage. Only a clean end-to-end pass guarantees
everything still holds.

### 8f. Verify tests pass (if code changed)

Before returning to Step 5:

```bash
mise run test:macos
mise run test:macos:release-safe
```

Both Debug and ReleaseSafe must pass. If tests fail, the implementer fixes
before proceeding to Step 5.

## Gate

- [ ] Over-engineering reviewer has completed the review
- [ ] If findings: implementer has fixed them, reviewer has re-validated
- [ ] If code changed: tests pass in Debug and ReleaseSafe

## State Update

- If clean (no code changes):
  - **Step**: 9 (Commit & Report)
  - Mark Step 8 as `[x]`
- If code changed:
  - **Step**: 5 (Spec Compliance Review) — regression loop
  - Note in TODO.md: "Returning to Step 5 after over-engineering fixes"

## Next

- If clean → Read `steps/09-commit-and-report.md`.
- If code changed → Read `steps/05-spec-compliance.md`.
