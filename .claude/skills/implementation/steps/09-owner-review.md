# Step 9: Owner Review

## Anti-Patterns

- **Don't rush the owner.** They review at their own pace. Do not prompt them to
  finish.
- **Don't guess when review is done.** Wait for the owner to explicitly say
  "accepted", "looks good", "done", or similar. Silence is not acceptance.
- **Don't start cleanup before acceptance.** TODO.md and plan are only deleted
  after the owner explicitly accepts.

## Action

### 9a. Support the owner's review

The owner reviews the committed code. During this time, the team leader:

- **Answers questions** about implementation decisions (consult the spec, plan,
  or spawn a research agent if needed)
- **Applies immediate fixes** if the owner requests small changes (typos,
  formatting, trivial corrections)
- **Logs larger issues** that the owner identifies — these may trigger a new
  implementation cycle (back to Step 3)
- **Creates ADRs** if the owner identifies undocumented decisions (use the
  `/adr` skill)

### 9b. Owner decision

The owner signals one of:

| Signal                   | Action                                                                                 |
| ------------------------ | -------------------------------------------------------------------------------------- |
| **Accepts**              | Proceed to 9c (cleanup)                                                                |
| **Requests changes**     | Log the changes, return to Step 3 with a new implementation cycle                      |
| **Identifies spec gaps** | Report for design revision cycle; implementation waits or proceeds per owner direction |

## Gate

- [ ] Owner has explicitly accepted OR requested changes
- [ ] If changes requested: changes logged

## State Update

- If accepted:
  - **Step**: 10 (Retrospective & Cleanup)
  - Mark Step 9 as `[x]`
- If changes requested:
  - **Step**: 3 (Implementation Phase)
  - Reset Step marks 3–8 to `[ ]`
  - Increment review round

## Next

- If accepted → Read `steps/10-retrospective.md`.
- If changes requested → Read `steps/03-implementation.md`.
