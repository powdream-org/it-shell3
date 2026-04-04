---
name: impl-fix
description: >
  Execute the fix cycle: route triaged issues to agents, verify fixes, run tests.
user-invocable: false
context: fork
---

# Step 9: Fix Cycle

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

### 9a. Update TODO.md

Update TODO.md: set **Step** to 9 (Fix Cycle), mark Step 8 as `[x]`. Record the
triaged issue list in **Active Issues**.

### 9b. Check context budget

Run `/check-available-context-window`. If remaining <= 25%, ask the owner to
`/compact` before continuing. Fix cycles accumulate context with each iteration
— especially if multiple rounds of 8 → 9 → 8 have occurred.

### 9c. Route issues to the correct agent

Route only the fix-dispositioned issues (from the team leader's triage at Step
8.5) to the appropriate agents:

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

### 9d. Monitor fix-and-verify loop

Both agents work on their respective issues:

1. Implementer fixes `[CODE]`/`[CONV]` issues → notifies QA reviewer
2. QA engineer fixes `[TEST]` issues → notifies QA reviewer
3. QA reviewer re-validates each fix + checks for regressions
4. QA reviewer confirms or reopens each issue
5. Repeat until all issues resolved

Monitor but do NOT intervene unless:

- An issue reveals a spec gap → log in TODO.md, report to owner
- The agents are stuck in a loop (same issue reopened 3+ times) → escalate to
  owner for decision
- The owner needs to make a decision

**Round limit:** The fix-and-verify loop within this step runs for up to **3
internal rounds**. If issues remain unresolved after 3 rounds, STOP and report
`gate: FAIL` with `unresolved` items.

Track the current round in TODO.md's `Review Round` field.

### 9e. Verify all tests pass

Once all issues are resolved, spawn the **devops** agent
(`.claude/agents/impl-team/devops.md`):

```
Run full test suite to verify fixes:
mise run test:all -- --no-coverage
Report structured results.
```

All tests must pass before returning `gate: PASS`.

## Gate Verification

Each condition must be verified by the fork before returning. Execute the exact
commands listed.

- [ ] All `[CODE]` issues resolved and verified by QA reviewer
- [ ] All `[TEST]` issues resolved and verified by QA reviewer
- [ ] All `[CONV]` issues resolved and verified by development-reviewer
- [ ] Tests pass: `mise run test:all -- --no-coverage` → output contains "tests
      passed" and exit code 0
- [ ] Format clean: `(cd <target> && zig fmt --check src/)` → exit code 0
- [ ] No new unauthorized extensions introduced during fixes
- [ ] Checkpoint commit performed: `git add -A && git commit` with all changed
      artifacts (TODO.md, fixed source/test files)

## Return

Return a JSON object conforming to the fork return contract:

```json
{
  "step": 9,
  "gate": "PASS | FAIL",
  "checkpoint": "<commit-sha>",
  "payload": {
    "rounds_used": "<number>",
    "resolved": [
      {
        "id": "<issue ID from Step 8, e.g. R1-001>",
        "summary": "<one-line description of what was fixed>"
      }
    ],
    "unresolved": [
      {
        "id": "<issue ID from Step 8>",
        "summary": "<one-line description of why it could not be resolved>"
      }
    ],
    "tests_pass": true | false
  }
}
```

**Field semantics:**

- `gate`: `PASS` if all fix-dispositioned issues are resolved AND tests pass.
  `FAIL` if any issues remain unresolved after 3 internal rounds, or if tests
  fail after all fixes are applied.
- `checkpoint`: The SHA of the checkpoint commit created at the end of the step.
- `rounds_used`: Number of internal fix-and-verify rounds executed (1 to 3).
- `resolved`: Array of issues that were successfully fixed and verified. Each
  entry references the original issue ID from Step 8's output.
- `unresolved`: Array of issues that could not be resolved within the round
  limit. Empty array `[]` when `gate` is `PASS`. Non-empty `unresolved` with
  `gate: FAIL` triggers owner escalation by the team leader.
- `tests_pass`: `true` if `mise run test:all -- --no-coverage` passes with exit
  code 0 after all fixes are applied.
