# Design Resolutions: Daemon v0.4 Review Note Resolutions

**Date**: 2026-03-11
**Team**: daemon-architect, ghostty-integration-engineer, ime-system-sw-engineer, principal-architect, protocol-architect, system-sw-engineer (6 members)
**Scope**: 4 review notes carried over from v0.3 owner review
**Source review notes**:
- 05-session-detach-request-naming (CRITICAL)
- 03-pane-slots-placement-and-session-entry (HIGH)
- 01-splitnode-remnants-in-v01-resolution (LOW)
- 02-pty-fd-naming-inconsistency (LOW)

---

## Resolution 1: Message Type Naming Alignment (6/6 unanimous)

**Source**: Review note 05 (CRITICAL), expanded during discussion to cover all non-normative message type names
**Affected docs**: `v0.4/03-lifecycle-and-connections.md`, `v0.1/design-resolutions/01-daemon-architecture.md`

### Decision

Align all message type names in daemon docs to match the normative message type table in protocol doc 01 (v0.6). Three mismatches were identified across 11 normative occurrences in 2 files.

### 1.1 SessionDetachRequest to DetachSessionRequest (3 occurrences)

Protocol normative name: `DetachSessionRequest` (0x0106).

| # | File | Line | Current | Replacement |
|---|------|------|---------|-------------|
| 1 | `v0.4/03-lifecycle-and-connections.md` | 406 | `SessionDetachRequest` | `DetachSessionRequest` |
| 2 | `v0.4/03-lifecycle-and-connections.md` | 435 | `SessionDetachRequest` | `DetachSessionRequest` |
| 3 | `v0.1/design-resolutions/01-daemon-architecture.md` | 443 | `SessionDetachRequest` | `DetachSessionRequest` |

### 1.2 ResizeRequest to WindowResize (1 occurrence)

Protocol normative name: `WindowResize` (0x0190). The context ("Update `display_info`, recalculate pane dimensions") confirms this is a client window resize, not a split divider adjustment (`ResizePaneRequest` 0x014A).

| # | File | Line | Current | Replacement |
|---|------|------|---------|-------------|
| 4 | `v0.4/03-lifecycle-and-connections.md` | 438 | `ResizeRequest` | `WindowResize` |

### 1.3 ServerShutdown to Disconnect (7 occurrences)

The protocol has no `ServerShutdown` message type. The protocol defines `Disconnect` (0x0005) with a `reason` field; `"server_shutdown"` is one of the defined reason values. Each replacement should make the reason semantics clear in context (e.g., "Send `Disconnect` message with `reason: server_shutdown`"). Inclusion of ServerShutdown in RN-05 scope is a binding owner decision.

| # | File | Line | Current | Replacement |
|---|------|------|---------|-------------|
| 5 | `v0.4/03-lifecycle-and-connections.md` | 209 | `ServerShutdown` | `Disconnect` (reason: `server_shutdown`) |
| 6 | `v0.4/03-lifecycle-and-connections.md` | 239 | `ServerShutdown` | `Disconnect` (reason: `server_shutdown`) |
| 7 | `v0.4/03-lifecycle-and-connections.md` | 245 | `ServerShutdown` | `Disconnect` (reason: `server_shutdown`) |
| 8 | `v0.4/03-lifecycle-and-connections.md` | 383 | `ServerShutdown` | `Disconnect` (reason: `server_shutdown`) |
| 9 | `v0.4/03-lifecycle-and-connections.md` | 417 | `ServerShutdown` | `Disconnect` (state diagram shorthand) |
| 10 | `v0.4/03-lifecycle-and-connections.md` | 440 | `ServerShutdown` | `Disconnect` (state table shorthand) |
| 11 | `v0.1/design-resolutions/01-daemon-architecture.md` | 413 | `ServerShutdown` | `Disconnect` (reason: `server_shutdown`) |

### 1.4 Deferred: ErrorResponse Semantic Correction

