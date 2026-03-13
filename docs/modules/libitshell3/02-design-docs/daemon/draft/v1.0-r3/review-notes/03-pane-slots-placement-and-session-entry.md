# pane_slots Placement and SessionEntry Introduction

**Date**: 2026-03-10
**Raised by**: verification team + owner
**Severity**: HIGH
**Affected docs**: `v0.2/01-internal-architecture.md` (Sections 1.5, 3.2, 3.3), `v0.1/design-resolutions/01-daemon-architecture.md` (R1, R3), `v0.2/design-resolutions/01-v0.2-review-note-resolutions.md` (Section 1.3)
**Status**: open

---

## Problem

Two normative documents contradict each other on where `pane_slots` lives:

- **v0.1 R1 rationale** (line 55): "`pane_slots: [MAX_PANES]?*Pane` **in `server/`**" and "not by pointer, preserving the dependency boundary"
- **v0.2 doc 01** Section 3.3: `pane_slots: [MAX_PANES]?*Pane` inside `Session` annotated as `core/session.zig`

This creates a `core/ → server/` reverse dependency: `Session` (in `core/`) holds `?*Pane`, but `Pane` is defined in `server/pane.zig` because it owns ghostty types (`*ghostty.Terminal`, `*ghostty.RenderState`) and OS resources (`pty_fd`, `child_pid`). This violates the stated invariant: "core/ depends on nothing."

The v0.1 resolution doc also contradicts itself — R1 says "in server/" while R3 shows pane_slots inside Session (in core/).

## Analysis

### Why Pane must stay in server/

Pane owns `*ghostty.Terminal`, `*ghostty.RenderState`, `pty_fd`, `child_pid`. Placing Pane in `core/` would create `core/ → ghostty/` and `core/ → OS` dependencies, violating the module decomposition.

### Why core/ doesn't need pane_slots

core/'s operations on Session all use slot indices (integers), not the Pane array:

- **Slot allocation/deallocation**: `free_mask` bit operations only
- **Tree mutation**: leaf stores `PaneSlot` value only
- **dirty_mask**: bit operations by slot index
- **focused_pane**: `?PaneSlot` value only
- **PaneId → PaneSlot lookup**: linear scan of pane_slots, but this happens at the `server/` protocol boundary (cold path)

No core/ code path needs to dereference a Pane pointer.

### Why splitting Pane (PaneState + PaneRuntime) is unnecessary

If pane_slots moves entirely to server/, the split motivation disappears. Pane stays as one struct in server/ — simpler, no artificial separation.

## Proposed Change

**Owner decision**: Remove `pane_slots` from `Session` (core/) and introduce `SessionEntry` in server/.

```zig
// server/session_entry.zig
const SessionEntry = struct {
    session: Session,                 // core/ type — no pane_slots
    pane_slots: [MAX_PANES]?Pane,     // Pane by value, not pointer
};
```

Key changes:

1. **Session (core/session.zig)**: Remove `pane_slots: [MAX_PANES]?*Pane` field
2. **SessionEntry (server/)**: New struct bundling Session + pane_slots
3. **SessionManager**: `HashMap(u32, *Session)` → `HashMap(u32, *SessionEntry)`
4. **Pane storage**: Changes from `?*Pane` (pointer in Session) to `?Pane` (value in SessionEntry)
5. **Mapping**: Session ↔ Pane linked by PaneSlot index within the same SessionEntry

This resolves the dependency violation while aligning with the v0.1 R1 rationale ("pane_slots in server/").

## Owner Decision

Adopt SessionEntry approach as described above. Rationale: core/ genuinely has no need to access Pane instances — all Pane access happens in server/ via fd operations and ghostty API calls. Keeping pane_slots in server/ preserves "core/ depends on nothing" without introducing artificial type splits.

## Resolution

