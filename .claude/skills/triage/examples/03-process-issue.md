## Example 3: Process Issue (SIP from Retrospective)

### What

During the Plan 5 verification triage session, the team leader skipped the
required grouping step and began presenting issues to the owner one by one as
they were discovered, without first showing a group index. This caused the owner
to defer a spec ambiguity that turned out to be the root cause of a crash bug
discovered later in the same session — forcing a re-open, re-read, and re-triage
that wasted ~15 minutes.

### Why

Issue #3 (spec says "resize every pane" — what about minimized?) looked
deferrable alone. Issue #7 (null crash in resize on minimized pane) looked like
a simple null check. The owner deferred #3, fixed #7 with a null guard, then
realized 20 minutes later that the null guard was wrong — the fix depends on
which resize interpretation is correct. Had to re-open #3, re-read evidence,
change disposition. 15 minutes wasted.

### Who

The team leader (who ran the triage) vs. the triage procedure defined in the
skill.

### When

Occurred during the Plan 5 verification session on 2026-03-18. Logged as
SIP-2026-03-18-001 during the post-cycle retrospective on 2026-03-19.

### Where

**The crash and its dependency on spec interpretation:**

```
applyResize iterates ALL pane slots:
  for each slot → access slot.active_surface → read .cols, .rows
                                    ↑ minimized panes have active_surface = null
                                    → null dereference crash

The fix depends on spec interpretation:
  1. Resize stored geometry → access stored dims, not surface
  2. Skip minimized         → add null check (but IS this correct?)
  3. Queue resize           → need a queue mechanism

A null check "fixes" the crash but silently chooses interpretation 2.
```

The spec sentence that causes the ambiguity (`server-client-protocols` v1.0-r9,
Section 4.3):

> When a LayoutResize event is received, the daemon SHALL update the geometry of
> every pane in the affected session.

"Every pane" with no carve-out for minimized panes. Three valid readings, no
guidance on which.

**If the group index had been shown first**, the owner would have seen both
issues in the same "resize handling" group:

```
Group Index — Plan 5 Verification Issues

 #  | Category        | Group             | Issues | Summary
----|-----------------|-------------------|--------|----------------------------------
 1  | Spec ↔ Code     | Event broadcast   | #1, #5 | Broadcast exclusion semantics
 2  | Spec ambiguity  | Resize handling   | #3     | Minimized pane resize undefined
 3  | Code bug        | Resize handling   | #7     | Null deref in applyResize on minimize
 4  | Spec ↔ Code     | Capability nego   | #2, #4 | Version field mismatch
 5  | Code style      | Error handling    | #6     | Missing errdefer in connectSession

Groups 2 and 3 share the tag "Resize handling." Even a quick scan of
this table reveals that a spec ambiguity and a code bug both involve
resize + minimized panes — prompting the owner to read them together.
```

Without this index, the owner saw Issue #3 in isolation (a spec editorial
concern), deferred it, and then 20 minutes later saw Issue #7 (a crash bug) with
no visible connection to the earlier decision.

**Procedure that was violated** (triage skill `SKILL.md`, Section 1, Steps 1-3):

> 1. **Group issues by conflict type.** ...Do NOT start presenting issues before
>    grouping is complete.
> 2. **Present the group index.** Show the owner a numbered table...
> 3. **Owner picks the next issue.**

The team leader went directly from "discover issue" to "present issue," skipping
Steps 1 and 2 entirely.

### How

The owner needs to decide whether the current procedure is sufficient with a
minor reinforcement (Option A: add a gate check requiring "grouping complete,
showing index now" before the first presentation), or whether phase separation
(Option B: split triage into discovery-then-presentation with a structured
document that enforces index-first) is worth the additional process overhead.
There may be other approaches — for example, the owner might decide the skip was
a one-time mistake that does not warrant a process change.

**The lesson this example teaches:** Grouping matters because without the index,
the owner cannot see that two issues in different categories (spec ambiguity vs
code bug) share the same root cause. Issue #3 looked deferrable alone. Issue #7
looked like a simple null check alone. Only when placed side by side under
"Resize handling" does the shared root cause become obvious.
