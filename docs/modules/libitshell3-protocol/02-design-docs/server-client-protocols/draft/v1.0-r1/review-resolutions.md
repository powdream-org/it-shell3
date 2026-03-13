# Review Resolutions: Server-Client Protocol v0.1

**Date**: 2026-03-04
**Review notes**: [review-notes-01-protocol-overview.md](./review-notes-01-protocol-overview.md)
**Participants**: protocol-architect (docs 01, 02), systems-engineer (docs 03, 06), rendering-cjk-specialist (docs 04, 05)
**Status**: Consensus reached on all 6 issues + cross-document inconsistencies

---

## Issue 1: CJK Preedit Directions Wrong (Section 4.2 of Doc 01)

**Severity**: Design-level error
**Resolution**: ACCEPTED — flip all preedit messages from C->S to S->C

### Agreed Changes

The server owns the native IME engine (libitshell3-ime). The client sends raw HID
keycodes; the server processes them through the composition engine and pushes
preedit state to all attached clients.

**Corrected data flow:**

```
Client                          Server (libitshell3-ime)        Other Clients
  |                                   |                              |
  |--- KeyEvent (raw HID) ---------->|                              |
  |                                   | IME processes key            |
  |<-- PreeditStart (S->C) ----------|----> PreeditStart (S->C) --->|
  |<-- PreeditUpdate (S->C) ---------|----> PreeditUpdate (S->C) -->|
  |<-- FrameUpdate (preedit sect) ---|----> FrameUpdate ----------->|
  |                                   |                              |
  |<-- PreeditEnd (S->C) ------------|----> PreeditEnd (S->C) ----->|
```

**Doc 01 changes:**
- `PreeditStart` (0x0500 in doc 01): change direction from C->S to **S->C**
- `PreeditUpdate` (0x0501 in doc 01): change direction from C->S to **S->C**
- `PreeditEnd` (0x0502 in doc 01): change direction from C->S to **S->C**
- `PreeditSync` (0x0503): remains S->C (already correct)
- Update the description: "Server pushes composition state to client(s)" instead
  of "Client reports composition state to server"

**Doc 04 change — remove `composing` field from KeyEvent:**

In the corrected architecture, the client does not know whether composition is
active — the server determines this from the IME engine state. The `composing`
field (byte offset 18 in KeyEvent, doc 04 section 2.1) is a leftover from the
incorrect C->S model.

- Remove `composing` field (1 byte)
- Replace with `reserved` (1 byte, must be 0)
- KeyEvent payload remains 8 bytes, total message size remains 22 bytes

**Doc 05 is already correct** — PreeditStart/Update/End are listed as S->C in
section 11 (message type summary). No changes needed.

### PreeditSync vs PreeditUpdate — Keep Both

The team agreed to keep PreeditSync (0x0403 in doc 05) as a distinct message:

| Message | Purpose | When sent |
|---------|---------|-----------|
| PreeditUpdate | Delta: assumes client has PreeditStart context | Every composition state change, to ALL clients |
| PreeditSync | Full snapshot: self-contained | When a late-joining client attaches to a session with active composition |

Merging them would bloat every PreeditUpdate by ~6 bytes (preedit_owner,
active_layout_id) for fields only needed once per attachment.

### Dual-Channel Preedit Design — Keep Both Channels

The team agreed that preedit state is communicated through two channels:

| Channel | Purpose | Coalescing | Consumer |
|---------|---------|------------|----------|
| FrameUpdate preedit section (0x0300) | Rendering: where to draw the overlay | Coalesced at frame rate (~60fps) | GPU rendering pipeline |
| PreeditStart/Update/End (0x0400-0x0402) | State tracking: composition state, ownership, conflict resolution | Not coalesced — full event sequence preserved | Session manager, debugging, multi-client sync |

**Rule**: Clients MUST use FrameUpdate's preedit section for rendering. Dedicated
preedit messages are for metadata and state tracking only.

**Capability interaction**: The FrameUpdate preedit section is always included when
preedit is active, regardless of whether the client negotiated `CJK_CAP_PREEDIT`.
The preedit section is part of the visual render state, not a CJK capability.
`CJK_CAP_PREEDIT` controls only the dedicated PreeditStart/Update/End messages.

