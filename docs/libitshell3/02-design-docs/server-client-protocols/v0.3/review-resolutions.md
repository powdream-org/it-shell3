# Review Resolutions: Server-Client Protocol v0.3

**Date**: 2026-03-04
**Review notes**: [review-notes-01-protocol-overview.md](./review-notes-01-protocol-overview.md)
**Participants**: protocol-architect (docs 01, 02), systems-engineer (docs 03, 06), cjk-specialist (docs 04, 05)
**Supporting research**: tmux-researcher, zellij-researcher
**Status**: Consensus reached on all 9 issues + 2 carry-overs from v0.1/v0.2

---

## Issue 1: Flags Byte Bit Numbering Convention

**Severity**: Minor (clarification)
**Resolution**: ACCEPTED — add LSB-first statement and concrete example

### Problem

The spec table says "Bit 0 = ENCODING, Bit 1 = COMPRESSED" but does not state
whether "bit 0" means LSB or MSB. In RFC convention, "bit 0" typically means MSB —
the opposite of the Zig packed struct semantics used in the spec's reference code.
Non-Zig implementers (Swift, C) cannot determine bit ordering from the spec alone.

### Agreed Changes

**Doc 01 Section 3.2 (Frame Flags)** — add after the flags table:

> Bit numbering is LSB-first: bit 0 is the least significant bit (0x01),
> bit 7 is the most significant bit (0x80).
>
> Example: ENCODING=1 only → flags byte = `0x01`.
> ENCODING=1 + COMPRESSED=1 → flags byte = `0x03`.

| Docs Affected | Changes |
|---|---|
| 01 | Section 3.2: add bit numbering convention + example |

---

## Issue 2: Heartbeat Timestamp — Simplify to Liveness-Only

**Severity**: Medium
**Resolution**: ACCEPTED — drop `timestamp` and `responder_timestamp`, simplify to `ping_id`-only liveness

### Problem

The reviewer identified four sub-issues:
- **2a**: Timestamps not explicitly stated as UTC
- **2b**: Clock skew estimation formula undocumented
- **2c**: RTT and clock skew have no documented consumer — no protocol subsystem
  reads or acts on these values
- **2d**: Two-way exchange cannot accurately measure clock skew over the internet
  (asymmetric delays)

Additionally, with SSH tunneling (Issue 4), heartbeat RTT only measures the local
Unix socket hop to sshd (~0ms), not the true end-to-end latency to the remote
client. The measured value would be wrong even if a consumer existed.

### Reference Codebase Evidence

| Codebase | Heartbeat | RTT Measurement | Clock Sync |
|---|---|---|---|
| **tmux** | None | None | None |
| **zellij** | None | None | None |

Neither reference codebase implements heartbeat, RTT measurement, or clock
synchronization. Both are local-only IPC. tmux has operated successfully for 15+
years without any client-server timing.

### Agreed Changes

**Simplify Heartbeat to liveness-only for v1.** The adaptive coalescing model
(Section 10) uses PTY throughput (KB/s) and keystroke timing to select tiers — it
never references heartbeat RTT. This disconnection is correct by design:
coalescing tiers are about server-side output rate, not network conditions. Client
self-reports transport latency via `ClientDisplayInfo` (see Issue 4).

**Heartbeat payload (0x0003):**

```json
{
  "ping_id": 42
}
```

**HeartbeatAck payload (0x0004):**

```json
{
  "ping_id": 42
}
```

| Field | Type | Description |
|---|---|---|
| `ping_id` | u32 | Monotonic ping counter for correlation |

Single field. The `timestamp` and `responder_timestamp` fields are both removed —
no protocol-level consumer exists for either. Liveness detection requires only
`ping_id`: did the ack arrive within the 90-second timeout?

**Local RTT diagnostics** (implementation-level, not wire protocol): The sender
MAY maintain a local `HashMap(u32, u64)` mapping `ping_id → send_time` for
debugging purposes. `RTT = current_time - sent_times[ack.ping_id]`. This is an
implementation choice, not a wire protocol concern.

| Docs Affected | Changes |
|---|---|
| 01 | Section 5.4: remove `timestamp` and `responder_timestamp` from Heartbeat/HeartbeatAck. Payload is `ping_id` only. Remove RTT formula from wire spec (local implementation detail). |
| 06 | Update heartbeat policy to match simplified format |

### Design Decision

Server-measured RTT via heartbeat was considered and rejected. With SSH tunneling
(Issue 4), heartbeat RTT only measures the local Unix socket hop to sshd (~0ms),
not true end-to-end latency. The client is the only entity that knows the true
transport latency and self-reports it via `ClientDisplayInfo.estimated_rtt_ms`.
Neither tmux nor zellij measures RTT. If accurate clock synchronization is needed
in the future, it requires an NTP-style 4-timestamp exchange — not heartbeat
timestamps.

---

## Issue 3: JSON Optional Field Convention

**Severity**: Medium
**Resolution**: ACCEPTED — Option A: omit field when absent, never send null

### Problem

