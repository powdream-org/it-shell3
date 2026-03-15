# Design Resolution 01: Protocol v1.0-r12 Revisions

- **Version**: v1.0-r12
- **Date**: 2026-03-14
- **Status**: Resolved (5/5 unanimous consensus on all items)
- **Participants**: protocol-architect, system-sw-engineer, cjk-specialist,
  ime-expert, principal-architect
- **Sources**: RN-01 through RN-06 (`draft/v1.0-r11/review-notes/`), CTR-01
  (`draft/v1.0-r11/cross-team-requests/01-daemon-surface-references.md`),
  section numbering audit (handover
  `draft/v1.0-r11/handover/handover-to-v012.md`)
- **Scope**: Docs 01-06, `99-post-v1-features.md`,
  `draft/v1.0-r7/design-resolutions/01-i-p-frame-ring-buffer.md`

---

## Table of Contents

1. [Resolution 1: Mouse + preedit interaction (RN-01)](#resolution-1-mouse--preedit-interaction-rn-01)
2. [Resolution 2: Zoom + split interaction (RN-02)](#resolution-2-zoom--split-interaction-rn-02)
3. [Resolution 3: Pane auto-close on process exit (RN-03)](#resolution-3-pane-auto-close-on-process-exit-rn-03)
4. [Resolution 4: Hyperlink CellData encoding deferred (RN-04)](#resolution-4-hyperlink-celldata-encoding-deferred-rn-04)
5. [Resolution 5: Resolution doc text fixes (RN-05)](#resolution-5-resolution-doc-text-fixes-rn-05)
6. [Resolution 6: Remove frame_type=2 (RN-06)](#resolution-6-remove-frame_type2-rn-06)
7. [Resolution 7: Remove ghostty_surface_preedit() references (CTR-01)](#resolution-7-remove-ghostty_surface_preedit-references-ctr-01)
8. [Resolution 8: Doc 05 section numbering gap fix](#resolution-8-doc-05-section-numbering-gap-fix)
9. [Resolution 9: Number all unnumbered subsections](#resolution-9-number-all-unnumbered-subsections)
10. [Resolution 10: Preamble sections — leave as-is](#resolution-10-preamble-sections--leave-as-is)

---

## Resolution 1: Mouse + preedit interaction (RN-01)

**Consensus**: 5/5 (writing only — owner pre-decided) **Severity**: MEDIUM

**Decision**: MouseButton (0x0202) during active preedit causes the server to
commit preedit before forwarding the mouse event. MouseScroll (0x0204) during
active preedit does NOT commit preedit.

### Rationale

- MouseButton changes the editing context (cursor position moves). Preedit must
  be finalized before the cursor relocates. The server sends `PreeditEnd` with
  `reason="committed"` (not `"cancelled"`) and the committed text is written to
  the PTY.
- MouseScroll is a viewport-only operation. The editing context (cursor
  position, active pane) is unchanged. Committing preedit on scroll would
  disrupt CJK composition (e.g., a user scrolling up to check something
  mid-composition should not lose their in-progress Korean syllable).
- Viewport restoration after scroll is handled automatically by libghostty's
  `scroll-to-bottom` default behavior — no protocol support needed.

### Affected locations

1. **Doc 05 Section 7** (post-Resolution 8 gap fix: Section 6): Add normative
   rules for mouse event interaction with active preedit. MouseButton commits:
   the server sends `PreeditEnd` with `reason="committed"` and the committed
   text written to PTY, then forwards the mouse event. MouseScroll does not
   commit.
2. **Doc 04 Section 2.3** (MouseButton definition): Add cross-reference note:
   "If preedit is active when a MouseButton event arrives, the server MUST
   commit preedit before processing the mouse event. See Doc 05 Section 6
   (post-Resolution 8 gap fix)."

---

## Resolution 2: Zoom + split interaction (RN-02)

**Consensus**: 5/5 **Severity**: MEDIUM

**Decision**: Option A — when a `SplitPaneRequest` arrives while a pane is
zoomed, the server MUST unzoom first (restore the original layout), then perform
the split. The operation is atomic from the client's perspective.

### Rationale

1. **tmux precedent.** tmux implements a `window_push_zoom()` /
   `window_pop_zoom()` pattern (`cmd-split-window.c:109,178`). When
   `split-window` is called while zoomed, tmux unzooms, performs
   `layout_split_pane()`, then optionally re-zooms (with the `-Z` flag). The
   split is never rejected due to zoom state.

2. **Option B (reject) is hostile UX.** If a user is zoomed and presses their
   split keybinding, getting an error is surprising and unhelpful. Zoom is a
   viewing mode, not a locking mode. It should not prevent structural
   operations.

3. **No new message types or error codes needed.** The server handles the unzoom
   internally. The client sees a normal `SplitPaneResponse` (success) followed
   by a single `LayoutChanged` with `zoomed_pane_present=false` and the updated
   layout tree.

4. **Preedit MUST survive the unzoom+split.** Unzoom is a layout operation (like
   resize), not an editing context change (like focus change or MouseButton
   click). Active preedit composition MUST NOT be committed or disrupted by the
   unzoom operation.

5. **No re-zoom after split in v1.** tmux only re-zooms with an explicit `-Z`
   flag. Adding a `zoom_after` field to `SplitPaneRequest` is scope creep for
   v1. The user can achieve this with two sequential requests (SplitPane +
   ZoomPane) if needed. Deferred to post-v1.

### Affected locations

1. **Doc 03 Section 2.3** (SplitPaneRequest): Add normative note: "If the
   session has a zoomed pane, the server MUST unzoom (restore the original
   layout) before performing the split. The resulting `LayoutChanged` will have
   `zoomed_pane_present=false`. Active preedit MUST NOT be committed or
   disrupted by the unzoom operation."
2. **Doc 03 Open Question #4**: Close with this resolution.

---

## Resolution 3: Pane auto-close on process exit (RN-03)

**Consensus**: 5/5 (writing only — owner pre-decided) **Severity**: MEDIUM

**Decision**: When a pane's process exits, the server MUST automatically close
the pane (same sequence as ClosePane). If the auto-closed pane was the last pane
in the session, the session is auto-destroyed (`side_effect=1`).

### Rationale

- Auto-close is the simplest v1 behavior. No dead panes accumulate.
- The cascade (last pane closes -> session auto-destroyed) matches user
  expectation: closing the last shell tab closes the terminal tab.
- Remain-on-exit is deferred to post-v1 (see `99-post-v1-features.md` Section
  2).
- The daemon embedder MUST pass `wait_after_command=false` to ghostty
  `Surface.Options` to ensure auto-close behavior.

### Affected locations

1. **Doc 03**: Add normative rules for auto-close behavior on process exit.
   Server sends `PaneMetadataChanged` with `is_running: false` followed by the
   same sequence as ClosePane (layout reflow, `LayoutChanged` notification).
2. **Doc 03 Open Question #6**: Already closed in v0.7. Confirm resolution text.

---

## Resolution 4: Hyperlink CellData encoding deferred (RN-04)

**Consensus**: 5/5 **Severity**: MEDIUM

**Decision**: Defer hyperlink encoding (per-cell association and URI delivery)
to post-v1. Keep `row_flags.hyperlink` bit 4 as-is. Document the HyperlinkTable
design direction in `99-post-v1-features.md`. CellData remains 16 bytes.

### Rationale

1. **No v1 consumer.** Hyperlink click handling, URL opening, and hover
   detection with underline rendering are not in scope for Phase 1-5. The
   `row_flags.hyperlink` bit 4 provides row-level presence detection for
   rendering optimization — this is self-contained and useful without URI data.

2. **`row_flags.hyperlink` bit 4 is fully specified for its current scope.** Its
   normative semantics ("When `hyperlink=0`, the client's renderer MAY skip
   overlay rendering for this row entirely") are a rendering optimization hint,
   not a promise of URI delivery. The server populates this bit from ghostty's
   per-row `Row.hyperlink: bool` flag at zero additional cost.

3. **CellData MUST stay 16 bytes.** The 16-byte FlatCell is power-of-2 aligned
   by design: O(1) random access via `buffer[col * 16]`, SIMD-friendly
   processing, deterministic sizing. Adding 2 bytes (to 18B) would destroy these
   properties. ghostty itself does not store hyperlink IDs in the cell — it uses
   an offset hash map (`hyperlink.zig:20-23`: "We use an offset hash map to save
   space since its very unlikely a cell is a hyperlink, so its a waste to store
   the hyperlink ID in the cell itself").

4. **Zero-cost deferral.** The side-table infrastructure is additive. Adding a
   third side table (HyperlinkTable) post-v1 does not change CellData,
   GraphemeTable, or UnderlineColorTable. The `row_flags` bit 4 is already
   reserved and ready.

5. **Unvalidated by PoC.** Every other CellData decision (16-byte FlatCell,
   GraphemeTable, UnderlineColorTable) was validated through PoC 06-08. The
   hyperlink export pipeline (walking ghostty's `AutoOffsetHashMap(Cell -> Id)`
   per row, frame-local ID assignment, cross-row P-frame hyperlink lifecycle)
   has not been validated.

### Design direction (for `99-post-v1-features.md`)

The intended approach is a per-row HyperlinkTable side table following the
GraphemeTable/UnderlineColorTable pattern:

```
HyperlinkTable (per-row, third side table):
  num_entries     u16 LE    Number of hyperlinked cells in this row
  Entry[num_entries]:
    col_index     u16 LE    Column index of the hyperlinked cell
    hyperlink_id  u16 LE    Per-frame hyperlink ID (references FrameUpdate hyperlink table)
```

Plus a per-frame hyperlink URI table in the JSON metadata blob:

```json
{
  "hyperlinks": {
    "1": "https://example.com/foo",
    "2": "file:///home/user/doc.txt"
  }
}
```

When `row_flags.hyperlink=0`, HyperlinkTable has `num_entries=0` (2-byte zero
header). CellData stays at 16 bytes. The side table chain is backward-compatible
— new clients read the third table, old clients ignore trailing data.

### Affected locations

1. **Doc 04 Open Question #4**: Close with: "Hyperlink encoding (per-cell
   association and URI delivery) deferred to post-v1. The `row_flags.hyperlink`
   bit provides row-level presence detection for rendering optimization. The
   intended design direction is a per-row HyperlinkTable side table (matching
   GraphemeTable/UnderlineColorTable pattern) with a per-frame hyperlink URI
   table in the JSON metadata blob. CellData remains 16 bytes."
2. **`99-post-v1-features.md`**: Add new Section 6 documenting the
   HyperlinkTable design direction, including the wire format above and
   backward-compatible extensibility notes.

---

## Resolution 5: Resolution doc text fixes (RN-05)

**Consensus**: 5/5 (writing only — owner pre-decided) **Severity**: LOW
**Status**: CANCELLED (v1.0-r12 fix cycle)

**Original decision**: Fix the two text issues in
`draft/v1.0-r7/design-resolutions/01-i-p-frame-ring-buffer.md`.

**Cancellation reason**:
`v1.0-r7/design-resolutions/01-i-p-frame-ring-buffer.md` is a historical
document from v0.7. Modifying historical records is incorrect practice. The ToC
mismatch (Resolution 19 title) and the missing Doc 05 entry are recording
artifacts of the v0.7 cycle — not defects that require correction in v1.0-r12.
The Doc 05 row addition was additionally found to reference sections (§8.2/8.4)
that were deleted in the v0.7 preedit overhaul, making the intended correction
itself incorrect. All v1.0-r12 changes to this file have been reverted.

---

## Resolution 6: Remove frame_type=2 (RN-06)

**Consensus**: 5/5 (writing only — owner pre-decided) **Severity**: MEDIUM

**Decision**: Remove `frame_type=2` (I-frame, unchanged). The `frame_type` field
stays (not renamed). Values become: 0 = P-frame (partial), 1 = I-frame (full
keyframe).

### Rationale

- When the pane is idle, no new frames are written to the ring buffer. The last
  I-frame stays in the ring indefinitely. Seeking clients read it and get
  correct state. There is no need to write a byte-identical duplicate entry.
- Saves ~6-33 KB/s bandwidth per idle pane.
- Removes the byte-comparison logic the server must perform each keyframe tick.
- Simplifies frame_type from 3 values to 2 (KISS).

### Affected locations

Pre-research identified ~20 locations across 5 files:

1. **Doc 04** (~10+ locations):
   - Frame_type table (Section 4.1): Remove row for value 2. Update to show only
     0=P-frame, 1=I-frame.
   - Normative notes referencing `frame_type=2`: Update to reference only
     `frame_type=1` where I-frames are described (implicit I-frame reference
     note, keyframe self-containment rule, row count rule).
   - Section 7.3 (frame_type=2 subsection): Remove ENTIRELY. Section 7 retains
     only 7.1 and 7.2.
   - Section 8.3: Remove paragraph referencing frame_type=2 bandwidth.
   - Flags/section_flags descriptions: Remove frame_type=2 references.
2. **Doc 02**: 3 attach sequences referencing frame_type=2 + Section 7.3
   cross-reference notes.
3. **Doc 03**: 2 attach sequences referencing frame_type=2 + Section 7.3
   cross-reference notes.
4. **Doc 05**: 2 changelog references (historical — update to note further
   reduction from 3 to 2 values).
5. **Doc 06**: 1 changelog reference.

After removing doc 04 Section 7.3, Section 7 has only 7.1 and 7.2 — no
renumbering needed (7.3 is last).

---

## Resolution 7: Remove ghostty_surface_preedit() references (CTR-01)

**Consensus**: 5/5 (writing only — cross-team request from daemon v0.4)
**Severity**: MEDIUM

**Decision**: Remove all `ghostty_surface_preedit()` references from Doc 05.
Replace with wire-observable, implementation-neutral language. The
wire-observable fact (preedit appears as cell data in I/P-frames) MUST remain;
only the specific API name is removed.

### Rationale

Protocol docs describe wire semantics only (v0.11 boundary).
`ghostty_surface_preedit()` is a server-side implementation detail — the daemon
architecture (headless API using `overlayPreedit()` at export time via
`ExportResult`) does not use ghostty Surface. This was established in daemon
v0.3 and confirmed in v0.4.

### Affected locations (expanded scope — 7 occurrences)

The original CTR-01 targeted ~lines 361, 383, 396 in v0.11 Section 4.2. Line
numbers shifted in v1.0-r12. The expanded scope covers all 7 occurrences in Doc
05:

1. **Line 9** (changelog): mentions "server calls `ghostty_surface_preedit()`" —
   historical reference; keep but annotate that this describes the v0.7 design,
   superseded by headless API.
2. **Line 80** (Section 1 overview): "The server calls
   `ghostty_surface_preedit()` on its own surface" — replace with: "the server
   injects preedit cells into frame cell data."
3. **Line 86** (mermaid diagram): node D labeled `ghostty_surface_preedit()` —
   replace with "Inject preedit into cell data."
4. **Line 427** (Section 7.5, post-R8: Section 6.5): "The server calls
   `ghostty_surface_preedit()`" — replace with wire-observable phrasing.
5. **Line 550** (Section 10, post-R8: Section 9): reference to
   `ghostty_surface_preedit()` — replace with generic phrasing.
6. **Line 552** (Section 10, post-R8: Section 9): reference to
   `ghostty_surface_preedit()` — replace with generic phrasing.
7. **Line 691** (Section 14, post-R8: Section 13): same — replace with generic
   phrasing.

---

## Resolution 8: Doc 05 section numbering gap fix

**Consensus**: 5/5 **Severity**: LOW

**Decision**: Close the Section 3 gap in Doc 05 by renumbering all sections from
4 onward: Section 4 becomes Section 3, Section 5 becomes Section 4, ..., Section
15 becomes Section 14.

### Rationale

Section 3 was deleted in v0.7 but the gap was never closed. This leaves a
numbering discontinuity (1, 2, 4, 5, ...) that is confusing for
cross-referencing.

### Affected locations

1. **Doc 05**: Renumber all `##` section headers from current Section 4 through
   Section 15 (shift by -1). Update all internal cross-references within Doc 05.
2. **Docs 01, 02, 03, 04, 06**: Update ALL cross-references to Doc 05 sections
   > = 4 (shift by -1). For example, "Doc 05 Section 7" becomes "Doc 05 Section
   > 6", "Doc 05 Section 14" becomes "Doc 05 Section 13", etc.

---

## Resolution 9: Number all unnumbered subsections

**Consensus**: 5/5 **Severity**: LOW

**Decision**: Add subsection numbers to all unnumbered `###` subsections within
numbered `##` sections, across all docs identified in the pre-research.

### Affected locations

1. **Doc 02 Section 5**: `### CJK Capability Semantics` — add number (5.1) or
   absorb into Section 5 body.
2. **Doc 02 Section 6**: `### Render Capability Notes` unnumbered mixed with
   numbered 6.1, 6.2 — add number (6.0 or rename/absorb).
3. **Doc 03 Section 3**: Leaf Node, Split Node, Example, Maximum Tree Depth —
   add numbers 3.1, 3.2, 3.3, 3.4.
4. **Doc 03 Section 8**: Focus Model, Layout Mutations, Window Size, Input
   Method State, Client Health — add numbers 8.1, 8.2, 8.3, 8.4, 8.5.
5. **Doc 03 Section 9**: Permitted Messages, Prohibited Messages, Readonly
   Receives — add numbers 9.1, 9.2, 9.3.
6. **Doc 04 Section 1**: Message Type Ranges, Common Message Header — add
   numbers 1.1, 1.2.
7. **Doc 04 Section 5**: RLE Cell Encoding, Row Header Extension for RLE — add
   numbers 5.1, 5.2.
8. **Doc 04 Section 10**: Input Messages summary, RenderState Messages summary —
   add numbers 10.1, 10.2.
9. **Doc 05 Section 1**: Architecture Context, Message Type Range — add numbers
   1.1, 1.2.
10. **Doc 06 Sections 1-8**: All unnumbered `###` subsections (Background,
    Message Types, Default Subscriptions, Extension ID Ranges, Known Core
    Extensions, heartbeat subsections, etc.) — add sequential numbers within
    each section.

> **Note**: Doc 05 subsection numbers must account for the gap fix (Resolution
> 8). For example, current Section 4 becomes Section 3 first, then its
> subsections are numbered 3.1, 3.2, etc.

---

## Resolution 10: Preamble sections — leave as-is

**Consensus**: 5/5 **Severity**: LOW

**Decision**: Leave the unnumbered `##` preamble headers (`## Overview`,
`## Message Type Assignments`) in Doc 03 and Doc 06 as-is. Do NOT absorb them
into a numbered `## 1. Overview` section. Defer to a future structural
consistency pass.

### Rationale

1. **Separation of concerns.** Doc 05 renumbering (Resolution 8) fixes a genuine
   defect (gap left by a deleted section). Doc 03/06 preamble absorption would
   be a cosmetic consistency change — structurally different from a defect fix.

2. **Cross-reference churn.** Absorbing preamble into `## 1. Overview` would
   require renumbering all sections in Doc 03 (+1 shift: 1->2, 2->3, ...,
   10->11) and Doc 06 (+1 shift: 1->2, 2->3, ..., 11->12). Combined with the Doc
   05 renumbering (-1 shift), this creates two simultaneous renumbering passes
   with overlapping cross-reference updates, increasing the risk of errors.

3. **No navigability impact.** The preamble sections are introductory/reference
   material. The numbering inconsistency (docs 01/02/04/05 start at `## 1.`,
   docs 03/06 have unnumbered preamble) is cosmetic and does not affect
   cross-referencing or wire format understanding.

---

## Wire Protocol Changes Summary

| Change                                | Impact                                                                               |
| ------------------------------------- | ------------------------------------------------------------------------------------ |
| Mouse + preedit interaction rules     | No wire format change. Behavioral rules added to doc 05 and doc 04.                  |
| Zoom + split: unzoom first            | No wire format change. No new message types or error codes. Server behavior defined. |
| Pane auto-close on process exit       | No wire format change. Server behavior defined.                                      |
| Remove frame_type=2                   | Wire format change: `frame_type` values reduced from 3 to 2 (0=P-frame, 1=I-frame).  |
| Remove ghostty_surface_preedit() refs | No wire format change. Documentation-only (protocol boundary enforcement).           |

## Deferred Items

| Item                                | Deferred to  | Reference                                                                                                          |
| ----------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------ |
| Hyperlink CellData encoding (RN-04) | Post-v1      | `99-post-v1-features.md` Section 6 (new). Design direction: per-row HyperlinkTable side table + JSON URI registry. |
| Remain-on-exit (RN-03)              | Post-v1      | `99-post-v1-features.md` Section 2 (existing).                                                                     |
| Split-and-re-zoom flag (RN-02)      | Post-v1      | tmux `-Z` flag equivalent. Achievable via sequential SplitPane + ZoomPane requests.                                |
| Doc 03/06 preamble absorption       | Future cycle | Cosmetic structural consistency pass.                                                                              |

## Prior Art References

| Reference                                       | Used for                                                           | Location                                                                   |
| ----------------------------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| tmux `window_push_zoom()` / `window_pop_zoom()` | RN-02: Zoom + split unzoom-first pattern                           | `~/dev/git/references/tmux/cmd-split-window.c:109,178`, `window.c:709-728` |
| tmux `WINDOW_ZOOMED` flag                       | RN-02: Zoom is a view mode, not a structural constraint            | `~/dev/git/references/tmux/window.c:661,677,688,691`                       |
| ghostty `hyperlink.zig:20-23`                   | RN-04: Offset hash map pattern (hyperlink ID not inline in cell)   | `vendors/ghostty/src/terminal/hyperlink.zig`                               |
| ghostty `page.zig:1899,1995`                    | RN-04: Per-row and per-cell boolean hyperlink flags                | `vendors/ghostty/src/terminal/page.zig`                                    |
| ghostty `Overlay.zig:149-199`                   | RN-04: Current rendering uses only boolean flag, not hyperlink IDs | `vendors/ghostty/src/renderer/Overlay.zig`                                 |

## Spec Documents Requiring Changes

| Document                                         | Resolutions        | Change Type                                                                                                                                                                                       |
| ------------------------------------------------ | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Doc 01                                           | R6                 | Remove frame_type=2 references                                                                                                                                                                    |
| Doc 02                                           | R6, R8, R9         | Remove frame_type=2 attach sequences; update Doc 05 cross-references (§6→§5, §6.3→§5.3); number subsections in Sections 5, 6                                                                      |
| Doc 03                                           | R2, R3, R6, R8, R9 | Zoom+split normative note; auto-close rules; remove frame_type=2 attach sequences; update Doc 05 cross-reference (§7.7→§6.7); number subsections in Sections 3, 8, 9; close Open Questions #4, #6 |
| Doc 04                                           | R1, R4, R6, R9     | Mouse+preedit cross-ref; close hyperlink Open Question #4; remove frame_type=2 (~10 locations, remove Section 7.3 entirely); number subsections in Sections 1, 5, 10                              |
| Doc 05                                           | R1, R7, R8, R9     | Mouse+preedit rules in Section 7; remove ghostty_surface_preedit() (7 locations); renumber sections 4-15 to 3-14; number subsections in Section 1                                                 |
| Doc 06                                           | R6, R9             | Remove frame_type=2 changelog ref; number subsections in Sections 1-8                                                                                                                             |
| `99-post-v1-features.md`                         | R4                 | Add Section 6: HyperlinkTable design direction                                                                                                                                                    |
| `design-resolutions/01-i-p-frame-ring-buffer.md` | R5 (CANCELLED)     | No changes — historical document; all v1.0-r12 edits reverted                                                                                                                                     |
