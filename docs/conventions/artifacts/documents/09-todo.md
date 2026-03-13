# TODO Documents

## Location and Naming

```
draft/vX.Y-rN/TODO.md
```

One TODO per draft version. Created at the start of the Revision Cycle (Section 3.1 Requirements Intake) and updated throughout the cycle.

## Purpose

The TODO tracks progress across all phases of a revision cycle. It serves as the **primary resumption point** when a session ends and a new session begins — the new session reads TODO.md first to understand what has been done and what remains.

## File Format

```markdown
# {Spec Area} vX.Y-rN TODO

## Phase 1: {Phase Name}

- [x] Completed task
- [x] Completed task
- [ ] Incomplete task
- [ ] Incomplete task

## Phase 2: {Phase Name}

- [ ] Task
- [ ] Task

## ~~Phase N: {Cancelled Phase}~~ — {Reason}

{Brief explanation, e.g., "Deferred to post-v1. Owner decision."}
```

## Rules

1. **Phase structure mirrors the revision cycle.** Each phase corresponds to a workflow step (research, discussion, writing, verification, commit, triage, etc.). The exact phases depend on the scope of work.

2. **Checkbox granularity.** Each checkbox should represent a discrete, completable unit of work. Not too coarse ("do everything") nor too fine ("edit line 42").

3. **Update as you go.** Mark tasks `[x]` as they complete. This is the live state of the revision — always reflect reality.

4. **Cancelled phases use strikethrough.** Use `~~Phase Name~~` with a brief reason. Do not delete cancelled phases — they document decisions.

5. **No prose in TODO.** Keep it to phase headers and checkboxes. Context and rationale belong in handover documents, review notes, or resolution docs.

## Example

```markdown
# Protocol v1.0-r7 TODO

## Phase 1: Research (Issues 22-24 prior art)

- [x] tmux multi-client frame delivery research
- [x] zellij multi-client frame delivery research
- [x] ghostty dirty tracking & frame generation research

## Phase 2: Design Discussion & Resolution (Issues 22-24)

- [x] Core team discussion (Issue 24 → 23 → 22 order)
- [x] Resolution document written & verified by same team (5/5 APPROVED)
- [x] Disband discussion team

## Phase 3: Unified Writing (all changes in one pass)

- [x] Fresh team spawned, assignment negotiation
- [x] Doc 01: registry + overview changes
- [ ] Doc 02: disconnect reason
- [ ] Doc 03: health notification + resize rewrite

## ~~Phase 4: Deferred Feature~~ — Deferred to post-v1

Moved to `99-post-v1-features.md`. Owner decision.
```

## Anti-Patterns

| Anti-pattern | Problem | Correct approach |
|-------------|---------|-----------------|
| No TODO.md | New session has no idea where to resume | Always create at Requirements Intake |
| TODO with prose paragraphs | Hard to scan, mixes tracking with documentation | Checkboxes only; prose goes in handover |
| Deleting completed phases | Loses history of what was done | Keep completed phases with `[x]` marks |
| Deleting cancelled phases | Loses decision record | Strikethrough with reason |
| Never updating checkboxes | TODO diverges from reality | Update after each task completes |