The spec allows two representations for "absent": field missing or field present
with `null`. This creates ambiguity for parsers, serializers, and equality
comparison. Swift's `Codable` and Zig's `std.json` handle these differently.

### Agreed Changes

**Doc 01 Section 7 (Endianness and Encoding Conventions)** — replace the existing
"Optional fields" row with:

> **Optional fields**: When a JSON field has no value, the field MUST be omitted
> from the JSON object. Senders MUST NOT include fields with `null` values.
> Receivers MUST tolerate both missing keys and `null` values as "absent"
> (defensive parsing for forward/backward compatibility).

**Rationale:**
- Smaller payloads (relevant at preedit frequency ~15 msgs/s)
- Swift's default `Codable` behavior encodes `nil` as key-absent
- Zig's `std.json` handles missing keys with `@"field" = null` defaults
- More common in modern JSON APIs
- Unambiguous: one canonical representation for "absent"

| Docs Affected | Changes |
|---|---|
| 01 | Section 7: replace optional field convention |
| All docs | Apply convention to all JSON message examples |

---

## Issue 4: Replace Custom TCP+TLS with SSH Tunneling

**Severity**: High (architectural change)
**Resolution**: ACCEPTED — replace TCP+TLS with SSH tunneling via libssh2

### Problem

Section 2.2 specifies a custom TCP/TLS 1.3 transport requiring: mTLS cert
management, SRP-based password auth, custom port 7822, and a second transport
implementation. This is high implementation cost with significant security audit
risk.

### Reference Codebase Evidence

| Codebase | Transport | Network Awareness |
|---|---|---|
| **tmux** | Unix socket only | None — SSH handled externally |
| **zellij** | Unix socket + WebSocket | None — no RTT, no adaptation |

Both tmux and zellij are local-only Unix socket IPC. SSH access is handled
entirely outside the protocol. The client connects locally after SSH'ing into the
machine. Neither has any awareness of network transport.

### Agreed Changes

**Architecture:**

```
Local client:   App → Unix socket → daemon
Remote client:  App → SSH tunnel (libssh2) → sshd → Unix socket → daemon
```

The daemon only ever sees Unix socket connections. The protocol is truly
transport-agnostic with a single transport implementation.

**Security trust model:** When a client connects through an SSH tunnel,
`getpeereid()` returns sshd's UID. The daemon accepts this because SSH has
already authenticated the user at the transport layer. The trust chain is:
SSH authentication → sshd process → Unix socket → daemon. The daemon trusts
sshd's UID as a proxy for the authenticated remote user's identity.

**Client type enum:** Remove `"remote"`. With SSH tunneling, all clients connect
via Unix socket. Types: `"native"`, `"control"`, `"headless"`. The transport
distinction moves to `ClientDisplayInfo.transport_type`.

**ClientDisplayInfo (0x0505) — add transport hint fields:**

```json
{
  "display_refresh_hz": 60,
  "power_state": "ac",
  "preferred_max_fps": 0,
  "transport_type": "local",
  "estimated_rtt_ms": 0,
  "bandwidth_hint": "local"
}
```

| Field | Type | Values | Description |
|---|---|---|---|
| `transport_type` | string | `"local"`, `"ssh_tunnel"`, `"unknown"` | How the client connects |
| `estimated_rtt_ms` | u16 | 0 = unknown/local | Client's measured/estimated RTT |
| `bandwidth_hint` | string | `"local"`, `"lan"`, `"wan"`, `"cellular"` | Network bandwidth class |

**Coalescing adaptation for remote clients:**

| Tier | Local | SSH Tunnel (WAN) |
|---|---|---|
| Preedit | Immediate (0ms) | Immediate (0ms) — never throttled |
| Interactive | Immediate (0ms) | Immediate (0ms) |
| Active | 16ms (60fps) | 33ms (30fps) |
| Bulk | 33ms (30fps) | 66ms (15fps) |

Server determines these from `ClientDisplayInfo.transport_type` and
`bandwidth_hint`.

**Preedit latency target scoping:**

> Preedit FrameUpdates MUST be flushed immediately with no server-side coalescing
> delay. Over Unix domain socket, the server MUST deliver the FrameUpdate to the
> transport layer within 33ms of receiving the triggering KeyEvent. Over SSH tunnel
> or other network transport, the server adds no additional delay; end-to-end
> latency is dominated by network RTT.
>
> For remote clients over SSH with 50-100ms RTT, user-perceived preedit latency
> will be approximately equal to the round-trip time. Client-side composition
> prediction is a potential mitigation deferred to a future version.

| Docs Affected | Changes |
|---|---|
| 01 | Section 2.2: replace TCP+TLS with SSH tunneling reference. Section 10.3: scope preedit latency target. Section 12.2: replace mTLS/SRP with SSH auth trust model. |
| 02 | Section 2.2: remove `"remote"` client type. Section 7: add transport fields to ClientDisplayInfo. |
| 06 | Update ClientDisplayInfo wire spec with transport fields. Add WAN coalescing tier adjustment guidance. Note heartbeat RTT only measures local hop. |

---

## Issue 5: Remove Application-Layer Compression for v1

