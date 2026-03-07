# Design Resolutions: Preedit Protocol Overhaul

**Version**: v0.8
**Date**: 2026-03-07
**Status**: Resolved (7/7 unanimous consensus)
**Participants**: protocol-architect, protocol-swe, cjk-specialist, ime-expert, principal-architect, ime-architect, ime-swe
**Source issues**: Protocol v0.7 review note `04-preedit-protocol-overhaul.md`, IME cross-team request `01-protocol-composition-state-removal.md`
**Scope**: Protocol docs 04, 05, 06 and IME Interface Contract v0.6

---

## Table of Contents

1. [Core Principle](#core-principle)
2. [Resolution 1: Remove composition_state from protocol and IME contract](#resolution-1-remove-composition_state-from-protocol-and-ime-contract)
3. [Resolution 2: Remove FrameUpdate preedit JSON section](#resolution-2-remove-frameupdate-preedit-json-section)
4. [Resolution 3: Remove dual-channel design](#resolution-3-remove-dual-channel-design)
5. [Resolution 4: Remove cursor/width fields from preedit messages](#resolution-4-remove-cursorwidth-fields-from-preedit-messages)
6. [Resolution 5: Remove Section 3 (Korean Composition State Machine)](#resolution-5-remove-section-3-korean-composition-state-machine)
7. [Resolution 6: Remove Section 10.1 cursor style rules](#resolution-6-remove-section-101-cursor-style-rules)
8. [Resolution 7: Remove ring buffer bypass](#resolution-7-remove-ring-buffer-bypass)
9. [Resolution 8: frame_type renumbering](#resolution-8-frame_type-renumbering)
10. [Resolution 9: PreeditUpdate resulting shape](#resolution-9-preeditupdate-resulting-shape)
11. [Resolution 10: PreeditStart resulting shape](#resolution-10-preeditstart-resulting-shape)
12. [Resolution 11: PreeditSync resulting shape](#resolution-11-preeditsync-resulting-shape)
13. [Resolution 12: PanePreeditState struct update](#resolution-12-panepreeditstate-struct-update)
14. [Resolution 13: Session snapshot format update](#resolution-13-session-snapshot-format-update)
15. [Resolution 14: Socket write priority simplification](#resolution-14-socket-write-priority-simplification)
16. [Resolution 15: IME contract composition_state removal](#resolution-15-ime-contract-composition_state-removal)
17. [Resolution 16: IME contract C API callback note](#resolution-16-ime-contract-c-api-callback-note)
18. [Wire Protocol Changes Summary](#wire-protocol-changes-summary)
19. [Spec Documents Requiring Changes](#spec-documents-requiring-changes)
20. [Evidence Base](#evidence-base)
21. [Items Deferred](#items-deferred)

---

## Core Principle

**Preedit is cell data, not metadata.**

The visual PoC (`poc/preedit-visual/`) proved that ghostty renders preedit as a 2-cell block cursor overlay. In the daemon-client architecture, the server calls `ghostty_surface_preedit()` on its own surface, and preedit cells are injected into frame cell data when serializing FrameUpdate. The client renders cells — it has no concept of preedit and never calls `ghostty_surface_preedit()`.

This insight eliminates the dual-channel design (ring buffer for grid + bypass for preedit), the FrameUpdate preedit JSON section, `composition_state`, cursor/width fields in preedit messages, and the ring buffer bypass. All rendering goes through one path: cell data in I/P-frames via the ring buffer. PreeditUpdate (0x0401) becomes lifecycle/metadata only.

---

## Resolution 1: Remove composition_state from protocol and IME contract

**Consensus (7/7).** Remove the `composition_state` field from PreeditUpdate (0x0401) and PreeditSync (0x0403). No component uses this value for rendering, branching, or decision-making.

**Rationale:**
- The libhangul PoC (`poc/libhangul-states/probe.c`) confirmed three factual errors in the documented states: `ko_vowel_only` IS reachable in 2-set, `ko_double_tail` is indistinguishable from `ko_syllable_with_tail` via the public API, and 3-set produces states with no corresponding constant.
- No component consumes `composition_state`. The server passes it through to PreeditUpdate JSON, and no client reads it.
- The field was a documentation exercise, not a feature (IME handover insight).

**Protocol changes:**
- Remove `composition_state` field from PreeditUpdate (doc 05 Section 2.2)
- Remove `composition_state` field from PreeditSync (doc 05 Section 2.4)
- Remove all `composition_state` references throughout doc 05

**IME contract changes:** See [Resolution 15](#resolution-15-ime-contract-composition_state-removal).

---

## Resolution 2: Remove FrameUpdate preedit JSON section

**Consensus (7/7).** Remove the entire `preedit` section from the FrameUpdate JSON metadata blob (doc 04 Section 4.2, doc 05 Section 1).

**Current (removed):**
```json
{
  "preedit": {
    "active": true,
    "cursor_x": 5,
    "cursor_y": 10,
    "text": "han",
    "display_width": 2
  }
}
```

**Rationale:** Preedit rendering is through cell data in I/P-frames. The server calls `ghostty_surface_preedit()` and serializes the resulting cells. The client renders cells without knowing what is preedit. A separate JSON preedit section is redundant.

**Affected locations in doc 04:**
- Section 4.2: Remove preedit fields subsection and JSON example
- Section 4.2: Remove "Cursor behavior during CJK composition" normative note (references `preedit.cursor_x`/`preedit.cursor_y` which no longer exist)
- Section 4.2: Rewrite capability interaction note (no preedit JSON section to interact with)

**Affected locations in doc 05:**
- Section 1: Remove FrameUpdate JSON preedit example and dual-channel description
- Section 3.4: Update backspace decomposition wire trace (remove "FrameUpdate: JSON preedit" lines)
- Section 6.4: Update conflict resolution sequence diagram (remove "FrameUpdate(JSON preedit)" lines)
- Section 7.3: Rewrite resize handling (preedit coordinates are ghostty-internal, no JSON section to update)
- Section 7.5: Rewrite rapid keystroke bursts (no "FrameUpdate with JSON preedit")
- Section 10.2: Rewrite observer client rendering (rendering is from cell data, not preedit JSON)
- Section 13: Remove "FrameUpdate (JSON preedit)" row from bandwidth analysis (preedit bandwidth is now part of cell data)

**Note on section_flags:** Bit 3 was already reserved (formerly Preedit). No change needed — remains reserved.

---

## Resolution 3: Remove dual-channel design

**Consensus (7/7).** Replace the dual-channel architecture with a single-path model.

**Current (removed):** "FrameUpdate JSON (rendering) + PreeditUpdate (metadata)" with "Clients MUST use FrameUpdate's preedit JSON for rendering."

**New model:** Preedit rendering is through cell data in I/P-frames. PreeditUpdate (0x0401) is lifecycle/metadata only — used for multi-client coordination, composition tracking, and debugging. Not used for rendering.

**Affected locations:**
- Doc 05 Section 1: Remove dual-channel description, rendering rule, and architecture diagram showing dual paths. Rewrite to single-path model.
- Doc 05 Section 14: Major rewrite — remove dual-channel premise, "authoritative rendering rule," and capability interaction note. The new Section 14 describes: PreeditUpdate is lifecycle/metadata only; rendering is through cell data; the `"preedit"` capability controls dedicated messages (0x0400-0x0405) only.

**Capability interaction (revised):** The `"preedit"` capability controls only the dedicated PreeditStart/Update/End/Sync messages. Preedit rendering is always available through cell data in I/P-frames regardless of capability negotiation. A client that only needs to render can ignore all 0x04xx messages.

---

## Resolution 4: Remove cursor/width fields from preedit messages

**Consensus (7/7).** Remove `cursor_x`, `cursor_y`, and `display_width` from preedit protocol messages. The server's ghostty surface handles positioning and width internally.

| Message | Fields removed |
|---------|---------------|
| PreeditStart (0x0400) | `cursor_x`, `cursor_y` |
| PreeditUpdate (0x0401) | `cursor_x`, `cursor_y`, `display_width` |
| PreeditSync (0x0403) | `cursor_x`, `cursor_y`, `display_width` |

**Rationale:** The server calls `ghostty_surface_preedit()` which handles cursor positioning (at terminal cursor location) and width (2 cells for Hangul, automatically computed) internally. These values were only needed when the client rendered preedit as a separate overlay from metadata. With preedit as cell data, the client never needs cursor coordinates or display width from the protocol.

---

## Resolution 5: Remove Section 3 (Korean Composition State Machine)

**Consensus (7/7).** Remove doc 05 Sections 3.1 through 3.4 entirely (~130 lines including state values, state transition diagram, complete transition table, and backspace decomposition trace).

**Rationale:**
- The section existed solely to document `composition_state` field semantics. With the field removed, the section has no protocol consumer.
- libhangul is the ground truth for Korean composition. The protocol should not maintain a parallel state machine (IME handover insight: "We should not maintain a parallel state machine in our documents").
- The PoC confirmed factual errors in the documented states, demonstrating the maintenance burden of duplicating libhangul's logic.

**Note:** The backspace decomposition trace in Section 3.4 also contains wire trace examples that reference the dual-channel design. These are removed along with the section.

---

## Resolution 6: Remove Section 10.1 cursor style rules

**Consensus (7/7).** Remove the following normative rules from doc 05 Section 10.1:
- "server MUST set cursor.style to block" during composition
- "client MUST NOT override cursor style"
- All numbered cursor behavior requirements

**Rationale:** Preedit cell decoration (block cursor, 2-cell width, underline) is determined by ghostty's renderer when `ghostty_surface_preedit()` is called server-side. These are ghostty-internal rendering decisions, not protocol requirements. The client renders whatever cells it receives.

**Also remove from doc 04 Section 4.2:** The "Cursor behavior during CJK composition (normative)" note, which references `preedit.cursor_x` and `preedit.cursor_y`.

---

## Resolution 7: Remove ring buffer bypass

**Consensus (7/7).** Remove all ring buffer bypass infrastructure for preedit frames.

**Items removed:**

| Item | Location |
|------|----------|
| `frame_type=0` (P-metadata) bypass semantics | Doc 04 Section 4.1 |
| Resolution 17 (preedit-only frame bypass) | Doc 04 design resolutions (superseded) |
| Resolution 18 (ring contains only grid-state frames) | Doc 04 design resolutions (superseded — ring now contains ALL frames including preedit cell data) |
| Resolution 19 (frame_sequence scope exception) | Doc 04 design resolutions (superseded — all frames increment frame_sequence) |
| Per-client preedit bypass buffer concept | Doc 04, Doc 05 |
| Section 8.2 Rule 2 (preedit bypasses ring) | Doc 05 |
| Section 8.4 (preedit-only FrameUpdate bypass buffer) | Doc 05 — remove entire section |
| Preedit bypass buffer subsection | Doc 06 Section 2.2 — remove |
| "ring does NOT contain preedit-only frames" | Doc 06 Section 2.3 — remove |
| PausePane preedit delivery note | Doc 06 Section 2.4 — remove |
| Stale recovery preedit bypass references | Doc 06 |
| Socket write priority: preedit-bypass at position 1 | Doc 06 |
| Resolution 20 reference (dedicated messages bypass) | Doc 05 Section 14 |

**Rationale:** The bypass existed because preedit was a separate JSON section delivered via a different path than grid cell data. With preedit as cell data in I/P-frames, bypass creates two delivery paths for the same thing (cells), causing ordering and consistency issues. Coalescing Tier 0 (Preedit tier, immediate flush at 0ms) already ensures immediate delivery without a separate path.

**Latency guarantee preserved:** Coalescing Tier 0 means the server serializes and writes the preedit-containing frame to the ring immediately upon keystroke. The 33ms latency target (doc 05 Section 8.2 Rule 4) is maintained. Behind clients receive preedit via I-frame cursor advancement — the latest I-frame already contains preedit cell data.

**Concurrency benefit:** Removing the bypass eliminates a separate per-client locking path. The per-pane ring buffer becomes the single synchronization point for frame data delivery.

**Remaining preedit coalescing rules** (doc 05 Section 8.2):
- Rule 1: Immediate flush on preedit state change — **retained**, rewording: "server MUST write a frame to the ring buffer immediately" (was "flush the FrameUpdate immediately")
- Rule 2: Preedit bypasses the ring buffer — **removed**
- Rule 3: Preedit bypasses power throttling — **retained**
- Rule 4: 33ms latency target — **retained**
- Rule 5: Per-pane preedit cadence — **retained**

---

## Resolution 8: frame_type renumbering

**Consensus (7/7).** Renumber `frame_type` values from 4 values to 3 values.

**Before:**
| Value | Name | Ring? |
|-------|------|-------|
| 0 | P-metadata (bypass) | No (bypass) |
| 1 | P-partial | Yes |
| 2 | I-frame | Yes |
| 3 | I-unchanged | Yes |

**After:**
| Value | Name | Ring? |
|-------|------|-------|
| 0 | P-partial | Yes |
| 1 | I-frame | Yes |
| 2 | I-unchanged | Yes |

**Rationale:** P-metadata (frame_type=0) existed primarily for preedit bypass. With bypass removed, there is no behavioral difference between a metadata-only frame and a P-partial frame with zero dirty rows. A P-partial frame with `num_dirty_rows=0` is semantically "the grid hasn't changed since the last I-frame, but the JSON metadata blob has updated cursor/mode information." The `section_flags` bit 4 (DirtyRows present) already tells the client whether to parse DirtyRows — no dedicated frame type needed for the metadata-only case.

**Discussion:** protocol-swe proposed keeping 4 values (retaining P-metadata as a named type without bypass semantics) for client optimization. The team determined that `section_flags bit 4` already provides this optimization — clients check the bit to know whether DirtyRows is present, regardless of frame_type. A dedicated enum value that duplicates information in section_flags violates KISS and creates a "what is this for?" question for future readers after the bypass is removed.

All frames now go through the ring buffer. `frame_sequence` is incremented for all frames (Resolution 19 from v0.7 is superseded).

---

## Resolution 9: PreeditUpdate resulting shape

**Consensus (7/7).** PreeditUpdate (0x0401) becomes a lifecycle/metadata-only message.

**After:**
```json
{
  "pane_id": 1,
  "preedit_session_id": 42,
  "text": "han"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `preedit_session_id` | u32 | Matches PreeditStart |
| `text` | string | UTF-8 preedit text (for multi-client coordination and debugging, NOT for rendering) |

**Removed fields:** `cursor_x`, `cursor_y`, `display_width`, `composition_state`.

**Rationale:** The `text` field is retained because multi-client coordination needs to know what is being composed (e.g., observer display of "Client A composing X"). This is not a DRY violation — cell data and PreeditUpdate serve different consumers (renderer vs. session manager/observers).

---

## Resolution 10: PreeditStart resulting shape

**Consensus (7/7).** PreeditStart (0x0400) after field removal:

```json
{
  "pane_id": 1,
  "client_id": 7,
  "active_input_method": "korean_2set",
  "preedit_session_id": 42
}
```

**Removed fields:** `cursor_x`, `cursor_y`.

---

## Resolution 11: PreeditSync resulting shape

**Consensus (7/7).** PreeditSync (0x0403) after field removal:

```json
{
  "pane_id": 1,
  "preedit_session_id": 42,
  "preedit_owner": 7,
  "active_input_method": "korean_2set",
  "text": "han"
}
```

**Removed fields:** `cursor_x`, `cursor_y`, `composition_state`, `display_width`.

PreeditSync remains necessary for late-joining clients — they need `preedit_owner`, `preedit_session_id`, and `active_input_method` to correctly handle subsequent PreeditUpdate and PreeditEnd messages. The visual preedit state is already in the I-frame cell data they receive from the ring.

---

## Resolution 12: PanePreeditState struct update

**Consensus (7/7).** Update the `PanePreeditState` struct in doc 05 Section 6.2.

**Before:**
```
struct PanePreeditState {
    owner: ?u32,
    preedit_session_id: u32,
    state: CompositionState,
    preedit_text: []u8,
    cursor_x: u16,
    cursor_y: u16,
}
```

**After:**
```
struct PanePreeditState {
    owner: ?u32,
    preedit_session_id: u32,
    preedit_text: []u8,
}
```

**Removed:** `state` (composition_state has no consumer), `cursor_x`, `cursor_y` (ghostty handles positioning). The struct is now pure ownership tracking for multi-client coordination.

---

## Resolution 13: Session snapshot format update

**Consensus (7/7).** Update the session snapshot preedit section in doc 05 Section 9.1.

**Before:**
```json
{
  "preedit": {
    "active": true,
    "session_id": 42,
    "owner_client_id": 7,
    "composition_state": "ko_syllable_with_tail",
    "preedit_text": "han",
    "cursor_x": 15,
    "cursor_y": 3
  }
}
```

**After:**
```json
{
  "preedit": {
    "active": true,
    "session_id": 42,
    "owner_client_id": 7,
    "preedit_text": "han"
  }
}
```

**Removed:** `composition_state` (no consumer), `cursor_x`, `cursor_y` (ghostty-internal).

**Rationale:** On restore, the server commits preedit text to PTY (Section 9.2). Only `preedit_text` is needed for this. Cursor position is not needed at restore time — ghostty determines cursor position from the terminal state.

---

## Resolution 14: Socket write priority simplification

**Consensus (7/7).** After removing the preedit bypass buffer, the socket write priority model in doc 06 drops from 3 levels to 2 levels.

**Before:**
1. Preedit bypass buffer (highest priority)
2. Direct message queue
3. Ring buffer frames

**After:**
1. Direct message queue (LayoutChanged, PreeditSync, ClientHealthChanged, etc.)
2. Ring buffer frames (via `writev()` zero-copy from ring memory)

PreeditSync remains in the direct message queue (priority 1), ensuring a recovering client receives composition metadata BEFORE the I-frame containing preedit cells. This preserves the "context before content" principle.

---

## Resolution 15: IME contract composition_state removal

**Consensus (7/7).** Apply all 6 changes from cross-team request `01-protocol-composition-state-removal.md`.

| # | Change | Location | Detail |
|---|--------|----------|--------|
| 1 | Remove `composition_state` field from `ImeResult` | Section 3.2 (02-types.md) | Remove `composition_state: ?[]const u8 = null` and its doc comment |
| 2 | Remove `composition_state` column from scenario matrix | Section 3.2 (02-types.md) | Matrix retains 4 columns: `committed_text`, `preedit_text`, `forward_key`, `preedit_changed` |
| 3 | Remove `CompositionStates` struct from `HangulImeEngine` | Section 3.7 (03-engine-interface.md) | Remove the struct with 5 string constants entirely |
| 4 | Remove composition-state naming convention | Section 3.7 (03-engine-interface.md) | Remove the `ko_` prefix table, `zh_pinyin_`/`zh_bopomofo_`/`zh_cangjie_` prefix table, and the discriminating factor note. Input method identifier naming convention (`"korean_*"`) in Section 3.4 is unaffected. |
| 5 | Remove `.composition_state = null` from `setActiveInputMethod` examples | Section 3.6 (03-engine-interface.md) | Remove from both Case 1 ImeResult examples |
| 6 | Remove `composition_state` memory model note | Section 6 (04-ghostty-integration.md) | Remove "Points to static string literals. Valid indefinitely — not invalidated by any method call." |

**Rationale:** `composition_state` was added in IME contract v0.4 (Appendix E.4) as a pass-through for the protocol. No vtable method inspects, branches on, or transforms this field. The producer (IME engine) and consumer (protocol PreeditUpdate) are both removed simultaneously — no orphan.

**Not affected:**
- `handleKeyEvent()`, `handleIntraSessionFocusChange()`, `handleInputMethodSwitch()` code in Section 5 — none reference `composition_state`
- `MockImeEngine` test example — does not use `composition_state`
- `ImeEngine` vtable — no method signature changes
- Remaining `ImeResult` fields (`committed_text`, `preedit_text`, `forward_key`, `preedit_changed`) and their memory model — unchanged

---

## Resolution 16: IME contract C API callback note

**Consensus (7/7).** The `itshell3_preedit_cb` callback signature in IME contract Section 8 (05-extensibility-and-deployment.md) needs revision.

**Current:**
```c
typedef void (*itshell3_preedit_cb)(
    uint32_t pane_id,
    const char* text,
    size_t text_len,
    uint32_t cursor_x,
    uint32_t cursor_y,
    void* userdata
);
```

**Action:** Add a note that `cursor_x` and `cursor_y` parameters are obsolete under the "preedit is cell data" model and will be removed when the C API is implemented. The callback's purpose should be re-evaluated: with preedit rendering via cell data, the callback may serve only non-rendering uses (status bar, accessibility) with a simplified signature of `(pane_id, text, text_len, userdata)`.

**Rationale:** This callback is speculative/future code (labeled "In itshell3.h"). It does not affect the wire protocol or IME contract types. Three team members independently flagged it (principal-architect, ime-swe, ime-architect). Rather than removing the hypothetical code now, a note ensures consistency when the C API is eventually implemented.

---

## Wire Protocol Changes Summary

### Messages modified

| Message | Type | Fields removed |
|---------|------|---------------|
| PreeditStart | 0x0400 | `cursor_x`, `cursor_y` |
| PreeditUpdate | 0x0401 | `cursor_x`, `cursor_y`, `display_width`, `composition_state` |
| PreeditSync | 0x0403 | `cursor_x`, `cursor_y`, `display_width`, `composition_state` |
| FrameUpdate | 0x0300 | Entire `preedit` JSON section removed from metadata blob |

### frame_type values changed

| Before | After |
|--------|-------|
| 0 = P-metadata (bypass) | 0 = P-partial |
| 1 = P-partial | 1 = I-frame |
| 2 = I-frame | 2 = I-unchanged |
| 3 = I-unchanged | (removed) |

### Delivery model changed

| Before | After |
|--------|-------|
| 3-level socket write priority | 2-level socket write priority |
| Preedit bypass buffer + direct queue + ring | Direct queue + ring |
| frame_sequence exception for bypass frames | All frames increment frame_sequence |

---

## Spec Documents Requiring Changes

### Doc 04 — Input Forwarding and RenderState Protocol

| Location | Change |
|----------|--------|
| Section 4.1 | Remove frame_type=0 (P-metadata), renumber to {0, 1, 2}. Remove Resolution 17 bypass normative notes. Remove frame_sequence scope exception. |
| Section 4.2 | Remove entire preedit fields subsection from JSON metadata. Remove "Cursor behavior during CJK composition" normative note. Rewrite capability interaction note. |
| Section 7 heading/content | Update frame_type value descriptions (was 0-3, now 0-2). |
| Appendix A hex dump | Update frame_type value in example. |
| Changes-from header | Add entry for this resolution. |

### Doc 05 — CJK Preedit Sync and IME Protocol

| Location | Change |
|----------|--------|
| Section 1 | Rewrite architecture diagram (remove dual-channel lines). Remove dual-channel description, rendering rule. Rewrite to single-path model. |
| Section 2.1 | Remove `cursor_x`, `cursor_y` from PreeditStart. Remove note about PreeditStart not carrying composition_state. |
| Section 2.2 | Remove `cursor_x`, `cursor_y`, `display_width`, `composition_state` from PreeditUpdate. Remove display_width computation note. |
| Section 2.4 | Remove `cursor_x`, `cursor_y`, `display_width`, `composition_state` from PreeditSync. |
| Section 3 (3.1-3.4) | Remove entirely (~130 lines). |
| Section 6.2 | Update PanePreeditState struct (remove `state`, `cursor_x`, `cursor_y`). |
| Section 6.4 | Update conflict resolution sequence diagram (remove "FrameUpdate(JSON preedit)" lines). |
| Section 7.3 | Rewrite resize handling (no PreeditUpdate cursor coordinates, no JSON preedit section). |
| Section 7.5 | Rewrite rapid keystroke bursts (no "FrameUpdate with JSON preedit"). |
| Section 8.2 | Remove Rule 2 (preedit bypass). Reword remaining rules for ring buffer delivery. |
| Section 8.4 | Remove entire section (preedit-only FrameUpdate bypass buffer). |
| Section 9.1 | Update snapshot format (remove `composition_state`, `cursor_x`, `cursor_y`). |
| Section 10.1 | Remove cursor style normative rules. |
| Section 10.2 | Rewrite observer client rendering description. |
| Section 13 | Remove "FrameUpdate (JSON preedit)" row from bandwidth analysis. |
| Section 14 | Major rewrite — remove dual-channel premise, authoritative rendering rule, capability interaction. |
| Section 15 | Remove Q1 (Japanese/Chinese composition states) — moot with composition_state removed. |
| Changes-from header | Add entry for this resolution. |

### Doc 06 — Flow Control and Auxiliary Protocols

| Location | Change |
|----------|--------|
| Section 2.2 | Remove preedit bypass buffer subsection. |
| Section 2.3 | Remove "ring does NOT contain preedit-only frames." |
| Section 2.4 | Remove PausePane preedit delivery note. |
| Socket write priority | Drop from 3-level to 2-level. Remove preedit-bypass at position 1. |
| Stale recovery | Remove preedit bypass references. |
| Resolution 17 summary | Mark as superseded by this resolution. |
| Changes-from header | Add entry for this resolution. |

### IME Interface Contract v0.6

| Location | Change |
|----------|--------|
| Section 3.2 (02-types.md) | Remove `composition_state` field from ImeResult. Remove column from scenario matrix. |
| Section 3.6 (03-engine-interface.md) | Remove `.composition_state = null` from setActiveInputMethod examples. |
| Section 3.7 (03-engine-interface.md) | Remove `CompositionStates` struct. Remove composition-state naming convention. |
| Section 6 (04-ghostty-integration.md) | Remove `composition_state` memory model note. |
| Section 8 (05-extensibility-and-deployment.md) | Add note that `itshell3_preedit_cb` signature needs revision (cursor_x/cursor_y obsolete). |

---

## Evidence Base

| Evidence | Finding | Impact |
|----------|---------|--------|
| `poc/libhangul-states/probe.c` | `ko_vowel_only` reachable in 2-set; `ko_double_tail` indistinguishable from `ko_syllable_with_tail`; 3-set produces unmapped state | composition_state has factual errors and no consumer |
| `poc/preedit-visual/` | ghostty renders preedit as 2-cell block cursor; cursor NOT suppressed; ghostty handles positioning/width automatically | Preedit is cell data, not a separate metadata layer |
| Research `07-ghostty-preedit-cell-serialization.md` | Server calls `ghostty_surface_preedit()`, injects preedit cells into frame cell data; client never calls preedit APIs | Single delivery path through I/P-frames suffices |

---

## Items Deferred

| Item | Rationale |
|------|-----------|
| v2 candidate window extension (`anchor` field for PreeditUpdate) | Future CJK language support. Additive extension, not current v1 scope. Review note 04 Section 8 sketches the schema. |
| `itshell3_preedit_cb` callback full revision | Speculative C API, not yet implemented. Noted for future consistency (Resolution 16). |
