# Step 6: Fix Cycle

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
- **Don't edit code directly.** All fixes go through the implementer, not the
  team leader. The team leader describes what needs to change; the implementer
  makes the edits.

## Action

### 6a. Check context budget

Run `/check-available-context-window`. If remaining <= 25%, ask the owner to
`/compact` before continuing. Fix cycles accumulate context with each iteration
— especially if multiple rounds of 5 -> 6 -> 5 have occurred.

### 6b. Hand issues to the implementer

Send the QA reviewer's issue list to the implementer:

```
The QA reviewer found these spec compliance issues. Fix each one.
After fixing, notify the QA reviewer directly so they can re-validate.
Do NOT add anything beyond what the fix requires.

Issues:
<paste numbered issue list>
```

### 6c. Monitor fix-and-verify loop

The implementer and QA reviewer work peer-to-peer:

1. Implementer fixes an issue -> notifies QA reviewer
2. QA reviewer verifies the fix + checks for regressions -> confirms or reopens
3. Repeat until all issues resolved

You (team leader) monitor but do NOT intervene unless:

- An issue reveals a spec gap -> log in TODO.md, report to owner
- The agents are stuck in a loop (same issue reopened 3+ times) -> escalate to
  owner for decision
- The owner needs to make a decision

**Round limit:** The 5 -> 6 -> 5 loop runs automatically for up to **3 rounds**.
If Step 5 still finds issues after Round 3, STOP and escalate to the owner. The
owner decides: (a) continue with another round, (b) accept remaining issues as
known limitations, or (c) trigger a spec revision.

Track the current round in TODO.md's `Review Round` field.

### 6d. Verify all tests pass

Once all issues are resolved:

```bash
mise run test:macos
mise run test:macos:release-safe
```

Both Debug and ReleaseSafe must pass before proceeding.

## Gate

- [ ] All issues from Step 5 are resolved and verified by QA reviewer
- [ ] `mise run test:macos` and `mise run test:macos:release-safe` pass
- [ ] No new unauthorized extensions introduced during fixes

## State Update

Update TODO.md:

- **Step**: 5 (Spec Compliance Review) — yes, back to Step 5 for re-review
- Mark Step 6 as `[x]` in the current round's progress
- Increment `Fix Iteration` in Fix Cycle State
- Update `Active Issues` to reflect resolved/remaining issues
- If starting a new verification round after Step 8 regression, append a new
  `## Progress — Round N` section (do NOT reset previous marks)

## Next

Read `steps/05-spec-compliance.md` — the QA reviewer does another full review to
catch any issues introduced by the fixes. This loop (5 -> 6 -> 5) continues
until Step 5 produces a clean pass.