**Severity**: Medium
**Resolution**: ACCEPTED — remove zstd compression from v1, reserve for v2

### Problem

The reviewer identified: (1) Unix socket has >1 GB/s throughput — compression adds
latency for negligible savings. (2) SSH tunneling provides built-in compression
(`Compression yes`) — app-layer zstd on top is double-compression. (3) Preedit
tier's 0ms latency target makes any compression overhead unacceptable.

### Reference Codebase Evidence

| Codebase | Application-Layer Compression | Transport Compression |
|---|---|---|
| **tmux** | None — zero compression libraries | SSH (external) |
| **zellij** | None — raw protobuf, no compression | None |

Neither tmux nor zellij compresses at the application protocol layer. tmux relies
entirely on SSH for remote compression. This is the approach the reviewer
recommended and the team unanimously supports.

### Agreed Changes

**Remove application-layer zstd compression from v1.** Reserve the COMPRESSED
flag bit and `"compression"` capability name for future use.

**Doc 01 Section 3.5 (Compression)** — replace with:

> The COMPRESSED flag (bit 1) is reserved for future use. In protocol version 1,
> compression is not implemented. Senders MUST NOT set the COMPRESSED flag.
> Receivers that encounter COMPRESSED=1 SHOULD send `ERR_DECOMPRESSION_FAILED`.

**Doc 01 Section 4 (Capability flags)** — update `"compression"`:

> Reserved for future use in v1. When present in negotiated capabilities, has no
> effect on v1 wire format.

| Docs Affected | Changes |
|---|---|
| 01 | Section 3.5: replace compression spec with reserved note. Section 4: mark `"compression"` as reserved. Section 11.3: change zstd from "Proposed" to "Deferred to v2." |
| 06 | Remove compression interaction from flow control logic |

### Design Decision

Application-layer compression deferred to v2. SSH compression covers WAN
scenarios. Neither tmux nor zellij compresses at the application protocol layer.
COMPRESSED flag bit and `"compression"` capability name reserved for v2. If
benchmarking shows benefit beyond SSH compression, add app-layer compression with
explicit exclusion of Preedit and Interactive tier messages.

---

## Issue 6: Input Language Negotiation — Two-Axis Model

**Severity**: High (fundamental gap)
**Resolution**: ACCEPTED — separate input method from keyboard layout, add
handshake negotiation, use string identifiers throughout

### Problem

The spec conflates two orthogonal concepts under a single `layout_id`:
- **Keyboard layout** (physical key mapping): QWERTY, Dvorak, JIS kana
- **Input method / IME mode** (composition engine): direct, Korean 2-set,
  Japanese romaji

The handshake claims "Layout IDs are negotiated during handshake" (doc 04 line
131) but doc 02 defines no such mechanism — `ServerHello` has no
`supported_input_methods` field, `ClientHello` has no `preferred_input_methods`
field. The claim is an empty promise.

Additionally:
- Default input method for new panes is undefined
- Newly-attached clients don't receive per-pane input method state (only panes
  with active preedit via PreeditSync)

### Agreed Changes

**Two-axis protocol model with string identifiers:**

1. **Two distinct axes:**
   - `input_method` (string): `"direct"`, `"korean_2set"`, `"korean_3set_390"`,
     `"korean_3set_final"`, future: `"japanese_romaji"`, `"chinese_pinyin"`
   - `keyboard_layout` (string): `"qwerty"`, `"dvorak"`, `"colemak"`,
     `"jis_kana"` (v1: only `"qwerty"`)

2. **String identifiers everywhere** — including KeyEvent. Since all input
   messages are JSON-encoded (per the v0.3 hybrid encoding decision), there is no
   wire efficiency benefit to numeric IDs. A string adds ~13 bytes per KeyEvent,
   which is irrelevant at typing speeds (~15/s) over a >1 GB/s Unix socket.
   Benefits: self-documenting on the wire, no mapping table, no reserved numeric
   ranges, adding new languages is just a new string value with zero schema
   migration.

3. **No numeric layout_id table.** The numeric ID ranges (0x0100-0x01FF for
   Japanese, 0x0200-0x02FF for Chinese) are no longer needed. New input methods
   are just new string values.

**ServerHello addition:**

```json
{
  "supported_input_methods": [
    {"method": "direct", "layouts": ["qwerty"]},
    {"method": "korean_2set", "layouts": ["qwerty"]}
  ]
}
```

**ClientHello addition:**

```json
{
  "preferred_input_methods": [
    {"method": "direct"},
    {"method": "korean_2set"}
  ]
}
```

Objects with optional `layout` field (omitted = `"qwerty"` default, per Issue 3
convention). When Japanese JIS kana arrives:
`{"method": "japanese_kana", "layout": "jis"}`.

**KeyEvent (0x0200):**

```json
{
  "keycode": 11,
  "action": 0,
  "modifiers": 0,
  "input_method": "korean_2set"
}
```

Replaces the numeric `active_layout_id: u16` with string `input_method`.
The `keyboard_layout` field is omitted in KeyEvent (established at handshake,
always `"qwerty"` in v1).

**InputMethodSwitch (0x0404) / InputMethodAck (0x0405):**

