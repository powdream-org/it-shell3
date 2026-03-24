# Step 10: Handover

## Anti-Patterns

- Do NOT skip this step — handover captures context that would otherwise be lost
  between sessions.
- Do NOT commit the handover in the same commit as spec docs.
- Do NOT write a handover that only lists research tasks. The handover MUST
  capture insights, design philosophy, and owner priorities — the "why" behind
  decisions that review notes and verification records do not contain.

## Action

### 10a. Write the handover

Run `/handover {topic} {version}` to write the handover document. The skill
handles artifact inventory, format, and placement.

The handover MUST explicitly carry forward:

- **Next revision scope and inputs**: If the owner has stated what the next
  revision will cover (e.g., "r8 is the big restructure"), document this as
  concrete scope — not a vague suggestion. Include specific inputs (spec docs,
  plans, unfixed findings).
- **Unfixed secondary findings**: Any issues flagged by verifiers but not fixed
  in this cycle (out of scope, deferred, or discovered in the final round).
  These are mandatory inputs for the next revision.
- **Research tasks**: What should happen before the next design round begins.

### 10b. Update design principles

After writing the handover, review its Insights and Design Philosophy sections
against `docs/insights/design-principles.md`. Add new principles, update Origin
columns for reinforced ones.

### 10c. Commit

Commit the handover and design-principles update in a single commit, separate
from spec docs.

## Gate

- [ ] Handover written to `draft/vX.Y-rN/handover/handover-to-r(N+1).md`
- [ ] Next revision scope explicitly stated (not just research tasks)
- [ ] Unfixed secondary findings carried forward
- [ ] Design principles updated (if applicable)
- [ ] Committed

## State Update

Update TODO.md:

- Mark `Step 10` as `[x]`
- `Current State` → `Complete`

## End

The revision cycle is fully complete. No further action.
