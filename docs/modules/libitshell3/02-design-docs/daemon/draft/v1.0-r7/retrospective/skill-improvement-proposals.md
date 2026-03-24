# Skill Improvement Proposals (Daemon v1.0-r7)

Logged as encountered during the revision cycle.

---

## SIP-01: Contested issue presentation — full context not shown on first attempt

**Step**: 5 (Verification), Phase 2 outcome presentation

**What happened**: When presenting V1-05 (contested issue) to the owner, the
team leader initially showed only the Phase 2 verdicts table with one-line
summaries. The owner had to explicitly ask for more context before the actual
document text and both reviewers' reasoning were shown.

**Root cause**: The Step 5 anti-pattern already says: "Do NOT present contested
issues to the owner as one-line summaries. For each contested issue, show the
actual document text (quoted, with line numbers) and both reviewers' reasoning."
The team leader violated this despite the anti-pattern being clearly stated.

**Proposed fix**: Strengthen the Step 5d outcome rules to make the full-context
presentation a **blocking gate**, not just an anti-pattern. Suggested change to
`steps/05-verification.md`:

```
### 5d. Apply outcome rules

For each issue:

- Both `confirm` → **confirmed** (true alarm)
- Both `dismiss` → **dismissed**
- One each → **contested** → MUST present to owner with:
  1. Actual document text (quoted, with line numbers)
  2. Confirm reviewer's reasoning with specific evidence
  3. Dismiss reviewer's reasoning with specific evidence
  Only THEN ask for binding decision.
  **NEVER present contested issues as one-line summaries.**
```

Move this from the anti-patterns section into the action section as a mandatory
sub-step, so it cannot be skipped.

---

## SIP-02: Contested issue presentation — file path and line locations not shown

**Step**: 5 (Verification), Phase 2 contested issue presentation

**What happened**: When presenting V1-05 (contested issue) with full context,
the team leader showed document text and both reviewers' reasoning but did NOT
include the file path. The owner had to ask "let me know which file" before the
team leader provided
`docs/modules/libitshell3/02-design-docs/daemon/draft/v1.0-r7/03-lifecycle-and-connections.md`.

**Root cause**: The contested issue presentation format in the skill specifies
"actual document text (quoted, with line numbers)" but does not explicitly
require the **file path** to be shown. The team leader showed line numbers but
not the file, making it impossible for the owner to navigate to the source
without asking.

**Proposed fix**: Add file path as a mandatory element in the contested issue
presentation format. Update the Step 5d template:

```
- One each → **contested** → MUST present to owner with:
  1. **File path** (full relative path from project root)
  2. Actual document text (quoted, with line numbers)
  3. Confirm reviewer's reasoning with specific evidence
  4. Dismiss reviewer's reasoning with specific evidence
```

---

## SIP-03: Cascade analysis misses intra-procedure ordering dependencies

**Step**: 6 (Fix Round Decision), Step 6a.2 (Cascade analysis)

**What happened**: The V2-01 fix deferred `engine.deactivate()` from step 4 to
step 12 in `executePaneDestroyCascade()`. The cascade analysis assessed risk as
"low (localized changes, no cross-module impact)" — it checked cross-document
ripple effects but did NOT check whether the fix changed execution order
relative to other steps in the same procedure. Step 6 (`close(pane.pty_fd)`)
sits between steps 4 and 12, so the deferred `deactivate()` now runs after the
PTY fd is closed — a use-after-close defect. This was caught in Round 3 as
V3-07, wasting a full verification round.

**Root cause**: Step 6a.2 cascade analysis instruction says "assess each
confirmed issue's fix impact across all documents" — the scope is
**cross-document**. It does not instruct the cascade agent to trace
**intra-procedure data/resource dependencies** when a fix reorders steps within
a single procedure.

**Proposed fix**: Add an intra-procedure ordering check to Step 6a.2. Suggested
addition to `steps/06-fix-round.md`:

---

## SIP-04: Contested issue presentation — concrete breakdown examples are highly effective

**Step**: 5 (Verification), Phase 2 contested issue presentation

**What happened**: When presenting V3-13 (LayoutChanged before WindowResizeAck),
the owner said "couldn't understand those rationale." The team leader then
reformulated using a concrete step-by-step example comparing navigation (where
the rule clearly applies) vs resize (the debated case). The owner immediately
understood and made a decision. The same technique worked for V3-15 (stale
terminology) — a concrete timeline with timestamps made the conflation
self-evident.

**Root cause**: The Step 5 contested issue presentation format requires "both
reviewers' reasoning with specific evidence" but does not suggest **concrete
examples** (timelines, step traces, message sequences) as a presentation
technique. Abstract reasoning about rules and edge cases is harder to evaluate
than a concrete scenario showing what actually happens.

**Proposed fix**: Add to the Step 5d contested issue presentation guidance:

```
- One each → **contested** → MUST present to owner with:
  1. File path (full relative path from project root)
  2. Actual document text (quoted, with line numbers)
  3. Confirm reviewer's reasoning with specific evidence
  4. Dismiss reviewer's reasoning with specific evidence
  5. **Concrete breakdown** (RECOMMENDED): A step-by-step example
     (timeline, message sequence, or code trace) that makes the
     contradiction or consistency self-evident. This is especially
     valuable when the issue involves ordering rules, state machines,
     or terminology that has different meanings in different contexts.
```

```
### 6a.2. Cascade analysis

...existing cross-document analysis...

**Intra-procedure ordering check (MANDATORY when a fix changes step
ordering or adds conditional branches):** For each fix that defers, reorders,
or conditionally skips a step within a procedure:

1. List all resources/state consumed by the deferred step (fd, engine state,
   session fields, etc.)
2. Check whether any intervening step between the old and new position
   invalidates, closes, or frees those resources.
3. If yes, flag as a cascade risk and include in the fix writer's instructions.
```

---

## SIP-05: ADR skill defaults to "Proposed" even for accepted decisions

**Step**: 7 (Commit & Report), ADR creation

**What happened**: The `/adr` skill instruction says "keep as `Proposed`
(default for new ADRs)." The team leader followed this mechanically and created
3 ADRs with `Status: Proposed` for decisions that were unanimously agreed (6/6),
integrated into spec docs, and verified across 4 rounds — clearly `Accepted`.
The owner caught the error and asked to fix it. The team leader corrected the
status but made the **same mistake on all 3 ADRs** instead of reasoning about
the status once and applying it consistently.

**Root cause**: The `/adr` skill has no guidance for determining the correct
status. It always defaults to `Proposed` regardless of context. When ADRs are
created during Step 7 of a design-doc-revision cycle, the decisions are already
accepted — they've passed discussion, resolution, and verification.

**Proposed fix**: Add status determination logic to the `/adr` skill:

```
## Step 4: Draft the Full ADR

...

**Status determination:**
- If the decision is under active discussion → `Proposed`
- If the decision has been agreed upon, integrated into specs, and/or
  verified → `Accepted`
- When creating ADRs as part of a design-doc-revision commit step (Step 7),
  the decisions are always `Accepted` — they passed team consensus,
  resolution verification, and spec integration.
```

Also add to `steps/07-commit-and-report.md`:

```
2. **ADR candidates**: ... For each confirmed candidate, run `/adr` with
   status **Accepted** (these decisions have passed consensus and
   verification).
```