Use string `input_method` + `keyboard_layout` in JSON payload. Replaces
numeric `layout_id`.

**AttachSessionResponse — add per-pane input method state:**

```json
{
  "pane_input_methods": [
    {"pane_id": 1, "active_input_method": "direct", "active_keyboard_layout": "qwerty"},
    {"pane_id": 3, "active_input_method": "korean_2set", "active_keyboard_layout": "qwerty"}
  ]
}
```

This provides newly-attached clients with input method state for ALL panes, not
just panes with active preedit (which PreeditSync already covers).

**Default for new panes:** `input_method: "direct"`, `keyboard_layout: "qwerty"`.
Normative.

**LayoutChanged leaf nodes — add input method state:**

```json
{
  "type": "leaf",
  "pane_id": 1,
  "cols": 40,
  "rows": 24,
  "active_input_method": "direct",
  "active_keyboard_layout": "qwerty"
}
```

**Two-channel input method state (no LayoutChanged trigger for IME changes):**

Input method state uses the same two-channel pattern as `preedit_active`:
- **LayoutChanged** (0x0180): Full layout tree with per-pane
  `active_input_method` + `active_keyboard_layout` in leaf nodes. Fires on
  structural changes (split, close, resize, zoom, swap) and on attach. Provides
  authoritative initial/refresh state.
- **InputMethodAck** (0x0405, already exists): Broadcast to ALL attached clients
  on input method changes. Carries `pane_id` + new method. Provides incremental
  updates.

Client state maintenance:
1. Initialize per-pane input method from `LayoutChanged` leaf nodes on attach
2. Update incrementally from `InputMethodAck` broadcasts
3. Refresh from `LayoutChanged` on structural changes

This avoids unnecessary LayoutChanged broadcasts for input-method-only changes
and is consistent with how `preedit_active` already works.

| Docs Affected | Changes |
|---|---|
| 02 | ServerHello: add `supported_input_methods`. ClientHello: add `preferred_input_methods`. AttachSessionResponse: add `pane_input_methods`. |
| 03 | LayoutChanged leaf nodes: add `active_input_method` + `active_keyboard_layout`. InputMethodAck broadcast to all clients on IME switch. Default input method for new panes. Input method state preserved across detach/reattach. |
| 04 | Rename `active_layout_id` → `input_method` (string) in KeyEvent. Restructure layout ID table into string-based model. |
| 05 | Rename `active_layout_id` → `active_input_method` in PreeditSync, InputMethodAck. Update InputMethodSwitch to string-based model. |

---

## Issue 7: Daemon Lifecycle and Empty Session Handling

**Severity**: Medium
**Resolution**: ACCEPTED — define auto-start, auto-create, and AttachOrCreate

### Problem

The protocol does not specify behavior when: (7a) the daemon is not running when
the client starts, or (7b) the daemon is running but no sessions exist.

### Agreed Changes

**7a — Daemon auto-start:**

> If the client cannot connect to the daemon socket (ECONNREFUSED or ENOENT), the
> client MAY auto-start the daemon process. Auto-start behavior is
> implementation-defined (e.g., launchd socket activation on macOS, fork/exec on
> Linux). If a stale socket file exists (ECONNREFUSED), the client SHOULD unlink
> it before attempting auto-start.

- **macOS primary**: launchd socket activation (`com.itshell3.daemon.plist` with
  `KeepAlive`). Daemon starts automatically on socket connection.
- **Fallback**: Client fork/exec of daemon binary (like tmux). Check socket →
  if absent, fork `itshell3d` → wait up to 5s → retry.
- **iOS**: Daemon embedded in app process (no separate daemon).

**Reconnection after daemon crash:** Exponential backoff with jitter: 100ms,
200ms, 400ms, ..., max 10s. After 5 failed attempts, report to user. Client
distinguishes clean exit (socket removed) vs crash (stale socket present).

**7b — Empty sessions and AttachOrCreate:**

When `ServerHello.sessions` is empty AND the client is `"native"` type, the
client SHOULD auto-create a default session with standard parameters (shell:
`$SHELL` or `/bin/sh`, cwd: `$HOME`, cols/rows from ClientHello).

**New message: AttachOrCreateRequest (0x010C) / AttachOrCreateResponse (0x010D):**

AttachOrCreateRequest payload:

```json
{
  "session_name": "main",
  "cols": 80,
  "rows": 24,
  "shell": "",
  "cwd": ""
}
```

Semantics: If a session with the given name exists → attach. If not → create.
Empty `session_name` → attach to most recently active, or create new. Equivalent
to tmux's `new-session -A`.

AttachOrCreateResponse payload:

```json
{
  "action_taken": "attached",
  "session_id": 1,
  "pane_id": 1,
  "session_name": "main",
  "active_pane_id": 1
}
```

| Field | Type | Description |
|---|---|---|
| `action_taken` | string | `"attached"` or `"created"` |
| `session_id` | u32 | Session ID |
| `pane_id` | u32 | Initial pane ID (only meaningful if created) |
| `session_name` | string | Actual session name |
| `active_pane_id` | u32 | Currently focused pane |

