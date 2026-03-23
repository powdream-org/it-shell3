# Step 7: Commit & Report

## Anti-Patterns

- Do NOT commit review notes or handover in the same commit as spec docs.
- Do NOT skip to the retrospective — Step 8 (Owner Review) comes next.
- Do NOT commit without reading the staged diff. If agents wrote the changes,
  read the modified files and check for stale content or missed coordinated
  updates before committing.

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
5. **Document production is complete.** Proceed to Step 8 (Owner Review).

## Gate

- [ ] All documents committed
- [ ] Owner notified with summary

## State Update

Update TODO.md:

- `Current State` → `Step: 8 (Owner Review)`
- `Active Team` → (none)
- Mark `Step 7` as `[x]`

## Next

Read `steps/08-owner-review.md`.
