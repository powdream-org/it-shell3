# Post-v1 Features

This document collects features explicitly deferred beyond v1. These items are
**not to be discussed or designed** during the v0.x through v1 cycle. They are
recorded here solely to prevent information loss.

---

## 1. Image Protocol (Sixel / Kitty)

**Origin**: Doc 04 Open Question #2 (closed in v0.7, owner decision)

Sixel and Kitty image protocol support requires:

- Dedicated message type for image data (potentially megabytes per image)
- Out-of-band transfer mechanism (separate from FrameUpdate CellData stream)
- Image lifecycle management (placement, scrolling, resize interaction)

Image data is fundamentally different from text cell data and does not fit the
current CellData structure. A dedicated spec is needed.

**References**: ghostty has Kitty image protocol support; iTerm2 supports both
Sixel and its own inline image protocol.

## 2. Remain-on-Exit

**Origin**: Doc 03 Open Question #6 (closed in v0.7, owner decision)

v1 uses auto-close: when a pane's process exits, the server automatically closes
the pane and triggers layout reflow. v1 ignores ghostty's `wait-after-command`
option — the daemon always passes `wait_after_command = false` to libghostty.

Post-v1, add a `remain-on-exit` option (per-pane or per-session configuration)
that keeps the pane visible with exit status displayed until the user explicitly
closes it. tmux supports this via `set -g remain-on-exit on`. When implemented,
add a `pane_remains` boolean field to the `ProcessExited` (0x0801) payload to
signal whether the pane stays open.

**Implementation note**: When implementing remain-on-exit, ghostty's
`wait-after-command` option MUST be considered. libghostty already has the
plumbing — the embedder passes `wait_after_command = true` via `Surface.Options`
and the Surface stays open after process exit. However, ghostty's behavior (show
"Press any key to close" message, close on any keypress) may not match our
desired UX (pane stays until explicit `ClosePane`). The daemon may need to
handle the process exit callback independently rather than relying on ghostty's
built-in wait behavior. See
`draft/v1.0-r7/research/04-ghostty-wait-after-command.md` for the full ghostty
implementation details.

## 3. Candidate Window Protocol

**Origin**: Doc 05 Open Question #2 (closed in v0.7, owner decision)
**Updated**: 2026-03-07 (review note
`draft/v1.0-r7/review-notes/04-preedit-protocol-overhaul.md`)

Japanese and Chinese IMEs present a candidate list for character selection. This
requires:

- Candidate list data delivery to the client (potentially large for Chinese)
- Pagination support
- Candidate selection feedback (client → server)
- Candidate window positioning relative to preedit text

### v1 preedit model context

v1 preedit is cell data — the server injects preedit cells into I/P-frame cell
data at export time. The client does not know what is preedit. PreeditUpdate
(0x0401) carries only `pane_id`, `preedit_session_id`, and `text` for lifecycle
tracking.

### v2 additions needed

**Anchor position**: The client needs to know where to place the candidate
floating window. The server knows the cursor position in cell coordinates from
libghostty-vt terminal state. PreeditUpdate gains an optional `anchor` field:

```json
{
  "pane_id": 1,
  "preedit_session_id": 42,
  "text": "にほんご",
  "anchor": { "row": 10, "col": 5 },
  "candidates": {
    "items": ["日本語を", "二本後を"],
    "selected": 0,
    "page": 1,
    "total_pages": 3
  }
}
```

Cell-to-pixel conversion is the client's responsibility using
`ghostty_surface_size()` cell dimensions plus the surface's screen origin.

**Per-segment styling**: Japanese IME needs per-segment decoration (reverse for
converting clause, underline for unconverted). The current preedit injection
mechanism accepts only flat UTF-8 — no styling information. This would require
either a ghostty API extension or a separate overlay mechanism. Design deferred.

This schema is a starting point for post-v1 design, not a commitment.

## 4. Application-Level Heartbeat (echo_nonce)

**Origin**: v0.5 review note Issue 3 (Client Health Model), gap 1.5. v0.6
Resolution 11 deferred to v2.

v1 heartbeat (Heartbeat 0x0003 / HeartbeatAck 0x0004) only proves the TCP
connection is alive. It does not prove the client application is actually
processing messages — a frozen app whose OS TCP stack continues to ACK packets
passes heartbeat checks.

v1 mitigates this through ring cursor stagnation detection and the PausePane
escalation timeline (5s/60s/300s). Combined with `latest` as the default resize
policy, a frozen client's stale dimensions do not affect healthy clients. This
covers all practical scenarios where PTY output is flowing.

