## Example 3: Process Issue (SIP from Retrospective)

### What

During the Plan 5 verification triage session, the team leader skipped the
required grouping step and began presenting issues to the owner one by one as
they were discovered, without first showing a group index. This caused the owner
to defer a spec ambiguity that turned out to be the root cause of a crash bug
discovered later in the same session — forcing a re-open, re-read, and re-triage
that wasted ~15 minutes.

### Why

The triage procedure requires grouping before presentation so the owner can see
the full landscape of issues, identify duplicates, and prioritize. When issues
are presented ad-hoc as discovered, the owner makes decisions without knowing
what else is coming.

Here is the concrete failure. Issue #3 was a **spec ambiguity** about resize
semantics for minimized panes. The spec text in question
(`server-client-protocols` v1.0-r9, Section 4.3 "Pane Geometry Updates"):

```
When a LayoutResize event is received, the daemon SHALL update the
geometry of every pane in the affected session. Each pane's `cols` and
`rows` fields are recalculated from the new terminal dimensions and the
pane's split ratio.
```

The ambiguity: the spec says "every pane" with no carve-out for minimized panes.
A minimized pane has no active rendering slot — its geometry is stored but not
displayed. Three interpretations are possible:

1. Resize the stored geometry (pane un-minimizes at new size when restored)
2. Skip minimized panes entirely (pane restores at its old size)
3. Queue the resize and apply it when the pane is restored

The spec does not say which. In isolation, this looked like a low-priority
editorial issue — the resize policy for minimized panes would not be implemented
until Plan 9.

Issue #7 was a **code bug** — the resize handler crashes with a null dereference
on minimized panes. The function in
`modules/libitshell3/src/layout_manager.zig`:

```zig
pub fn applyResize(self: *LayoutManager, new_cols: u32, new_rows: u32) void {
    for (self.pane_slots) |slot| {
        // BUG: minimized panes have slot.active_surface = null
        // because they release their rendering surface on minimize.
        // .? on null causes a panic.
        const surface = slot.active_surface.?;
        surface.cols = new_cols;
        surface.rows = new_rows;
        surface.markDirty();
    }
}
```

When a pane is minimized, `slot.active_surface` is `null` because minimized
panes release their rendering surface. The `.?` unwrap panics. This is not just
a missing null check — the fix depends on which of the three interpretations
above is correct. If interpretation 1 is chosen, the code should resize the
_stored_ geometry (not the surface). If interpretation 2, the code should skip.
If interpretation 3, the code should enqueue. The crash and the spec ambiguity
share the same root cause: the spec never defined minimized-pane resize
semantics, and the code assumed all panes have active surfaces.

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

### Who

The team leader (who ran the triage) vs. the triage procedure defined in the
skill.

### When

Occurred during the Plan 5 verification session on 2026-03-18. Logged as
SIP-2026-03-18-001 during the post-cycle retrospective on 2026-03-19.

### Where

**SIP file quote** (`.claude/sips/SIP-2026-03-18-001.md`, lines 8-22):

```
## Observed Behavior

During Plan 5 verification triage, the team leader began presenting
issues to the owner immediately upon discovery. Issues were presented
in discovery order (not grouped by type), and no group index was shown
before the first issue presentation.

## Impact

The owner deferred Issue #3 (spec ambiguity: resize semantics for
minimized panes) without knowing that Issue #7 (code bug: resize
handler crashes on minimized panes) was caused by the same ambiguity.
After all issues were presented, the owner had to re-open Issue #3
and re-triage it alongside Issue #7, costing ~15 minutes and requiring
re-reading of evidence already presented.
```

**Procedure that was violated** (triage skill `SKILL.md`, Section 1, Steps 1-3):

> 1. **Group issues by conflict type.** ...Do NOT start presenting issues before
>    grouping is complete.
> 2. **Present the group index.** Show the owner a numbered table...
> 3. **Owner picks the next issue.**

The team leader went directly from "discover issue" to "present issue," skipping
Steps 1 and 2 entirely.

**Sequence of events:**

1. Team leader starts reading Plan 5 verification results.
2. Finds Issue #3 (spec ambiguity: resize semantics for minimized panes).
3. Immediately presents it to owner using 5W1H format.
4. Owner reads the spec text, sees no implementation depends on it yet: _"Issue
   #3: defer to Plan 9, resize policy for minimized panes isn't implemented yet.
   Not blocking."_
5. Team leader continues discovering and presenting issues #4, #5, #6.
6. Team leader finds Issue #7 (null dereference in `applyResize`).
7. Presents it as a code bug. Shows the crash trace and the function.
8. Owner reads the code, sees `slot.active_surface.?` on a minimized pane, and
   realizes the fix depends on the resize-minimized-pane policy: _"Wait — this
   crash IS the resize ambiguity. The code panics because the spec never said
   what to do here. Re-open #3."_
9. Owner re-reads Issue #3 evidence (already scrolled off), changes disposition:
   _"#3 and #7 are the same root cause. Fix the spec first (define
   interpretation 2 — skip minimized panes), then fix the code to match. Do both
   in this plan, not Plan 9."_

Steps 8-9 cost ~15 minutes of re-reading and re-discussion that would not have
occurred if the group index had shown Issues #3 and #7 together under "Resize
handling."

**Option A (small fix):** Add a gate check to the triage procedure — before
presenting the first issue, the team leader must confirm "grouping complete,
showing index now" and actually display the index table. This is a one-line
behavioral addition to the existing procedure. The risk is that a team leader
under time pressure may still skip it since there is no enforcement mechanism.

**Option B (larger fix):** Restructure triage into two explicit phases with a
hard boundary. Phase 1: discovery and grouping (the team leader collects all
issues into a structured document). Phase 2: presentation (the team leader
presents from the document, which enforces the index-first pattern because the
document IS the index). This requires creating a triage document template and
updating the skill to reference it.

### How

The owner needs to decide whether the current procedure is sufficient with a
minor reinforcement (Option A), or whether the phase separation (Option B) is
worth the additional process overhead. There may be other approaches — for
example, the owner might decide the current procedure is fine and the skip was a
one-time mistake that does not warrant a process change.

**The lesson this example teaches:** Grouping matters because without the index,
the owner cannot see that two issues in different categories (spec ambiguity vs
code bug) share the same root cause. The group index is not bureaucratic
overhead — it is the mechanism that makes cross-category connections visible.
Issue #3 looked deferrable alone. Issue #7 looked like a simple null check
alone. Only when placed side by side under "Resize handling" does the shared
root cause become obvious.
