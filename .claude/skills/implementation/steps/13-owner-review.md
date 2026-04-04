# Step 13: Owner Review

## Anti-Patterns

- **Don't rush the owner.** They review at their own pace. Do not prompt them to
  finish.
- **Don't guess when review is done.** Wait for the owner to explicitly say
  "accepted", "looks good", "done", or similar. Silence is not acceptance.
- **Don't start cleanup before acceptance.** TODO.md and plan are only deleted
  after the owner explicitly accepts.

## Action

### 13a. Update TODO.md

Update TODO.md: set **Step** to 13 (Owner Review), mark Step 12 as `[x]`.

### 13b. Support the owner's review

The owner reviews the committed code. During this time, the team leader:

- **Answers questions** about implementation decisions (consult the spec, plan,
  or spawn a research agent if needed)
- **Applies immediate fixes** if the owner requests small changes (typos,
  formatting, trivial corrections)
- **Logs larger issues** that the owner identifies — these may trigger a new
  implementation cycle (back to Step 6)
- **Creates ADRs** if the owner identifies undocumented decisions (use the
  `/adr` skill)

### 13c. Owner decision

The owner signals one of:

| Signal                   | Action                                                                                 |
| ------------------------ | -------------------------------------------------------------------------------------- |
| **Accepts**              | Proceed to Step 14 (Retrospective)                                                     |
| **Requests changes**     | Log the changes, return to Step 6 with a new implementation cycle                      |
| **Identifies spec gaps** | Report for design revision cycle; implementation waits or proceeds per owner direction |

## Gate

- [ ] Owner has explicitly accepted OR requested changes → owner confirmation
      ("accepted" / "changes requested")
- [ ] If changes requested: changes logged: `grep -A5 'Round' <target>/TODO.md`
      → change requests documented
- [ ] Checkpoint commit performed (TODO.md + changed artifacts):
      `git log -1 --oneline` → commit message references owner review
