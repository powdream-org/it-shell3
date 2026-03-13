# Design Resolution 01: Top-Severity Fixes

**Version**: v0.10
**Date**: 2026-03-10
**Status**: Resolved (5/5 unanimous consensus)
**Participants**: protocol-architect, system-sw-engineer, cjk-specialist, ime-expert, principal-architect
**Sources**: RN-01 (`v0.9/review-notes/01-scroll-delivery-design.md`), RN-02 (`v0.9/review-notes/02-preeditend-reason-cleanup.md`), cross-team request (`v0.9/cross-team-requests/01-daemon-architecture-requirements.md` Change 3), R3-T01 (`v0.9/handover/handover-to-v0.10.md`)
**Scope**: Docs 02, 03, 04, 05, 06

---

## Resolution 1: Revert scroll I-frame per-client delivery (RN-01)

**Consensus**: 5/5
**Severity**: CRITICAL

**Decision**: Remove the V2-04 text in Doc 04 Section 6.1 that routes scroll-response I-frames through the per-client direct message queue. Scroll-response I-frames go through the shared ring buffer like any other I-frame.

### Affected locations

1. **Doc 04 Section 6.1** (line 837): Remove the sentence "This I-frame is delivered via the per-client direct message queue (priority 1), NOT the shared ring buffer, because scroll is a per-client viewport operation — writing it to the shared ring would expose a scrolled viewport to all clients, including those that did not request the scroll." Replace with: "Scroll-response I-frames are written to the shared ring buffer like any other I-frame. When one client scrolls, all attached clients receive the scrolled viewport. This is consistent with the globally singleton session model."

2. **Doc 06 Section 2.3** (line 276): Remove the exception sentence "The sole exception is scroll-response I-frames, which are delivered via the per-client direct message queue because scroll is a per-client viewport operation (see doc 04 Section 6.1)." The preceding statement "All rendering frames (I-frames, P-frames) go through the ring — there are no bypass paths for rendered content" becomes unconditionally true.

### Rationale

1. **The design is globally singleton.** All clients share the same session state — there are no per-client independent viewports. Per-client scroll positions contradict this core design principle. When one client scrolls, all clients see the scrolled viewport (same as tmux).

2. **Direct message queue is for small control messages** (~110B preedit bypass, LayoutChanged, PreeditSync), not full I-frames (~38KB-116KB).

3. **Ring buffer model integrity.** `frame_sequence` is ring-only (Resolution 19, v0.7). Direct-queue I-frames have no specified `frame_sequence` behavior, which was flagged as a V3-01 inconsistency. Routing all I-frames through the ring eliminates this problem.

4. **ScrollPosition message** (Doc 04 Section 6.2) sends viewport position metadata to all clients. In a global model, this is broadcast — consistent with the corrected scroll I-frame delivery.

### Cross-doc verification

Doc 06 Section 2.3 ripple was independently identified by principal-architect, system-sw-engineer, and cjk-specialist. Docs 01, 02, 03, 05 do not reference scroll delivery routing — no further ripple.

---

## Resolution 2: Remove PreeditEnd "input_method_changed" reason (RN-02)

**Consensus**: 5/5
**Severity**: HIGH

**Decision**: Remove `"input_method_changed"` as a PreeditEnd reason value. For InputMethodSwitch during active preedit, use `"committed"` when `commit_current=true` and `"cancelled"` when `commit_current=false`.

### Affected locations (all in Doc 05)

1. **Section 2.3** (line 202): Remove `"input_method_changed"` from the PreeditEnd reason values list.

2. **Section 7.9 server behavior** (lines 546-549): Eliminate step 3 (the unconditional PreeditEnd with `reason="input_method_changed"`). Fold PreeditEnd into step 1 and step 2. The 5-step sequence becomes 4 steps:
   - Step 1: If `commit_current=true`, commit current preedit text to PTY, send PreeditEnd with `reason="committed"` to all clients
   - Step 2: If `commit_current=false`, cancel current preedit, send PreeditEnd with `reason="cancelled"` to all clients
   - Step 3: Switch the session's input method (applies to all panes)
   - Step 4: Send InputMethodAck to all attached clients

3. **Section 7.9 wire trace** (lines 562, 564): Change `reason=input_method_changed` to `reason=committed` (the wire trace shows the `commit_current=true` path).

4. **Changelog entries** (lines 57-58): Do NOT modify. These are historical records of what v0.8 introduced. The v0.10 changelog will record the removal.

### Rationale

1. **No semantic distinction from the client's perspective.** Whether preedit ends because the input method switched or because the user cancelled, the client behavior is identical: clear the preedit display. The distinction adds complexity without behavioral value.

2. **Aligns Section 7.9 with Section 4.1.** Section 4.1 (lines 267-278) already correctly uses `"cancelled"` for `commit_current=false` and describes commit/cancel as inline steps. Section 7.9 contradicts this by sending a separate `reason="input_method_changed"` in step 3. The fix makes the two sections consistent.

3. **IME engine is reason-agnostic.** ime-expert confirmed the IME contract (v0.7) has zero references to `"input_method_changed"`. The IME engine's `flush()`/`reset()` produces identical `ImeResult` regardless of what triggered the operation. The reason is purely a protocol-layer annotation with no downstream consumer.

### Cross-doc verification

`"input_method_changed"` does not appear in Docs 01, 02, 03, 04, or 06. Confirmed independently by protocol-architect and cjk-specialist. No cross-module impact (IME contract verified by ime-expert).

---

## Resolution 3: Add PANE_LIMIT_EXCEEDED error to SplitPaneResponse

**Consensus**: 5/5
**Severity**: NORMAL (cross-team request from daemon architecture v0.1)

