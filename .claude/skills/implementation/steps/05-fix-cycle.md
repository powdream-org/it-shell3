# Step 5: Fix Cycle

## Anti-Patterns

- **Don't proxy fixes.** The QA reviewer sends issues directly to the
  implementer. They communicate peer-to-peer.
- **Don't skip regression checks.** After each fix, the QA reviewer must verify
  the fix AND check for regressions (other tests still pass).
- **Don't batch fixes without verification.** Each fix should be verified
  individually, not all at once at the end.
- **Don't let the implementer "improve" while fixing.** Fixes address the
  specific issue — no scope creep. If the implementer thinks something should be
  improved, they report it as a spec gap.

## Action

### 5a. Hand issues to the implementer

Send the QA reviewer's issue list to the implementer:

```
The QA reviewer found these spec compliance issues. Fix each one.
After fixing, notify the QA reviewer directly so they can re-validate.
Do NOT add anything beyond what the fix requires.

Issues:
<paste numbered issue list>
```

### 5b. Monitor fix-and-verify loop

The implementer and QA reviewer work peer-to-peer:

1. Implementer fixes an issue → notifies QA reviewer
2. QA reviewer verifies the fix + checks for regressions → confirms or reopens
3. Repeat until all issues resolved

You (team leader) monitor but do NOT intervene unless:

- An issue reveals a spec gap → log in TODO.md, report to owner
- The agents are stuck in a loop → investigate and unblock
- The owner needs to make a decision

### 5c. Verify all tests pass

Once all issues are resolved:

```bash
(cd <target> && zig build test)
```

All tests must pass before proceeding.

## Gate

- [ ] All issues from Step 4 are resolved and verified by QA reviewer
- [ ] `zig build test` passes
- [ ] No new unauthorized extensions introduced during fixes

## State Update

Update TODO.md:

- **Step**: 4 (Spec Compliance Review) — yes, back to Step 4 for re-review
- Mark Step 5 as `[x]` (but it may be revisited)

## Next

Read `steps/04-spec-compliance.md` — the QA reviewer does another full review to
catch any issues introduced by the fixes. This loop (4 → 5 → 4) continues until
Step 4 produces a clean pass.