### IMEModeSwitch

Doc 05's `InputMethodSwitch` (0x0404, C->S) already covers this use case. The
client requests a layout/IME mode change; the server performs it. Additionally,
the server should detect mode-switch hotkeys (e.g., Right-Alt) from raw KeyEvent
and auto-switch internally. Both paths produce the same result.

No additional message types needed.

---

## Issue 2: Pane Management Missing Operations

**Severity**: Incomplete specification
**Resolution**: MOSTLY ALREADY ADDRESSED in doc 03 — add LayoutGet request only

### What Doc 03 Already Covers

The review notes were based on doc 01's overview table, which lacks detail. Doc 03
(systems-engineer) already specifies comprehensive pane operations:

| Review concern | Doc 03 coverage | Section |
|----------------|-----------------|---------|
| 2a. Split parameters (direction, reference, ratio, position) | `SplitPaneRequest` (0x0142) with direction, ratio, pane_id, focus_new | 3.3 |
| 2b. Divider adjustment | `ResizePaneRequest` (0x014A) with direction + delta (signed i16 cells) | 3.11 |
| 2c. Pane swap | `SwapPanesRequest` (0x0150) swaps two panes in the layout tree | 3.17 |
| 2c. Pane move (cross-tab) | Deferred to v2 (complex cross-tab reparenting) | N/A |
| 2c. Pane rotate | Deferred to v2 (syntactic sugar over multiple swaps) | N/A |
| 2d. Layout query | **Not covered** — see below | N/A |

### New Addition: LayoutGet Request/Response

Add `LayoutGetRequest` and `LayoutGetResponse` for explicit layout queries without
triggering a mutation. Use case: client wants to refresh layout state after missing
a notification, or a monitoring tool queries layout on demand.

| Type Code | Name | Direction | Description |
|-----------|------|-----------|-------------|
| `0x0152` | LayoutGetRequest | C -> S | Request current layout tree |
| `0x0153` | LayoutGetResponse | S -> C | Returns same payload as LayoutChanged |

**LayoutGetRequest payload:**

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | session_id | Session to query (u32) |

**LayoutGetResponse**: Same payload format as the existing `LayoutChanged`
notification (doc 03 section 5.1), returned with the RESPONSE flag set and
echoing the request's sequence number.

### Doc 01 Update

Update the pane management message table (section 4.2) to reference doc 03's
complete message set instead of the abbreviated list. Add LayoutGet to the table.

---

## Issue 3: Tab Concept Removal

**Severity**: Structural change
**Resolution**: ACCEPTED — remove Tab, absorb into Session

### Mapping (Confirmed by Reviewer)

| libitshell3 concept | Maps to | Analogy |
|---------------------|---------|---------|
| **Session** | ghostty tab | tmux session, zellij tab |
| **Pane** | ghostty split pane | tmux pane, zellij pane |

There is no "Tab" concept in libitshell3. Each Session has one layout tree (a
binary split tree of panes). Users wanting multiple workspaces create multiple
Sessions. The client's UI presents Sessions as tabs.

### Messages to Remove

All Tab messages from doc 03 (0x0120-0x0129):

| Removed | Reason |
|---------|--------|
| `CreateTabRequest/Response` (0x0120/0x0121) | Creating a session creates the initial pane |
| `CloseTabRequest/Response` (0x0122/0x0123) | Closing the last pane destroys the session |
| `RenameTabRequest/Response` (0x0124/0x0125) | Use RenameSession instead |
| `SwitchTabRequest/Response` (0x0126/0x0127) | No tabs to switch between |
| `ReorderTabRequest/Response` (0x0128/0x0129) | No tabs to reorder |
| `TabListChanged` (0x0183) | No tab list |

### Messages to Update