**State machine update:** Doc 01 Section 5.3 adds AttachOrCreateRequest as a
valid transition from READY → OPERATING alongside AttachSessionRequest and
CreateSessionRequest.

**Placement:** AttachOrCreateRequest is defined in doc 03 (session management
range 0x01xx). Doc 01's state machine references it.

| Docs Affected | Changes |
|---|---|
| 01 | Section 2.1: add daemon auto-start note. Section 5.3: add AttachOrCreate to state transitions. |
| 03 | Add AttachOrCreateRequest (0x010C) / AttachOrCreateResponse (0x010D). Define auto-create semantics and default session parameters. |

---

## Issue 8: Error Message Type → 0x00FF

**Severity**: Minor (message type allocation)
**Resolution**: ACCEPTED — move Error from 0x0006 to 0x00FF

### Problem

Error is a catch-all message placed at 0x0006, wasting the 0x0007-0x00FE range.
Future lifecycle messages (AttachOrCreate, daemon status, reconnection) would need
non-contiguous allocation.

### Agreed Changes

Move Error to 0x00FF — the last slot in the Handshake & Lifecycle range:

| Type | Message |
|---|---|
| `0x0001` | ClientHello |
| `0x0002` | ServerHello |
| `0x0003` | Heartbeat |
| `0x0004` | HeartbeatAck |
| `0x0005` | Disconnect |
| `0x0006`-`0x00FE` | Reserved (future lifecycle: AttachOrCreate etc.) |
| `0x00FF` | Error |

| Docs Affected | Changes |
|---|---|
| 01 | Section 4.2.1: move Error from 0x0006 to 0x00FF. Update all references. |

---

## Issue 9: Multi-Client Per-Session Support Gaps

**Severity**: High (12 gaps — 3 HIGH, 5 MEDIUM, 2 LOW, 2 clarifications)
**Resolution**: ACCEPTED — all 12 gaps resolved with 3/3 unanimous consensus
**Source**: Team-initiated review (owner flagged concern that multi-client support
may be incomplete across the protocol)

### Background

The v0.3 spec supports multiple clients attached to the same session, but the
multi-client design was only partially specified. A systematic review by all three
core members identified 12 gaps. Several were found independently by 2-3 members
(strong convergence).

### Well-Designed Areas (no changes needed)

These multi-client aspects are already properly specified:

| Area | Location | Assessment |
|------|----------|------------|
| Terminal resize algorithm | Doc 02 S9.6, Doc 03 S5.1 | min(cols,rows), detach recomputation |
| Per-(client,pane) coalescing | Doc 06 S1.4 | Independent timers, dirty bitmaps, tier state per client |
| Per-client flow control | Doc 06 S2 | PausePane/ContinuePane per-client per-pane, output queues |
| Preedit conflict resolution | Doc 05 S6 | preedit_owner per pane, last-writer-wins, takeover notification |
| PreeditSync for late-joining clients | Doc 05 S2.4 | Full state snapshot on attach |
| Dual-channel preedit | Doc 05 S1, S14 | Rendering vs state tracking separation |
| Heartbeat per-connection | Doc 01 S5.4 | Per-socket by nature |
| ClientDisplayInfo per-client | Doc 06 S1.5 | Each connection sends its own |

---

### Gap 1: No `client_id` Assignment in Wire Protocol

**Severity**: HIGH (unanimous — all 3 members)

**Problem**: The spec uses `client_id` in PreeditStart, PreeditSync, and the
preedit ownership model (doc 05), but never defines how `client_id` is assigned
or communicated. ClientHello sends no `client_id`. ServerHello returns no
`client_id`. Clients don't know their own ID.

**Impact**: Clients cannot determine if they are the preedit owner. Observer
clients see opaque IDs they were never told about. The "Client A composing"
indicator (doc 05 S10.2) cannot work.

**Resolution**: Add `"client_id": <u32>` to ServerHello response. Server assigns
monotonically increasing IDs per daemon lifetime. Client stores its own ID for
comparison with `preedit_owner`.

| Docs Affected | Changes |
|---|---|
| 02 | Add `client_id` to ServerHello response schema |

---

### Gap 2: KeyEvent (0x0200) Missing `pane_id`

**Severity**: HIGH (unanimous — all 3 members)

