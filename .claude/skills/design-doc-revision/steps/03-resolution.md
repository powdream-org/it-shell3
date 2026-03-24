# Step 3: Resolution & Verification

## Anti-Patterns

- Do NOT shut down agents before they verify the resolution document. The same
  agents who debated must verify that the document captures what they agreed on.
- Do NOT skip verification — a resolution that doesn't match consensus causes
  incorrect spec updates.
- Do NOT proceed if any member objects. Go back to Step 2 discussion.

## Action

1. **One representative** (a core member) writes `design-resolutions-{topic}.md`
   in `draft/vX.Y-rN/design-resolutions/`. Format follows the design resolutions
   convention. The writer MUST tag architectural decisions with
   `[ADR-CANDIDATE]` when the decision changes a data structure, selects between
   named alternatives, or establishes a permanent constraint.
2. If changes affect another team's documents, the resolution MUST note which
   team and what changes. These become cross-team requests in Step 4.
3. **All team members verify the resolution WITH MEMORY INTACT.** Each member
   confirms or objects.
4. If **any** member objects → back to Step 2 (update TODO accordingly).
5. After **ALL** members confirm → shut down **all** agents (clean memory wipe).

**Why memory wipe:** Fresh agents in Step 4 avoid bias from the discussion. They
work purely from the resolution document.

## Gate

- [ ] Resolution document written to disk (not just discussed)
- [ ] All team members explicitly confirmed
- [ ] All agents shut down (clean memory wipe)

## State Update

Update TODO.md:

- `Current State` → `Step: 4 (Writing)`
- `Active Team` → (none)
- `Team Directory` → (none)
- Mark `Step 3` as `[x]`

## Next

Read `steps/04-writing.md`.
