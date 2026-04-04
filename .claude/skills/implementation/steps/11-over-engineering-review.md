# Step 11: Over-Engineering Review

## Anti-Patterns

- **Don't activate this reviewer early.** The over-engineering reviewer sees the
  code AFTER implementation + spec compliance + coverage are complete. See
  `05-implementation-workflow.md` §4.3 for why.
- **Don't let the reviewer rewrite code.** They report findings — the
  implementer fixes. The reviewer re-validates.
- **Don't self-triage over-engineering findings.** Even if findings appear
  pre-existing or out-of-scope, the owner decides the disposition.
  "Pre-existing" is a timeline fact, not a disposition — the owner may still
  choose Fix, Justified, or Defer. Always invoke `/triage`. Self-check: "has the
  owner seen this finding's 5W1H presentation?" — if no, you haven't triaged it.
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

- [ ] Over-engineering reviewer has completed the review → reviewer agent
      reports "clean pass" or findings list
- [ ] If findings: implementer has fixed them, reviewer has re-validated →
      reviewer agent reports "clean pass" after re-validation
- [ ] If code changed: tests pass in Debug and ReleaseSafe:
      `mise run test:macos && mise run test:macos:release-safe` → all tests pass
- [ ] If findings exist: `/triage` invoked, sub-agent ID recorded, owner
      dispositions in TODO.md: `grep 'triage\|disposition' <target>/TODO.md` →
      dispositions recorded
- [ ] Checkpoint commit performed (TODO.md + changed artifacts):
      `git log -1 --oneline` → commit message references over-engineering review
