# Step 8: Owner Review

## Anti-Patterns

- Do NOT start the retrospective before the owner finishes reviewing.
- Do NOT write review notes or handover without owner instruction.
- Do NOT rush the owner — review happens at the owner's pace.

## Action

### 8a. Notify the owner

After committing (Step 7), inform the owner that documents are ready for review.
The owner reviews the committed spec docs at their own pace.

### 8b. Support the review

While the owner reviews, the team leader:

- Answers questions about design decisions
- Spawns research agents when the owner needs investigation
- Writes review notes when the owner identifies issues
- Creates ADRs when the owner identifies undocumented design decisions
- Applies immediate fixes when the owner requests them (metadata, links,
  editorial corrections)
- Delegates implementation tasks to agents as directed

### 8c. Wait for completion

The owner explicitly signals when the review is done (e.g., "review done",
"owner review complete"). Do NOT proceed until this signal.

## Gate

- [ ] Owner has explicitly signaled review completion

## State Update

Update TODO.md:

- `Current State` → `Step: 9 (Retrospective)`
- Mark `Step 8` as `[x]` with summary of review artifacts produced

Checkpoint: commit all changed artifacts (TODO.md, review notes, ADRs).

## Next

**Owner input required** — wait for owner's explicit review completion signal.

Read `steps/09-retrospective.md`.
