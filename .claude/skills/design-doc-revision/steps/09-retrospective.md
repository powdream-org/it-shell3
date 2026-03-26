# Step 9: Retrospective & Skill Update

## Anti-Patterns

- Do NOT edit skill files without owner approval.
- Do NOT skip this step — it is how the harness loop improves over time.
- Do NOT commit skill file changes without reading the staged diff. Agent-
  written edits may contain stale content or miss coordinated updates across
  step files.

## Purpose

This step exists so the harness loop self-improves over time. After each
revision cycle, the team leader reviews what went wrong and proposes updates to
the step files. This ensures anti-patterns are captured at the point of failure
and future cycles benefit from past experience.

## Action

### 9a. Review the cycle

Read TODO.md's Progress section end-to-end. For each step, answer:

1. **Did I skip this step or execute it out of order?** If yes, why? Was the
   step file unclear, or did I lose track?
2. **Did I violate any anti-pattern listed in the step file?** If yes, which one
   and how?
3. **Was there unnecessary token consumption?** (e.g., spawning agents that
   weren't needed, re-reading files unnecessarily, unnecessary communication
   rounds)
4. **Was a gate condition unclear or insufficient?** Could I have accidentally
   passed it without actually completing the step?
5. **Did I micromanage?** (e.g., gave specific edit instructions instead of
   goals, proxied messages instead of letting agents talk directly)

### 9b. Review and finalize accumulated proposals

Review SIPs accumulated via `/sip` during the cycle at
`retrospective/skill-improvement-proposals.md`.

For each problem identified in 9a that is not already captured, run
`/sip <description>` to add it now.

- Draft a specific edit to the relevant step file:
  - Add a new anti-pattern if one was discovered
  - Clarify a gate condition if it was ambiguous
  - Add a missing instruction if a step was unclear
  - Remove unnecessary steps if they wasted tokens

### 9c. Owner review

Present proposed changes to the owner:

- List each proposed edit with: which file, what change, why
- **Wait for owner approval.** Do not edit skill files without approval.

### 9d. Apply approved changes

If owner approves:

1. Edit the step file(s)
2. Commit with message:
   `fix(skills): improve design-doc-revision step N — {reason}`

If owner has no changes or declines: no action needed.

## Gate

- [ ] Retrospective questions answered
- [ ] Improvements proposed (or "none needed" stated)
- [ ] Owner has responded

## State Update

Update TODO.md:

- Mark `Step 9` as `[x]`
- `Current State` → `Step: 10 (Handover)`

## Next

Read `steps/10-handover.md`.