| Message | Change |
|---------|--------|
| All pane messages referencing `tab_id` | Remove `tab_id` field; panes belong directly to a Session |
| `LayoutChanged` (0x0180) | Remove `tab_id`; layout tree is per-session |
| `CreateSessionResponse` (0x0101) | Remove `tab_id` from response |
| `ListSessionsResponse` (0x0103) | Remove `tab_count` and `active_tab_id` fields |
| `AttachSessionResponse` (0x0105) | Remove `active_tab_id` |
| `EqualizeSplitsRequest` (0x014C) | Change from "equalize splits in a tab" to "equalize splits in a session" |
| `NavigatePaneRequest` (0x0148) | Remove `tab_id` field (navigate within the session's single layout tree) |

### Doc 01 Updates

- Remove `TabCreate` (0x0208), `TabCreated` (0x0209), `TabClose` (0x020A),
  `TabClosed` (0x020B), `TabFocus` (0x020C), `TabFocused` (0x020D) from the
  message type table (section 4.2)
- Rename range `0x0200-0x02FF` from "Tab & Pane Management" to
  "Pane Management"
- Remove `tab_id` from SessionDescriptor in ServerHello (doc 02 section 3.2):
  remove `tab_count` field
- Remove `tab_id` from SessionCreated response (doc 02 section 8.3)

### Doc 06 Updates

- Remove `TabListChanged` from the default subscription list (section 5)

### Docs 04, 05

Minimal impact — these docs already use `pane_id` and `session_id` without
`tab_id`.

---

## Issue 4: Sequence Number 0 Contradiction

**Severity**: Specification contradiction
**Resolution**: Notifications use normal monotonic sequence numbers. Seq 0 is
never sent on the wire.

### The Contradiction

Doc 01 section 3.4 states two contradictory rules:
1. "Sequence 0 is reserved for unsolicited notifications"
2. "Notifications use the sender's next sequence number"

### Agreed Resolution

**All messages use the sender's next monotonic sequence number.** No exceptions.

| Message type | Sequence number | RESPONSE flag |
|--------------|-----------------|---------------|
| Request | Sender's next seq | 0 |
| Response | Echo request's seq | 1 |
| Notification | Sender's next seq | 0 |
| Error response | Echo offending request's seq | 1 (RESPONSE + ERROR) |

**Sequence 0 is never sent on the wire.** The counter starts at 1 and wraps from
`0xFFFFFFFF` back to 1 (skipping 0).

Sequence 0 is used ONLY as a sentinel value in payload fields:
- `ref_sequence = 0` in Error message payload means "no specific message triggered
  this error" (unsolicited error)

**Rationale:**
1. Preserves full message ordering for debugging — every message on a connection
   has a unique, monotonically increasing sequence number
2. Notifications are already identifiable by message type (LayoutChanged,
   PaneMetadataChanged, etc. are distinct types never used as request/response)
3. One simple rule ("every message gets the next seq") instead of a special case

### Doc Updates

- Doc 01 section 3.4: Remove "Sequence 0 is reserved for unsolicited
  notifications." Replace with: "Sequence 0 is never sent on the wire. It is used
  only as a sentinel value in payload fields (e.g., ref_sequence in Error
  messages)."
- Doc 03 section 8: Change "Notifications use sequence number 0" to
  "Notifications use the server's next monotonic sequence number"

---

## Issue 5: Cursor Style During CJK Composition

**Severity**: Missing specification
**Resolution**: Server controls cursor style during composition. No new messages
needed.

### Agreed Behavior

When the server's IME engine enters composition (`preedit_active` transitions
from false to true):

1. Server saves the current `cursor_style` and `cursor_blinking` values
2. Server sets `cursor_style = 0` (block) in subsequent FrameUpdate Cursor
   sections
3. Server sets `cursor_blinking = 0` (steady) in subsequent FrameUpdate Cursor
   sections

When composition ends (`preedit_active` transitions from true to false):

1. Server restores the saved `cursor_style` (whatever the terminal application
   had set via DECSCUSR)
2. Server restores the saved `cursor_blinking`

### Why Server-Side

1. **Consistency across clients**: All clients render the same cursor style during
   composition. No per-client divergence.
2. **Server-authoritative principle**: The server already owns cursor state in
   FrameUpdate. Adding preedit-aware logic is minimal code in the server's
   FrameUpdate builder.
3. **No new messages**: The existing `cursor_style` field in FrameUpdate's Cursor
   section (doc 04 section 4.4) carries the information. The server simply changes
   the value it sends.

