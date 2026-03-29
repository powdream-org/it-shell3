# Step 6: Fix Cycle

## Anti-Patterns

- **Don't proxy fixes.** Agents communicate peer-to-peer. The team leader routes
  issues to the correct agent but does not relay messages between them.
- **Don't skip regression checks.** After each fix, the relevant reviewer must
  verify the fix AND check for regressions.
- **Don't batch fixes without verification.** Each fix should be verified
  individually, not all at once at the end.
- **Don't let the implementer "improve" while fixing.** Fixes address the
  specific issue — no scope creep. If the implementer thinks something should be
  improved, they report it as a spec gap.
- **Don't edit code directly.** All fixes go through the implementer or QA
  engineer, not the team leader.
- **Don't route issues to the wrong agent.** `[CODE]` and `[CONV]` go to the
  implementer. `[TEST]` goes to the QA engineer. Mixing these wastes time and
  creates confusion.

## Action

### 6a. Update TODO.md

Update TODO.md: set **Step** to 6 (Fix Cycle), mark Step 5 as `[x]`. Record the
merged issue list in **Active Issues**.

### 6b. Check context budget

Run `/check-available-context-window`. If remaining <= 25%, ask the owner to
`/compact` before continuing. Fix cycles accumulate context with each iteration
— especially if multiple rounds of 5 → 6 → 5 have occurred.

### 6c. Route issues to the correct agent

**`[CODE]` and `[CONV]` issues → Implementer**
(`.claude/agents/impl-team/implementer.md`):

```
The review found these issues. Fix each one.
After fixing, notify the QA reviewer directly so they can re-validate.
Do NOT add anything beyond what the fix requires.

Issues:
<paste [CODE] and [CONV] issues>
```

**`[TEST]` issues → QA Engineer** (`.claude/agents/impl-team/qa-engineer.md`):

```
The review found these test case issues. Fix each one — add missing tests,
correct wrong assertions, or update spec citations.
After fixing, notify the QA reviewer directly so they can re-validate.

Issues:
<paste [TEST] issues>
```

If all issues are one type only, skip the other agent's message.

### 6d. Monitor fix-and-verify loop

Both agents work on their respective issues:

1. Implementer fixes `[CODE]`/`[CONV]` issues → notifies QA reviewer
2. QA engineer fixes `[TEST]` issues → notifies QA reviewer
3. QA reviewer re-validates each fix + checks for regressions
4. QA reviewer confirms or reopens each issue
5. Repeat until all issues resolved

You (team leader) monitor but do NOT intervene unless:

- An issue reveals a spec gap → log in TODO.md, report to owner
- The agents are stuck in a loop (same issue reopened 3+ times) → escalate to
  owner for decision
- The owner needs to make a decision

**Round limit:** The 5 → 6 → 5 loop runs automatically for up to **3 rounds**.
If Step 5 still finds issues after Round 3, STOP and escalate to the owner. The
owner decides: (a) continue with another round, (b) accept remaining issues as
known limitations, or (c) trigger a spec revision.

Track the current round in TODO.md's `Review Round` field.

### 6e. Verify all tests pass

Once all issues are resolved, spawn the **devops** agent
(`.claude/agents/impl-team/devops.md`):

```
Run full test suite to verify fixes:
mise run test:all -- --no-coverage
Report structured results.
```

All tests must pass before proceeding.

## Gate

- [ ] All `[CODE]` issues resolved and verified by QA reviewer
- [ ] All `[TEST]` issues resolved and verified by QA reviewer
- [ ] All `[CONV]` issues resolved and verified by development-reviewer
- [ ] `mise run test:all -- --no-coverage` passes
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
catch any issues introduced by the fixes. This loop (5 → 6 → 5) continues until
Step 5 produces a clean pass.