**Problem**: KeyEvent is the ONLY input message without a `pane_id` field.
TextInput, MouseButton, MouseScroll, PasteData, and FocusEvent all have
`pane_id`. Input routing is implicit (to session's focused pane) but never
stated.

**Impact**: With per-session focus, Client A composing Korean on pane 1 can have
composition silently broken if Client B changes focus to pane 2. Client A's next
KeyEvent goes to pane 2 mid-composition. Also an inconsistency — a client can
paste into a specific pane but can't type into one.

**Resolution**: Add optional `pane_id` to KeyEvent. Omitted = route to session's
focused pane. When present, server validates pane exists in client's attached
session. For IME composition, client SHOULD specify `pane_id` to prevent
focus-change races. Also enables future per-client focus (v2) without protocol
change.

**Design debate**: 2-1 split initially (systems-engineer argued against adding
complexity to the highest-frequency input message). Resolved to 3/3 after
recognizing that two explicit routing models already exist (TextInput/PasteData
have `pane_id`; making KeyEvent the exception is an unjustifiable inconsistency).

| Docs Affected | Changes |
|---|---|
| 04 | Add optional `pane_id` to KeyEvent schema |

---

### Gap 3: Focus Change During Active Preedit — Missing Race Condition

**Severity**: HIGH (protocol-architect + cjk-specialist, confirmed by
systems-engineer)

**Problem**: Doc 05 Section 7 covers race conditions for pane close (S7.1),
client disconnect (S7.2), resize (S7.3), screen switch (S7.4), and rapid
keystrokes (S7.5). But it does NOT cover focus change during active preedit.

**Impact**: If Client B sends FocusPaneRequest while Client A is composing
Korean on the focused pane, the composition state becomes inconsistent — the
preedit is on pane 1 but KeyEvents now route to pane 2.

**Resolution**: Add Section 7.7 "Focus Change During Composition": Server
commits current preedit to PTY, sends PreeditEnd with `reason="focus_changed"`
to all clients, processes focus change, sends LayoutChanged. Consistent with all
other preedit-interrupting events (screen switch, pane close).

New PreeditEnd reason values: `"focus_changed"`, `"input_method_changed"`.

| Docs Affected | Changes |
|---|---|
| 05 | New Section 7.7: focus change during composition race condition. Add `"focus_changed"` and `"input_method_changed"` to PreeditEnd reason values. |
| 03 | Focus change rule: commit active preedit before processing FocusPaneRequest |

---

### Gap 4: No Client Join/Leave Notifications

**Severity**: MEDIUM

**Problem**: Doc 02 S9.5 point 5 says "other clients receive a
ServerNotification about the client count change" but no such message type
exists. SessionListChanged (0x0182) is for sessions, not clients.

**Resolution**: Add ClientAttached (0x0183) and ClientDetached (0x0184)
notifications carrying `session_id`, `client_id`, `client_name`,
`attached_clients` count. Sent to all clients attached to the affected session.

| Docs Affected | Changes |
|---|---|
| 03 | Add ClientAttached (0x0183) and ClientDetached (0x0184) notification message types |

---

### Gap 5: Session Attachment Cardinality Undefined

**Severity**: MEDIUM

**Problem**: Can a client attach to multiple sessions simultaneously? The
lifecycle state machine (READY -> OPERATING) is ambiguous. What if a client calls
AttachSessionRequest twice?

**Resolution**: Add normative statement: "A client connection is attached to at
most one session at a time. To switch sessions, the client must first detach
(DetachSessionRequest) then attach to the new session. Sending
AttachSessionRequest while already attached returns
ERR_SESSION_ALREADY_ATTACHED." Matches tmux behavior.

| Docs Affected | Changes |
|---|---|
| 01 | State machine: single-session-per-connection normative rule |
| 03 | AttachSessionRequest: add ERR_SESSION_ALREADY_ATTACHED error handling |

---

### Gap 6: DestroySession with Attached Clients

**Severity**: MEDIUM

**Problem**: If Client A sends DestroySessionRequest while Client B is attached,
Client B's fate is unspecified.

**Resolution**: Server sends SessionListChanged("destroyed") to all connected
clients, then sends forced DetachSessionResponse with
`reason="session_destroyed"` to clients attached to the destroyed session. Those
clients transition back to READY state.

| Docs Affected | Changes |
|---|---|
| 03 | DestroySession cascade behavior for attached clients. DetachSessionResponse reason values. |

---

### Gap 7: Readonly Client Scope Undefined

**Severity**: MEDIUM

**Problem**: AttachSessionRequest has `readonly` flag but the protocol never
defines what readonly prohibits. No error code for rejected readonly operations.

**Resolution**: Add a permissions table to doc 03 defining which messages
readonly clients can send. Prohibited messages return ERR_ACCESS_DENIED (new
error code, suggest 0x00000203).

**Readonly MAY send**: queries (ListSessions, LayoutGet, Search), viewport
operations (Scroll, MouseScroll), connection management (Heartbeat, Disconnect,
Detach, ClientDisplayInfo, Subscribe).

**Readonly MUST NOT send**: any mutating input or session/pane management
(KeyEvent, TextInput, MouseButton, PasteData, InputMethodSwitch,
CreatePane, DestroyPane, ResizePane, etc.).

**Readonly receives**: all S->C messages including preedit broadcasts
(PreeditStart/Update/End/Sync, InputMethodAck) as observer.

| Docs Affected | Changes |
|---|---|
| 02 | Readonly attach semantics note |
| 03 | Readonly client permitted-message table. ERR_ACCESS_DENIED error code. |
| 04 | Readonly input rejection note |

---

### Gap 8: `detach_others` Force Detach — No Notification

**Severity**: MEDIUM

**Problem**: AttachSessionRequest has `detach_others: true` but no mechanism to
notify evicted clients.

**Resolution**: Evicted clients receive forced DetachSessionResponse with
`reason="force_detached_by_other_client"`, transition to READY. Combined with
Gap 6's fix (both are forced-detach scenarios with different reason values).

| Docs Affected | Changes |
|---|---|
| 02 | Attach semantics: detach_others notification behavior |
| 03 | DetachSessionResponse reason values: `"force_detached_by_other_client"` |

---

### Gap 9: FrameUpdate Delivery Scope

**Severity**: LOW (clarification)

**Problem**: Never explicitly stated that a client receives FrameUpdates for ALL
panes in its attached session (not just the focused pane).

**Resolution**: Add normative statement: "The server sends FrameUpdate for all
panes in the client's attached session that have dirty state, not just the
focused pane."

| Docs Affected | Changes |
|---|---|
| 04 | FrameUpdate delivery scope normative statement |

---

### Gap 10: `frame_sequence` Scope Undefined

**Severity**: LOW (clarification)

**Problem**: FrameUpdate's `frame_sequence` (u64) is not specified as per-pane
or per-(client, pane).

**Resolution**: Add normative statement: "`frame_sequence` is a per-pane
monotonic counter incremented each time the server produces a new terminal state
for that pane (regardless of which clients receive it). Clients may observe gaps
due to coalescing or flow control."

| Docs Affected | Changes |
|---|---|
| 04 | frame_sequence scope normative statement |

---

### Gap 11: OutputQueueStatus Is Per-Client

**Severity**: LOW (clarification)

**Problem**: Doc 06's OutputQueueStatus (0x0504) is ambiguous about whether it
reports per-client or aggregate queue state.

**Resolution**: Add normative statement: "OutputQueueStatus reports per-client
queue state for the receiving client's connection, not aggregate server state."

| Docs Affected | Changes |
|---|---|
| 06 | OutputQueueStatus explicitly per-client |

---

### Gap 12: Preedit-Only FrameUpdate to Paused Clients

**Severity**: LOW (clarification)

**Problem**: Preedit bypasses PausePane (doc 06 correctly specifies this), but
the format of preedit-only FrameUpdates to paused clients is not specified.

**Resolution**: Preedit bypass FrameUpdate uses `dirty_row_count=0` (no grid
data) + JSON preedit metadata (~100-110 bytes). This allows the client to update
preedit overlay without receiving full terminal grid state. Edge case: preedit
commit while paused — client sees PreeditEnd but not grid update until
ContinuePane.

| Docs Affected | Changes |
|---|---|
| 05 | Preedit-only FrameUpdate format for paused clients |
| 06 | PausePane preedit exception: preedit-only FrameUpdate format and commit-while-paused behavior |

---

### Additional Interactions Discovered During Multi-Client Review

**InputMethodSwitch during active preedit**: Not covered in any race condition
section. If input method is switched on a pane with active preedit, server MUST
commit preedit first, then send PreeditEnd with `reason="input_method_changed"`,
then process the input method switch.

**Per-client dirty tracking semantics**: Doc 06 S1.4 says "per-client dirty
bitmaps" but doesn't specify when dirty bits are cleared. Normative statement:
"The server maintains independent dirty bitmaps per (client, pane) pair. A row's
dirty flag for a specific client is cleared only when a FrameUpdate containing
that row's data has been sent to that client."

---

## Carry-over from v0.1/v0.2: CJK Cursor Style During Composition

**Status**: RESOLVED in v0.3 with normative tightening for v0.4

### Current State

Doc 05 (v0.3) already specifies:
- During composition: `cursor.style` = block(0), `cursor.blinking` = false
- `cursor.x/y` == `preedit.cursor_x/y` (block cursor encloses composing character)
- Cursor width follows `display_width` (2 cells for Hangul syllable, 1 cell for
  standalone Jamo)
- On commit: pre-composition cursor style restored, cursor advances

### Normative Tightening for v0.4

Three descriptive statements promoted to normative requirements:

1. **Server MUST restore pre-composition cursor style** (`cursor.style` and
   `cursor.blinking`) in the FrameUpdate following PreeditEnd.
2. **Server MUST set block(0) + non-blinking** during active composition.
3. **Client MUST NOT override cursor style** based on local preedit state —
   render whatever the server sends in FrameUpdate.

| Docs Affected | Changes |
|---|---|
| 04 | Section 4.2 (or equivalent): promote cursor-during-composition to normative MUST |
| 05 | Section 10.1 (or equivalent): add client MUST NOT override note |

---

## Carry-over from v0.1/v0.2: Multi-Client Window Size Negotiation

**Status**: RESOLVED in v0.3 — no changes needed

Systems Engineer confirmed: Doc 02 Section 9.6 and doc 03 Section 5.1 both
consistently specify `min(cols, rows)` across all attached clients, with
detach-triggered recomputation. Per-client viewports deferred to v2. No
contradiction remains.

---

## Summary of All Resolutions

| # | Issue | Resolution | Docs Affected |
|---|---|---|---|
| 1 | Flags byte bit numbering | Add LSB-first convention + concrete example | 01 |
| 2 | Heartbeat timestamp | Simplify to `ping_id`-only liveness; drop `timestamp` and `responder_timestamp`; RTT rejected (not deferred) | 01, 06 |
| 3 | JSON optional fields | Omit absent fields, never send null | 01 (all docs apply) |
| 4 | TCP+TLS transport | Replace with SSH tunneling; extend ClientDisplayInfo with transport hints; remove `"remote"` client type; scope preedit latency | 01, 02, 06 |
| 5 | zstd compression | Remove from v1; reserve COMPRESSED bit and capability for v2 | 01, 06 |
| 6 | Input language negotiation | Two-axis model (input_method + keyboard_layout); string identifiers everywhere; handshake negotiation; per-pane state via two-channel (LayoutChanged + InputMethodAck) | 02, 03, 04, 05 |
| 7 | Daemon lifecycle | Auto-start note; AttachOrCreateRequest (0x010C/0x010D); auto-create on empty sessions | 01, 03 |
| 8 | Error message type | Move from 0x0006 to 0x00FF | 01 |
| 9 | Multi-client per-session gaps | 12 gaps: `client_id` in ServerHello, `pane_id` in KeyEvent, focus-change preedit race, client join/leave notifications, session attachment cardinality, DestroySession cascade, readonly scope, detach_others notification, FrameUpdate scope, frame_sequence scope, OutputQueueStatus per-client, preedit bypass format | 01, 02, 03, 04, 05, 06 |
| CO-1 | CJK cursor style | Resolved in v0.3; add normative MUST tightening | 04, 05 |
| CO-2 | Multi-client window size | Resolved in v0.3; no changes needed | — |

---

## Changes by Document

| Doc | Owner | Changes |
|---|---|---|
| **01 — Protocol Overview** | protocol-architect | Issue 1: bit numbering. Issue 2: heartbeat to `ping_id`-only, RTT rejected. Issue 3: JSON optional convention. Issue 4: SSH tunneling replaces TCP+TLS, preedit latency scoping, SSH trust model. Issue 5: defer compression. Issue 7: state machine + auto-start note. Issue 8: Error → 0x00FF. Issue 9/Gap 5: single-session-per-connection normative rule in state machine. |
| **02 — Handshake** | protocol-architect | Issue 4: remove `"remote"` client type, add transport fields to ClientDisplayInfo. Issue 6: add `supported_input_methods` to ServerHello, `preferred_input_methods` to ClientHello, `pane_input_methods` to AttachSessionResponse. Issue 7: AttachOrCreate state transition reference. Issue 9/Gap 1: add `client_id` to ServerHello. Issue 9/Gap 7: readonly attach semantics note. Issue 9/Gap 8: detach_others notification behavior. |
| **03 — Session/Pane Mgmt** | systems-engineer | Issue 6: `active_input_method` + `active_keyboard_layout` in LayoutChanged leaf nodes, InputMethodAck broadcast to all clients, default input method for new panes. Issue 7: AttachOrCreateRequest (0x010C/0x010D), auto-create semantics. Issue 9/Gap 3: focus change commits active preedit rule. Issue 9/Gap 4: ClientAttached (0x0183) / ClientDetached (0x0184). Issue 9/Gap 5: ERR_SESSION_ALREADY_ATTACHED. Issue 9/Gap 6: DestroySession cascade. Issue 9/Gap 7: readonly permissions table, ERR_ACCESS_DENIED. Issue 9/Gap 8: forced DetachSessionResponse reasons. |
| **04 — Input/RenderState** | cjk-specialist | Issue 6: rename `active_layout_id` → `input_method` (string) in KeyEvent, restructure layout ID table. CO-1: promote cursor-during-composition to normative MUST. Issue 9/Gap 2: add optional `pane_id` to KeyEvent. Issue 9/Gap 7: readonly input rejection note. Issue 9/Gap 9: FrameUpdate delivery scope. Issue 9/Gap 10: frame_sequence scope. Issue 9: per-client dirty tracking semantics. |
| **05 — CJK Preedit** | cjk-specialist | Issue 6: rename `active_layout_id` → `active_input_method` in PreeditSync/InputMethodAck, update InputMethodSwitch to string model. CO-1: add client MUST NOT override cursor style note. Issue 9/Gap 3: new Section 7.7 focus change during composition, new PreeditEnd reasons. Issue 9: Section 7.9 InputMethodSwitch during active preedit. Issue 9: readonly client preedit observation note. Issue 9/Gap 12: preedit-only FrameUpdate format for paused clients. |
| **06 — Flow Control** | systems-engineer | Issue 2: update heartbeat policy. Issue 4: add transport fields to ClientDisplayInfo wire spec, WAN coalescing tier adjustments. Issue 5: remove compression interaction from flow control. Issue 9/Gap 11: OutputQueueStatus explicitly per-client. Issue 9/Gap 12: PausePane preedit exception format and commit-while-paused behavior. |

---

## Next Steps

1. Each document owner applies the agreed changes to their docs for v0.4
2. protocol-architect updates docs 01, 02
3. systems-engineer updates docs 03, 06
4. cjk-specialist updates docs 04, 05
5. Cross-review after updates to verify consistency