`ErrorResponse` appears in daemon docs as descriptive prose (e.g., doc 01 line 169: "enforced server-side via ErrorResponse"). The protocol uses a two-layer error model:

- **Layer 1 (typed responses)**: Expected failures use non-zero `status` fields in the specific response message (e.g., `SplitPaneResponse` with `status: PANE_LIMIT_EXCEEDED`).
- **Layer 2 (Error 0x00FF)**: Unexpected or cross-cutting protocol errors.

Renaming `ErrorResponse` to `Error` would be misleading because the daemon doc usage refers to Layer 1 typed responses, not the Layer 2 `Error` message. The correct fix requires per-occurrence semantic rewording. Deferred to the writing phase as a separate item.

### 1.5 Wire Protocol Changes

**None.** These are documentation-only corrections aligning daemon docs to existing protocol normative names.

---

## Resolution 2: SessionEntry Introduction and pane_slots Migration (6/6 unanimous + owner binding decision)

**Source**: Review note 03 (HIGH), with owner directive on mask placement
**Affected docs**: `v0.4/01-internal-architecture.md` (Sections 1.5, 3.2, 3.3), `v0.1/design-resolutions/01-daemon-architecture.md` (R1, R3), `v0.2/design-resolutions/01-v0.2-review-note-resolutions.md` (Section 1.3)

### Decision

Introduce `SessionEntry` in `server/session_entry.zig` as a server-side wrapper that bundles `Session` (core/) with pane-slot management state. Move `pane_slots`, `free_mask`, and `dirty_mask` from `Session` (core/) to `SessionEntry` (server/). `focused_pane` stays in `Session`.

### 2.1 Updated Structs

```zig
// core/session.zig — pane_slots, free_mask, dirty_mask removed
pub const Session = struct {
    session_id: u32,
    name: []const u8,
    ime_engine: ImeEngine,
    active_input_method: []const u8,
    keyboard_layout: []const u8,
    tree_nodes: [MAX_TREE_NODES]?SplitNodeData,
    focused_pane: ?PaneSlot,
    creation_timestamp: i64,
    current_preedit: ?[]const u8,
    preedit_buf: [64]u8,
};

// server/session_entry.zig (NEW)
const SessionEntry = struct {
    session: Session,
    pane_slots: [MAX_PANES]?Pane,  // by value, not pointer
    free_mask: u16,
    dirty_mask: u16,
};
```

### 2.2 Key Changes

1. **Session (core/session.zig)**: Remove `pane_slots`, `free_mask`, and `dirty_mask` fields.
2. **SessionEntry (server/session_entry.zig)**: New struct bundling `Session` + `pane_slots` + `free_mask` + `dirty_mask`.
3. **SessionManager**: `HashMap(u32, *Session)` changes to `HashMap(u32, *SessionEntry)`.
4. **Pane storage**: Changes from `?*Pane` (pointer in Session) to `?Pane` (value in SessionEntry).
5. **Mapping**: Session and Pane linked by `PaneSlot` index within the same `SessionEntry`.

### 2.3 Rationale

**Dependency violation**: `Session` in `core/` held `?*Pane`, but `Pane` is defined in `server/` because it owns ghostty types (`*ghostty.Terminal`, `*ghostty.RenderState`) and OS resources (`pty_fd`, `child_pid`). This created a `core/ -> server/` reverse dependency, violating the invariant "core/ depends on nothing."

**Mask cohesion (owner directive)**: `free_mask` and `dirty_mask` are pane-slot management state -- they index into `pane_slots`. Moving `pane_slots` without them would leave orphaned indices in `core/`. Grouping all three in `SessionEntry` is cohesive. This was decided by owner directive.

**focused_pane stays in Session**: `focused_pane: ?PaneSlot` is a session-level UI concept (which pane has keyboard focus). It stores a slot index value (`?u8`), not a pane reference, so it creates no dependency on `server/`. Core operations like tree traversal and input routing use `focused_pane`.

