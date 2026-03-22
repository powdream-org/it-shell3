# Step 7: Commit & Report

## Anti-Patterns

- Do NOT write review notes or handover after committing. The Revision Cycle
  ends here. Review notes and handover are Review Cycle artifacts — they only
  happen when the owner explicitly instructs in a future session.
- Do NOT commit review notes or handover in the same commit as spec docs.
- Do NOT self-declare "review complete" or start the next revision.

## Action

1. Disband any remaining agents (there should be none if previous steps were
   followed correctly, but verify).
2. `git add` all files in the draft version directory.
3. Commit with a descriptive message following commit conventions.
4. Report to the owner:
   - What was produced (which spec docs, which version)
   - Summary of key decisions from the resolution
   - Verification result (clean after N rounds, or owner-declared
     clean/deferred)
5. **Document production is complete.** Do NOT write review notes, handover, or
   start a new revision. The only remaining step is the retrospective.

The Review Cycle begins **only when the owner opens a new session and starts
reviewing**. The team leader cannot initiate, advance, or complete any part of
the Review Cycle on their own.

## Gate

- [ ] All documents committed
- [ ] Owner notified with summary

## State Update

Update TODO.md:

- `Current State` → `Step: 8 (Retrospective)`
- `Active Team` → (none)
- Mark `Step 7` as `[x]`

## Next

Read `steps/08-retrospective.md`.
