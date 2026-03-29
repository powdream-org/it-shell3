# Step 13: Owner Review

## Anti-Patterns

- **Don't rush the owner.** They review at their own pace. Do not prompt them to
  finish.
- **Don't guess when review is done.** Wait for the owner to explicitly say
  "accepted", "looks good", "done", or similar. Silence is not acceptance.
- **Don't start cleanup before acceptance.** TODO.md and plan are only deleted
  after the owner explicitly accepts.

## Action

### 13a. Support the owner's review

The owner reviews the committed code. During this time, the team leader:

- **Answers questions** about implementation decisions (consult the spec, plan,
  or spawn a research agent if needed)
- **Applies immediate fixes** if the owner requests small changes (typos,
  formatting, trivial corrections)
- **Logs larger issues** that the owner identifies — these may trigger a new
  implementation cycle (back to Step 6)
- **Creates ADRs** if the owner identifies undocumented decisions (use the
  `/adr` skill)

### 13b. Owner decision

The owner signals one of:

| Signal                   | Action                                                                                 |
| ------------------------ | -------------------------------------------------------------------------------------- |
| **Accepts**              | Proceed to Step 14 (Retrospective)                                                     |
| **Requests changes**     | Log the changes, return to Step 6 with a new implementation cycle                      |
| **Identifies spec gaps** | Report for design revision cycle; implementation waits or proceeds per owner direction |

## Gate

- [ ] Owner has explicitly accepted OR requested changes
- [ ] If changes requested: changes logged

## State Update

- If accepted:
  - **Step**: 14 (Retrospective & Cleanup)
  - Mark Step 13 as `[x]`
- If changes requested:
  - **Step**: 6 (Implementation Phase)
  - Append a new `## Progress — Round N` section to TODO.md (do NOT reset
    previous round's marks — they are the audit trail)
  - **Carry forward**: Spec Gap Log, Coverage exemption, Plan path, Spec
    version(s), owner's change requests
  - **Reset in new round**: Active Team, Team Directory, Fix Iteration, Active
    Issues
  - Increment review round

## Next

- If accepted → Read `steps/14-retrospective.md`.
- If changes requested → Read `steps/06-implementation.md`.