**Prior art**: Both tmux and zellij separate pure session state from runtime pane resources. tmux's `struct session` contains `winlink` references (analogous to slot indices) while `struct window_pane` holds runtime resources (fd, pid, screen buffer). zellij's `SessionMetaData` wraps `Screen` as a server-level container. The `SessionEntry` pattern follows this established approach.

### 2.4 Wire Protocol Changes

**None.** `SessionEntry` is a server-internal type. The wire protocol continues to use `session_id: u32` and `pane_id: u32`.

---

## Resolution 3: SplitNode Remnants in v0.1 Resolution Doc (6/6 unanimous)

**Source**: Review note 01 (LOW)
**Affected docs**: `v0.1/design-resolutions/01-daemon-architecture.md`

### Decision

Fix 3 stale `SplitNode` references that were missed during the v0.2 V1-03 fix cycle. The v0.1 resolution doc is living normative text.

| # | Line | Current | Replacement |
|---|------|---------|-------------|
| 1 | 24 | `SplitNode (tree shape, leaf = PaneId)` | `SplitNodeData (tree shape, leaf = PaneSlot)` |
| 2 | 79 | `Each Session directly owns a SplitNode tree` | `Each Session directly owns a SplitNodeData tree` |
| 3 | 558 | `SplitNode references PaneId` | `SplitNodeData references PaneSlot` |

Line 558 was discovered by daemon-architect during v0.4 discussion (the original review note listed only lines 23 and 80; actual stale text is at lines 24 and 79).

### 3.1 Rationale

The v0.1 resolution doc is normative living text (confirmed by v0.2 V1-03 precedent). The v0.2 resolution renamed `SplitNode` to `SplitNodeData` and `PaneId` to `PaneSlot` for internal use, but these 3 narrative occurrences were missed.

### 3.2 Wire Protocol Changes

**None.** Documentation correction only.

---

## Resolution 4: pty_fd Naming Consistency (6/6 unanimous)

**Source**: Review note 02 (LOW)
**Affected docs**: `v0.4/03-lifecycle-and-connections.md`

### Decision

Replace `pty_master_fd` with `pty_fd` at 2 locations in Section 1.1 Step 6 pseudocode:

| # | Line | Current | Replacement |
|---|------|---------|-------------|
| 1 | 110 | `forkpty() -> (pty_master_fd, child_pid)` | `forkpty() -> (pty_fd, child_pid)` |
| 2 | 114 | `Register pty_master_fd with kqueue:` | `Register pty_fd with kqueue:` |

### 4.1 Rationale

All other daemon docs use `pty_fd` exclusively. The `Pane` struct declares `pty_fd: posix.fd_t`. `pty_master_fd` is technically precise (it is the master side of the PTY pair) but inconsistent with the project convention.

### 4.2 Wire Protocol Changes

**None.** Documentation correction only.

---

## Items Deferred to Future Versions

| Item | Severity | Deferred to | Rationale |
|------|----------|-------------|-----------|
| `ErrorResponse` semantic correction (doc 01 lines 169, 187, 396) | LOW | v0.4 writing phase | Requires per-occurrence analysis against protocol two-layer error model. Not a mechanical rename. |

---

## Prior Art References

| Reference | Used for | Resolution |
|-----------|----------|------------|
| Protocol doc 01 (v0.6) normative message type table | Authoritative source for message type names | R1 |
| Protocol doc 02 (v0.6) Section 11.1 Disconnect message | `Disconnect` with `reason` field | R1 |
| Protocol doc 03 (v0.6) Section 6 error model | Two-layer error model (typed responses vs Error 0x00FF) | R1 (deferred) |
| tmux `struct session` / `struct window_pane` | Session-resource separation pattern | R2 |
| zellij `SessionMetaData` / `Tab` | Pure state vs runtime container separation | R2 |
| v0.2 design resolutions (Resolution 1) | `SplitNode` -> `SplitNodeData`, `PaneId` -> `PaneSlot` rename | R3 |