### Doc Updates

**Doc 04 (Section 4.4 Cursor Section)** — add note:

> When `preedit_active=true` (Section 4.5), the server overrides `cursor_style`
> to block (0) and `cursor_blinking` to steady (0) for the duration of
> composition. The pre-composition cursor style is restored when composition ends.

**Doc 05 (Section 9.1 Client Rendering)** — add note:

> Cursor style changes during composition are handled server-side. Clients render
> the cursor as specified in FrameUpdate's cursor section without any
> preedit-specific overrides.

---

## Issue 6: Multi-Client Window Size Negotiation

**Severity**: Design contradiction
**Resolution**: ACCEPTED — use minimum (cols, rows) across all attached clients
for v1

### The Contradiction

| Document | Strategy |
|----------|----------|
| Doc 02 (line 489) | Minimum (cols, rows) across all attached clients |
| Doc 03 (line 765) | Most recently attached client's dimensions |

### Agreed Strategy: Minimum (cols, rows)

**For v1, the effective terminal size is `min(cols)` x `min(rows)` across all
attached clients.** This matches tmux's proven approach (15+ years of production
use).

**Rationale:**

1. The PTY has exactly ONE terminal size (`TIOCSWINSZ`). Per-client virtual
   viewports require complex per-client dirty tracking and are deferred to v2.
2. No client sees clipped content — all clients see the complete terminal output.
3. The larger client sees padding (unused space), which is cosmetically
   acceptable.
4. Simple to implement — one canonical size, one `TIOCSWINSZ` call per PTY.

### Resize Algorithm

When any client sends `WindowResize`:

```
1. Update the sending client's recorded dimensions.
2. Recompute effective_cols = min(client.cols for all attached clients).
3. Recompute effective_rows = min(client.rows for all attached clients).
4. If (effective_cols, effective_rows) changed:
   a. Walk the layout tree, recompute pane dimensions based on split ratios.
   b. For each pane with changed dimensions:
      ioctl(pane.pty_fd, TIOCSWINSZ, &new_size)
   c. Send LayoutChanged to ALL attached clients.
   d. Send FrameUpdate for each pane whose content changed.
5. If unchanged: send WindowResizeAck to the sending client only.
```

When a client **detaches**:

```
1. Remove the client's dimensions from the tracking set.
2. Recompute effective size (may increase if the detaching client had
   the smallest dimensions).
3. If size changed: resize cascade (same as above).
```

### Doc Updates

- Doc 02 section 8.5: Keep existing "minimum (cols, rows)" wording. Add the
  resize algorithm above.
- Doc 03 section 9: Change "most recently attached" to "minimum (cols, rows)
  across all attached clients." Add detach-resize behavior. Add note: "Per-client
  viewports are deferred to v2."

---

## Cross-Document Inconsistencies Discovered During Review

In addition to the 6 reviewer issues, the team identified structural
inconsistencies across the protocol documents that must be resolved.

### A. Header Size: 16 Bytes (Canonical)

**Problem**: Doc 01 defines a 16-byte header. Docs 03, 04, 05, 06 reference a
14-byte header.

**Resolution**: The canonical header is **16 bytes** as defined in doc 01.

```
Offset  Size  Field        Description
------  ----  -----        -----------
 0      2     magic        0x49 0x54 ("IT")
 2      1     version      Protocol version (1)
 3      1     flags        Frame flags
 4      2     msg_type     Message type ID (u16 LE)
 6      2     reserved     Must be 0
 8      4     payload_len  Payload length in bytes (u32 LE)
12      4     sequence     Sequence number (u32 LE)
```

**Key semantics:**
- `payload_len` is the payload size only (NOT including the 16-byte header)
- Total message size on wire = 16 + payload_len
- The 2-byte reserved field provides natural 4-byte alignment for `payload_len`
  and `sequence`, and room for future routing/flag fields

**Doc updates**: Docs 03, 04, 05, 06 must update all references from "14-byte
header" to "16-byte header" and from "length = total message length" to
"payload_len = payload length only."

### B. ID Types: u32 (Canonical)

**Problem**: Doc 01 specifies u32 for session/tab/pane IDs. Doc 03 uses 16-byte
UUIDs. Doc 04 uses u32.