**Blind spot**: When the PTY is idle (no terminal output), there are no new ring
frames, so cursor stagnation cannot trigger. A frozen client in an idle session
is undetectable by v1 mechanisms. Under `latest` policy this is harmless (frozen
client's dimensions are irrelevant). Under `smallest` policy, the frozen
client's stale dimensions permanently constrain healthy clients.

### v2 design

Add `echo_nonce` as a `HEARTBEAT_NONCE` capability (negotiated at handshake):

```
Server -> Client: EchoNonce (0x0900) { "nonce": u64 }
Client -> Server: EchoNonceAck (0x0901) { "nonce": u64 }
```

The client **application layer** must read the nonce from its message queue and
echo it back. TCP-level ACK is insufficient — the nonce proves the app is alive
and processing. Failure to respond within a configured timeout triggers the same
health escalation as ring cursor stagnation.

**Message range**: 0x0900–0x09FF reserved for connection health extensions.

**References**: Doc 06 v0.7 Section 7 (heartbeat orthogonality note),
design-resolutions-resize-health.md Resolution 11.

## 5. Per-Client Focus Indicators

**Origin**: v0.5 review note `review-notes-01-per-client-focus-indicators.md`
Issue 1. Carried forward through v0.6 handover (Priority 4), v0.7 TODO (Phase
6c). Deferred to post-v1 by owner decision.

When multiple clients are attached to the same session, show which clients are
focused on which tabs and panes — spatial awareness for collaborative or
multi-device usage (e.g., macOS + iPad viewing the same session).

### What exists (v0.7)

`client_id`, `client_name`, `ClientAttached` (0x0183), `ClientDetached`
(0x0184), `ClientHealthChanged` (0x0185) provide multi-client awareness
infrastructure. But no per-client focus tracking.

### What is missing

- **Per-client focus tracking**: Server does not track which pane each client is
  viewing. v1 uses shared focus (all clients share one `active_pane_id` per
  session, tmux model).
- **`ClientFocusChanged` notification**: No message to broadcast when a client
  changes focused pane.
- **`ListAttachedClients` query**: No way to query attached clients and their
  focus state on demand.
- **Per-client cursor broadcasting**: No "fake cursors" mechanism.

### Design decisions needed

1. **Display-only focus vs independent input routing**: Display-only (each
   client tracks what they _look at_, input goes to shared `active_pane_id`) vs
   independent (each client's input goes to their own focused pane, zellij
   independent mode). Independent mode requires per-client PTY size negotiation.
2. **Message ID allocation**: 0x0185 is occupied by `ClientHealthChanged`. New
   IDs needed.
3. **Client-side rendering**: RenderState architecture means client renders
   focus indicators locally (tab bar markers, pane frame indicators, optional
   fake cursors).

### Zellij reference

Zellij supports mirrored (shared view) and independent (per-client focus) modes.
Color assignment via `client_id % 10`. Server computes per-client
`other_focused_clients` lists. Tab bar and pane frame rendering with graceful
text degradation. Full details in v0.5 source document Section 3.

**References**: `draft/v1.0-r5/review-notes-01-per-client-focus-indicators.md`
(full original analysis).

## 6. HyperlinkTable (CellData Hyperlink Encoding)

**Origin**: Doc 04 Open Question #4 (closed in v1.0-r12, Resolution 4)

v1 provides row-level hyperlink presence detection via `row_flags.hyperlink`
(bit 4). When set, the client's renderer knows the row contains hyperlinked
cells, enabling rendering optimization (e.g., skip overlay rendering when
`hyperlink=0`). The server populates this bit from ghostty's per-row
`Row.hyperlink: bool` flag at zero cost.

v1 does **not** provide per-cell hyperlink association or URI delivery.
Hyperlink click handling, URL opening, and hover detection with underline
rendering are not in scope for Phase 1-5.

### Design direction

The intended approach is a per-row HyperlinkTable side table, following the
existing GraphemeTable/UnderlineColorTable pattern. CellData remains 16 bytes —
no inline hyperlink ID in the cell.

**Per-row HyperlinkTable** (third side table, appended after
UnderlineColorTable):

```
HyperlinkTable:
  num_entries     u16 LE    Number of hyperlinked cells in this row
  Entry[num_entries]:
    col_index     u16 LE    Column index of the hyperlinked cell
    hyperlink_id  u16 LE    Per-frame hyperlink ID (references FrameUpdate hyperlink table)
```

When `row_flags.hyperlink=0`, HyperlinkTable has `num_entries=0` (2-byte zero
header only).

**Per-frame hyperlink URI table** (in the JSON metadata blob of FrameUpdate):

```json
{
  "hyperlinks": {
    "1": "https://example.com/foo",
    "2": "file:///home/user/doc.txt"
  }
}
```

Hyperlink IDs are frame-local (assigned per FrameUpdate, not globally
persistent). The server walks ghostty's `AutoOffsetHashMap(Cell -> Id)` per row
during frame serialization and assigns frame-local IDs.

### Backward compatibility

The side table chain is backward-compatible: new clients read the third table,
old clients ignore trailing data after UnderlineColorTable. Adding
HyperlinkTable does not change CellData (16 bytes), GraphemeTable, or
UnderlineColorTable formats.

### Why deferred

1. **No v1 consumer.** Hyperlink click handling, URL opening, and hover
   detection are post-Phase 5 features.
2. **CellData MUST stay 16 bytes.** The 16-byte FlatCell is power-of-2 aligned
   by design: O(1) random access via `buffer[col * 16]`, SIMD-friendly
   processing, deterministic sizing. ghostty itself uses an offset hash map
   rather than inline hyperlink IDs (`hyperlink.zig:20-23`).
3. **Unvalidated by PoC.** Every other CellData decision (16-byte FlatCell,
   GraphemeTable, UnderlineColorTable) was validated through PoC 06-08. The
   hyperlink export pipeline has not been validated.
4. **Zero-cost deferral.** The `row_flags` bit 4 is already reserved and
   functional. The side-table infrastructure is additive.

**References**: ghostty `hyperlink.zig:20-23` (offset hash map pattern),
`page.zig:1899,1995` (per-row/per-cell hyperlink flags), `Overlay.zig:149-199`
(rendering uses boolean flag only).
