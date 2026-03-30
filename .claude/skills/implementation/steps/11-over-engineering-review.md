# Step 11: Over-Engineering Review

## Anti-Patterns

- **Don't activate this reviewer early.** The over-engineering reviewer sees the
  code AFTER implementation + spec compliance + coverage are complete. See
  `05-implementation-workflow.md` §4.3 for why.
- **Don't let the reviewer rewrite code.** They report findings — the
  implementer fixes. The reviewer re-validates.
- **Don't skip the regression loop.** If ANY code changes during this step,
  control returns to Step 8, not Step 12. No exceptions.

## Action

### 11a. Update TODO.md

Update TODO.md: set **Step** to 11 (Over-Engineering Review), mark Step 10 as
`[x]`.

### 11b. Check context budget

Run `/check-available-context-window`. If remaining <= 25%, ask the owner to
`/compact` before spawning the over-engineering reviewer. This step may trigger
a regression loop back to Step 8, which further accumulates context.

### 11c. Spawn the over-engineering reviewer

The principal architect has been dormant until now. Activate them:

```
Review all source files in <target>/src/ for over-engineering.
The design spec is at: <spec paths>.
Current coverage: <line%>, <branch%>, <function%> (from Step 10).
Note: removing code may drop coverage below targets, triggering a re-audit.

Check for:
- Types, fields, methods, or features beyond what the spec requires
- Unnecessarily complex implementations (simpler alternative exists)
- Code for hypothetical future requirements (YAGNI)
- Unused functions, types, or imports (dead code)
- Helper functions or utilities for one-time operations (premature abstraction)
- Buffer sizes not justified by spec or measurement
- Unnecessary build steps, targets, or dependencies
- Import dependency direction — grep for ../ imports and verify they flow
  downward (handler -> shared types, not handler -> parent module). Cross-module
  references must use named imports, not relative paths. Flag any bidirectional
  import chains as dependency violations.

For each finding, report:
- file:line reference
- What the code does
- Which principle it violates (spec scope / KISS / YAGNI / dead code /
  dependency direction / etc.)
- Suggested fix (simplification or removal)

If no findings: report "Clean pass."
```

### 11d. Process findings

- **If clean pass** -> Proceed to Step 12.
- **If findings exist** -> Invoke `/triage` to present them to the owner.
  Dispositions: Fix (simplify), Justified (keep), Defer. Then send
  fix-dispositioned findings to the implementer.

### 11e. Fix findings (if any)

Send findings to the implementer:

```
The over-engineering reviewer found these issues. Fix each one.
Remove or simplify as directed. Do NOT add new code while fixing.

Findings:
<paste finding list>
```

After the implementer fixes, the over-engineering reviewer re-validates.

### 11f. Check for code changes

**Critical decision point:**

- If any code was changed during this step -> **return to Step 8**. The full
  verification chain (Compliance -> Coverage -> Over-Engineering) must pass
  clean in a single run before commit.
- If no code was changed (clean pass on first review) -> proceed to Step 12.

**Why:** Over-engineering fixes remove or simplify code. This can break spec
compliance or reduce coverage. Only a clean end-to-end pass guarantees
everything still holds.

### 11g. Verify tests pass (if code changed)

Before returning to Step 8:

Spawn the **devops** agent (`.claude/agents/impl-team/devops.md`):

```
Run full test suite to verify over-engineering fixes:
mise run test:all -- --no-coverage
Report structured results.
```

All tests must pass. If tests fail, the implementer fixes before proceeding to
Step 8.

## Gate

- [ ] Over-engineering reviewer has completed the review
- [ ] If findings: implementer has fixed them, reviewer has re-validated
- [ ] If code changed: tests pass in Debug and ReleaseSafe

## State Update

Update TODO.md:

- If clean (no code changes):
  - **Step**: 12 (Commit & Report)
  - Mark Step 11 as `[x]`
- If code changed:
  - **Step**: 8 (Spec Compliance Review) — regression loop
  - Note in TODO.md: "Returning to Step 8 after over-engineering fixes"

Checkpoint: commit all changed artifacts (TODO.md, any simplified source files).

## Next

**Auto-proceed** — no owner input required.

- If clean -> Read `steps/12-commit-and-report.md`.
- If code changed -> Read `steps/08-spec-compliance.md`.