**Resolution**: Use **u32** for all IDs on the wire.

| ID type | Wire size | Assignment |
|---------|-----------|------------|
| session_id | u32 (4 bytes) | Server-assigned, monotonically increasing |
| pane_id | u32 (4 bytes) | Server-assigned, monotonically increasing |

**Rationale:**
- 12 bytes smaller per ID reference vs UUID
- FrameUpdate sends pane_id on every frame at 60fps — 4 bytes vs 16 bytes matters
- u32 provides 4 billion IDs, never reused during a daemon's lifetime — sufficient
- UUIDs can be used in persistence snapshots (JSON) for cross-restart identity,
  mapped to u32 wire IDs on session attach

**Doc update**: Doc 03 must change all UUID references to u32. Doc 06 must update
UUID references in persistence messages.

### C. Message Type Range Allocation (Unified)

**Problem**: Doc 01's range allocation conflicts with docs 03-06.

**Resolution**: Adopt the allocation used by docs 03-06, which is more logically
organized. Update doc 01 to match.

| Range | Category | Document |
|-------|----------|----------|
| `0x0001 - 0x00FF` | Handshake & Lifecycle | Doc 02 |
| `0x0100 - 0x01FF` | Session & Pane Management | Doc 03 |
| `0x0200 - 0x02FF` | Input Forwarding | Doc 04 |
| `0x0300 - 0x03FF` | Render State (FrameUpdate, scrollback, search) | Doc 04 |
| `0x0400 - 0x04FF` | CJK & IME | Doc 05 |
| `0x0500 - 0x05FF` | Flow Control & Backpressure | Doc 06 |
| `0x0600 - 0x06FF` | Clipboard | Doc 06 |
| `0x0700 - 0x07FF` | Persistence (snapshot/restore) | Doc 06 |
| `0x0800 - 0x08FF` | Notifications & Subscriptions | Doc 06 |
| `0x0900 - 0x09FF` | Heartbeat & Connection Health | Doc 06 |
| `0x0A00 - 0x0AFF` | Extension Negotiation | Doc 06 |
| `0x0B00 - 0x0FFF` | Reserved for future use | -- |
| `0xF000 - 0xFFFE` | Vendor/custom extensions | -- |
| `0xFFFF` | Reserved (never used) | -- |

**Doc 01 update**: Replace section 4.1 (Allocation Ranges) and section 4.2 (Core
Message Types) with the unified allocation above. Remove the `Tab*` messages.
Reference docs 03-06 for detailed message specifications per range.

---

## Summary of All Resolutions

| # | Issue | Resolution | Docs Affected |
|---|-------|------------|---------------|
| 1 | CJK preedit directions | Flip to S->C; remove `composing` from KeyEvent; keep PreeditSync + dual-channel | 01, 04 |
| 2 | Pane management gaps | Mostly covered in doc 03; add LayoutGet request/response | 01, 03 |
| 3 | Tab concept removal | Remove Tab, absorb into Session; Session has one layout tree | 01, 02, 03, 06 |
| 4 | Sequence number 0 | All messages use normal seq numbers; seq 0 never sent on wire | 01, 03 |
| 5 | Cursor style during composition | Server sets block+steady during preedit; no new messages | 04, 05 |
| 6 | Multi-client window size | Minimum (cols, rows) across all attached clients | 02, 03 |
| A | Header size inconsistency | 16 bytes canonical (doc 01 definition) | 03, 04, 05, 06 |
| B | ID type inconsistency | u32 canonical; UUIDs only in persistence snapshots | 03, 06 |
| C | Message type range conflicts | Adopt docs 03-06 allocation; update doc 01 | 01 |

---

## Next Steps

1. Each document owner applies the agreed changes to their docs
2. protocol-architect updates docs 01, 02 (framing, handshake, range allocation,
   Tab removal, seq number fix)
3. systems-engineer updates docs 03, 06 (Tab removal, u32 IDs, header size,
   seq numbers, window resize strategy)
4. rendering-cjk-specialist updates docs 04, 05 (header size, remove `composing`,
   cursor style notes)
5. Cross-review after updates to verify consistency