**Decision**: Add `PANE_LIMIT_EXCEEDED` (status code 8) to the Doc 03 error code table and to SplitPaneResponse. The server rejects SplitPaneRequest when the session's pane count would exceed the daemon's 16-pane-per-session limit. The limit is NOT announced in ServerHello.

### Affected locations (all in Doc 03)

1. **Section 6 error code table** (line 996): Add code 8, name `PANE_LIMIT_EXCEEDED`, description "Cannot create pane — session pane limit reached".

2. **Section 2.4 SplitPaneResponse** (line 432): Add field documentation table (currently missing) and failure JSON example:
   ```json
   {
     "status": 8,
     "error": "PANE_LIMIT_EXCEEDED"
   }
   ```
   On success, the existing format is unchanged: `{ "status": 0, "new_pane_id": 3 }`.

### Scope: SplitPane only

CreatePaneRequest (Section 2.1) always replaces the current layout root — it destroys the existing tree and substitutes a single pane. After CreatePane, the session has exactly 1 pane. PANE_LIMIT_EXCEEDED is logically unreachable for CreatePane and is therefore not added to CreatePaneResponse. If CreatePane semantics change in the future to allow adding without replacing, the error code can be added at that time.

### Design decisions

- **Not in ServerHello**: The limit is not announced during capability negotiation. The server is the sole source of truth for pane count. The client does not track pane counts — it sends SplitPane requests and handles success/failure responses. This keeps the client thin and avoids client-server counter synchronization issues.

- **Orthogonal to tree depth limit**: Doc 03 Section 3 (Maximum Tree Depth subsection) enforces a maximum tree depth of 16 levels. The daemon's 16-pane limit is a separate policy constraint. The pane limit will be hit long before the depth limit in practice. Both constraints coexist; no change to Section 3 is needed.

### Prior art

tmux does not expose a pane limit in its protocol — the server simply rejects operations that exceed resource limits. The client handles the error response. This is the same pattern.

---

## Resolution 4: Fix frame_type=2 wording in attach sequences (R3-T01)

**Consensus**: 5/5
**Severity**: MECHANICAL (v0.8 authoring regression)

**Decision**: Change `(frame_type=2)` to `(frame_type=1 or frame_type=2)` in all attach sequence descriptions across Doc 02 and Doc 03. The server may send either an I-frame (`frame_type=1`) or an I-unchanged (`frame_type=2`) on initial attach; the client MUST treat both as `frame_type=1` per Doc 04 Section 7.3 (seeking context).

### Affected locations

**Doc 03** (owner: system-sw-engineer):
1. **Section 1.6** (line 201): AttachSessionResponse post-attach sequence — change `(frame_type=2)` to `(frame_type=1 or frame_type=2)`.
2. **Section 1.14** (line 348): AttachOrCreateResponse post-attach sequence — same fix.

**Doc 02** (owner: protocol-architect):
3. **Section 9.2** (line 720): Attach sequence step 3 — change `(frame_type=2)` to `(frame_type=1 or frame_type=2)`.
4. **Section 9.2** (line 727): Client processing step — change `(frame_type=2)` to `(frame_type=1 or frame_type=2)`.
5. **Section 9.4** (line 780): Create-and-attach sequence — change `(frame_type=2)` to `(frame_type=1 or frame_type=2)`.
6. **Section 11** (line 983): Reconnection description — change `(frame_type=2)` to `(frame_type=1 or frame_type=2)`.

### Discovery

The handover identified 2 locations in Doc 03. During team discussion, protocol-architect identified 4 additional locations in Doc 02 with the same v0.8 authoring error. All 6 locations have identical text patterns and require the same mechanical fix. Verified independently by principal-architect.

### Rationale

The v0.8 frame_type renumbering (Resolution 8 in `v0.8/design-resolutions/01-preedit-overhaul.md`) changed I-frame from `frame_type=2` to `frame_type=1` and I-unchanged from `frame_type=3` to `frame_type=2`. The attach sequence descriptions were updated to reference `frame_type=2` (I-unchanged) but should have been updated to `frame_type=1 or frame_type=2` (either I-frame variant), since the server may send a fresh I-frame or reuse the latest ring entry depending on whether the pane has changed.

---

## Wire Protocol Changes Summary

| Change | Message/Field | Before | After |
|--------|--------------|--------|-------|
| R1 | Scroll I-frame delivery | Per-client direct message queue | Shared ring buffer |
| R2 | PreeditEnd reason enum | 8 values (incl. `"input_method_changed"`) | 7 values (`"input_method_changed"` removed) |
| R3 | SplitPaneResponse | No error field | `status: 8` + `error: "PANE_LIMIT_EXCEEDED"` on failure |
| R3 | Error code table | Codes 0-7 | Codes 0-8 (add `PANE_LIMIT_EXCEEDED`) |
| R4 | Attach sequence text | `(frame_type=2)` | `(frame_type=1 or frame_type=2)` |

## Spec Documents Requiring Changes

| Doc | Owner | Changes |
|-----|-------|---------|
| Doc 02 | protocol-architect | R4: 4 locations (Section 9.2 x2, Section 9.4, Section 11) |
| Doc 03 | system-sw-engineer | R3: Section 2.4 + Section 6. R4: Section 1.6 + Section 1.14 |
| Doc 04 | cjk-specialist | R1: Section 6.1 |
| Doc 05 | cjk-specialist | R2: Section 2.3 + Section 7.9 (4 edits) |
| Doc 06 | system-sw-engineer | R1 ripple: Section 2.3 |

## Items Deferred

None. All 4 items are fully resolved.
