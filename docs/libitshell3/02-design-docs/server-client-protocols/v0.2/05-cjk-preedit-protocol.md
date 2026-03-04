# 05 — CJK Preedit Sync and IME Protocol

**Status**: Draft v0.2
**Author**: rendering-cjk-specialist
**Date**: 2026-03-04
**Depends on**: 01-protocol-overview.md (header format), 04-input-and-renderstate.md (FrameUpdate, KeyEvent)

**Changes from v0.1**:
- Header updated from 14 bytes to 16 bytes (canonical format per doc 01)
- `length` field renamed to `payload_len` (payload only, not including header)
- All wire format offsets updated for 16-byte header
- All message sizes updated for 16-byte header
- Section 1 (Overview): clarified that ALL preedit messages are S->C; client NEVER sends preedit state
- Section 1 (Overview): added explicit dual-channel rendering rule
- Architecture diagram: corrected PreeditUpdate delivery to show broadcast to ALL clients
- Section 2: clarified direction annotations on all preedit lifecycle messages
- Section 3.4: added cursor behavior during backspace decomposition
- Section 4.1: added note about server-side hotkey detection for IME switching
- Section 7.3: added normative message ordering (FrameUpdate before PreeditUpdate)
- Section 7: added cross-reference to LayoutGet for layout query during reconnection
- Section 9.1: added cursor style cross-reference to doc 04; added cursor position spec
- Section 13: added authoritative rendering rule and capability interaction note

---

## 1. Overview

This document specifies the protocol messages for CJK Input Method Editor (IME) composition state synchronization. The design addresses:

1. **Preedit lifecycle management**: Start, update, end of composition sessions
2. **Multi-client sync**: Broadcasting preedit state to all attached clients
3. **Korean Hangul composition**: The most complex case — Jamo decomposition on backspace
4. **Input method switching**: Per-pane keyboard layout state
5. **Race condition handling**: Pane close during composition, client disconnect, concurrent preedit
6. **Session persistence**: Serializing/restoring preedit state across daemon restart

### Architecture Context

The server owns the native IME engine (libitshell3-ime). The client sends ONLY raw HID keycodes via KeyEvent (doc 04, Section 2.1). The client NEVER sends preedit state or composition information — the server determines all composition state internally from the IME engine.

```
Client A (active typist)          Server (libitshell3-ime)         Client B (observer)
────────────────────────          ──────────────────────           ────────────────────

KeyEvent(HID keycode)  ─────►    IME Composition Engine
                                       │
                                       ├── Preedit changed?
                                       │     ├── Yes: Update preedit state
                                       │     │         │
                                       │     │         ├── PreeditUpdate (S->C) ──────► Client A
                                       │     │         ├── PreeditUpdate (S->C) ──────► Client B
                                       │     │         ├── FrameUpdate (preedit section) ──► Client A
                                       │     │         └── FrameUpdate (preedit section) ──► Client B
                                       │     │
                                       │     └── No: process normally
                                       │
                                       └── Text committed?
                                             ├── Write to PTY
                                             ├── PreeditEnd (S->C) ──────► Client A
                                             └── PreeditEnd (S->C) ──────► Client B
```

**Dual-channel design**: Preedit state is communicated through TWO mechanisms:

1. **FrameUpdate preedit section (0x0300)**: For rendering. Contains the preedit text and cursor position within the terminal frame. This is the **authoritative rendering source** — clients MUST use this to draw the preedit overlay. The preedit section is always included when preedit is active, regardless of `CJK_CAP_PREEDIT` capability.

2. **Dedicated preedit messages (0x0400-0x04FF)**: For state tracking. Contains composition state details (Korean Jamo state, layout info) useful for debugging, multi-client conflict resolution, and session snapshots. Observers (non-typing clients) can use these to display composition state indicators. These messages are sent only to clients that negotiated `CJK_CAP_PREEDIT`.

**Rendering rule**: Clients MUST use FrameUpdate's preedit section for rendering, NOT PreeditUpdate's text field. PreeditUpdate provides metadata (composition_state, session_id, owner) for state tracking only.

### Message Type Range

| Range | Category | Direction |
|-------|----------|-----------|
| `0x0400`-`0x04FF` | CJK/IME messages | See per-message direction below |

---

## 2. Preedit Lifecycle Messages

All preedit lifecycle messages (PreeditStart, PreeditUpdate, PreeditEnd, PreeditSync) flow **S->C** (server to client). The server is the sole authority on composition state.

### 2.1 PreeditStart (type = 0x0400, S->C)

Sent by the server to ALL attached clients when a new composition session begins on a pane. This occurs when the first composing keystroke is processed by the IME engine.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0400, payload_len=19
16       4    pane_id             Target pane (u32 LE)
20       4    client_id           Client that initiated composition (u32 LE)
24       2    cursor_x            Composition start column (u16 LE)
26       2    cursor_y            Composition start row (u16 LE)
28       2    active_layout_id    Keyboard layout (u16 LE, same IDs as KeyEvent)
30       1    composition_state   Initial state: 0=empty (always 0 for start)
31       4    preedit_session_id  Unique ID for this composition session (u32 LE)
```

**Total payload**: 19 bytes. **Total with header**: 35 bytes.

The `preedit_session_id` is a monotonically increasing counter per pane. It disambiguates overlapping composition sessions (e.g., one ends and another starts quickly).

### 2.2 PreeditUpdate (type = 0x0401, S->C)

Sent by the server to ALL attached clients each time the composition state changes (keystroke adds/removes a Jamo, composition advances).

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0401, payload_len=15+N
16       4    pane_id             (u32 LE)
20       4    preedit_session_id  Matches PreeditStart (u32 LE)
24       2    cursor_x            Current preedit cursor column (u16 LE)
26       2    cursor_y            Current preedit cursor row (u16 LE)
28       1    composition_state   Current state enum (u8, see Section 3)
29       1    display_width       Width of preedit text in cells (u8)
30       1    preedit_text_len    Length of preedit text in bytes (u8)
31       N    preedit_text        UTF-8 encoded preedit string
```

**Typical size**: 31 + 3 (single Korean syllable UTF-8) = **34 bytes**.

**Note**: `display_width` is the visual width in terminal cells, which may differ from the byte length or codepoint count. A single Hangul syllable is 2 cells wide. The client uses this for overlay positioning.

### 2.3 PreeditEnd (type = 0x0402, S->C)

Sent by the server to ALL attached clients when composition ends, either by committing text or cancelling.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0402, payload_len=11+N
16       4    pane_id             (u32 LE)
20       4    preedit_session_id  Matches PreeditStart (u32 LE)
24       1    reason              0=committed, 1=cancelled, 2=pane_closed,
                                  3=client_disconnected, 4=replaced_by_other_client
25       2    committed_text_len  Length of committed text (u16 LE, 0 if cancelled)
27       N    committed_text      UTF-8 committed text (absent if cancelled)
```

**Committed text** is the final text written to the PTY. For Korean: if the user composed "한" and pressed Space, committed_text="한".

**Cancel reasons**:
- `0=committed`: Normal completion (Space, Enter, non-Jamo key)
- `1=cancelled`: User pressed Escape during composition
- `2=pane_closed`: Pane was closed while composition was active
- `3=client_disconnected`: The composing client disconnected
- `4=replaced_by_other_client`: Another client started composing on the same pane

### 2.4 PreeditSync (type = 0x0403, S->C)

Server -> specific client. Sent when a client attaches to a pane that has an active composition session (e.g., a second client connects while Client A is mid-composition). This is a full state snapshot — self-contained, unlike PreeditUpdate which assumes the client has PreeditStart context.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0403, payload_len=21+N
16       4    pane_id             (u32 LE)
20       4    preedit_session_id  Current session ID (u32 LE)
24       4    preedit_owner       Client ID that owns the composition (u32 LE)
28       2    cursor_x            (u16 LE)
30       2    cursor_y            (u16 LE)
32       1    composition_state   Current state (u8)
33       2    active_layout_id    (u16 LE)
35       1    display_width       (u8)
36       1    preedit_text_len    (u8)
37       N    preedit_text        UTF-8 preedit string
```

This is essentially a snapshot of the current preedit state for late-joining clients. It carries additional fields (`preedit_owner`, `active_layout_id`) that are redundant in the normal PreeditUpdate flow but essential for initial sync.

---

## 3. Korean Composition State Machine

### 3.1 State Enum

The `composition_state` field (u8) encodes the current Korean Hangul composition state:

```
Value  State                Description
─────  ─────                ───────────
0x00   empty                No composition active (initial/terminal state)
0x01   leading_jamo         Single consonant: ㅎ, ㄴ, ㄱ, ...
0x02   syllable_no_tail     Consonant + vowel: 하, 나, 가, ...
0x03   syllable_with_tail   Full syllable (C+V+C): 한, 난, 간, ...
0x04   double_tail          Syllable with double final consonant: 읽 (ㅇ+ㅣ+ㄹㄱ)
0x10   non_korean           Non-Korean composition (future: Japanese, Chinese)
```

### 3.2 State Transition Diagram

```
                    ┌─────────────────────────────────────────────────┐
                    │                                                 │
                    │   ┌──────────────────────────────────────┐     │
                    │   │  non-jamo key / Space / Enter         │     │
                    │   │  (commit current + pass through)      │     │
                    │   │                                       │     │
                    ▼   │                                       │     │
              ┌─────────┴──┐                                    │     │
              │            │                                    │     │
 consonant    │   empty    │◄──── backspace                    │     │
  ────────►   │   (0x00)   │      (from leading_jamo)          │     │
              │            │                                    │     │
              └─────┬──────┘                                    │     │
                    │ consonant                                 │     │
                    ▼                                           │     │
              ┌────────────┐                                    │     │
              │  leading    │──── non-jamo ─────────────────────┘     │
  vowel       │  _jamo     │     (commit ㅎ + pass through)          │
  ────────►   │  (0x01)    │                                          │
              │  e.g., ㅎ  │◄──── backspace                          │
              └─────┬──────┘      (from syllable_no_tail)             │
                    │ vowel                                            │
                    ▼                                                  │
              ┌────────────┐                                          │
              │  syllable   │──── non-jamo ───────────────────────────┘
  consonant   │  _no_tail  │     (commit 하 + pass through)
  ────────►   │  (0x02)    │
              │  e.g., 하  │◄──── backspace
              └─────┬──────┘      (from syllable_with_tail)
                    │ consonant
                    ▼
              ┌────────────┐
              │  syllable   │──── non-jamo ──────────────────────────┐
              │  _with_tail │     (commit 한 + pass through)         │
              │  (0x03)    │                                          │
              │  e.g., 한  │                                          │
              └─────┬──────┘                                          │
                    │                                                  │
                    │ vowel (Jamo reassignment)                       │
                    │ Split tail consonant: 한 + ㅏ → commit 하,     │
                    │   new syllable_no_tail 나                       │
                    ▼                                                  │
              ┌────────────┐                                          │
              │  syllable   │                                          │
              │  _no_tail  │◄─────────────────────────────────────────┘
              │  (0x02)    │
              │  (new)     │
              └────────────┘
```

### 3.3 Complete Transition Table

| Current State | Input | Next State | Preedit | Commit | Notes |
|---------------|-------|------------|---------|--------|-------|
| empty | consonant | leading_jamo | "ㅎ" | — | Begin composition |
| empty | vowel | syllable_no_tail | "ㅇ+V" | — | Implicit ㅇ leading (Korean convention) |
| empty | non-jamo | empty | — | passthrough | Not a Korean character |
| leading_jamo | vowel | syllable_no_tail | "하" | — | Form syllable |
| leading_jamo | consonant | leading_jamo | "ㄴ" | "ㅎ" | Commit previous, start new |
| leading_jamo | non-jamo | empty | — | "ㅎ" + passthrough | Commit consonant |
| leading_jamo | backspace | empty | — | — | Remove consonant |
| syllable_no_tail | consonant | syllable_with_tail | "한" | — | Add tail consonant |
| syllable_no_tail | vowel | syllable_no_tail | "해" | — | Replace vowel (only certain transitions) |
| syllable_no_tail | non-jamo | empty | — | "하" + passthrough | Commit syllable |
| syllable_no_tail | backspace | leading_jamo | "ㅎ" | — | Remove vowel |
| syllable_with_tail | vowel | syllable_no_tail | "나" | "하" | Jamo reassignment |
| syllable_with_tail | consonant | syllable_with_tail | "핝" | — | Form double-tail (if valid) OR commit + new leading |
| syllable_with_tail | non-jamo | empty | — | "한" + passthrough | Commit syllable |
| syllable_with_tail | backspace | syllable_no_tail | "하" | — | Remove tail consonant |
| double_tail | vowel | syllable_no_tail | "가" | "읽" | Split: commit base, new syllable with split consonant |
| double_tail | backspace | syllable_with_tail | "읽→일" | — | Remove second tail consonant |

### 3.4 Backspace Decomposition Trace

Korean backspace is NOT "delete previous character" — it decomposes the composition step by step:

```
State              Preedit  Composition State      Backspace Result
─────              ───────  ─────────────────      ────────────────
한 (0xD55C)        "한"     syllable_with_tail     → "하" (remove ㄴ)
하 (0xD558)        "하"     syllable_no_tail       → "ㅎ" (remove ㅏ)
ㅎ (0x314E)        "ㅎ"     leading_jamo           → "" (clear, end composition)
```

**Cursor behavior during decomposition**: The cursor position remains at `preedit_cursor_x` throughout decomposition. The block cursor width follows the composing character's `display_width`: 2 cells for a Hangul syllable (하, 한), 1 cell for a standalone Jamo (ㅎ). The server updates `display_width` in both FrameUpdate preedit section and PreeditUpdate accordingly.

**Wire trace** (server sends to all clients):

```
1. PreeditUpdate: pane=1, state=syllable_no_tail, text="하", width=2
   + FrameUpdate: preedit section with text="하", cursor_style=block (2 cells)

2. PreeditUpdate: pane=1, state=leading_jamo, text="ㅎ", width=1
   + FrameUpdate: preedit section with text="ㅎ", cursor_style=block (1 cell)

3. PreeditEnd: pane=1, reason=cancelled, committed_text=""
   + FrameUpdate: preedit section with active=0, cursor_style restored
```

Note: Backspace during `leading_jamo` produces a PreeditEnd with `reason=1 (cancelled)` and empty committed text, because the composition was fully undone without committing anything.

---

## 4. Input Method Switching

### 4.1 InputMethodSwitch (type = 0x0404, C->S)

Client -> server. The client requests switching the active keyboard layout for a pane.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0404, payload_len=10
16       4    pane_id             Target pane (u32 LE)
20       2    layout_id           New layout ID (u16 LE)
22       1    flags               Bit 0: commit_current (if 1, commit active preedit before switching)
                                  Bit 1: per_pane (if 1, only this pane; if 0, all panes in session)
23       3    reserved            Must be 0
```

**Server behavior**:
1. If `commit_current=1` and preedit is active, commit current preedit text to PTY
2. If `commit_current=0` and preedit is active, cancel current preedit (PreeditEnd with reason=cancelled)
3. Update the pane's (or session's) active layout
4. Send InputMethodAck to the requesting client
5. If `per_pane=0`, broadcast layout change to all panes in the session

**Server-side hotkey detection**: In addition to the explicit InputMethodSwitch message, the server detects configurable mode-switch hotkeys (e.g., Right-Alt, Ctrl+Space) from raw KeyEvent and handles layout switching internally. Both paths produce InputMethodAck (0x0405) sent to all attached clients.

### 4.2 InputMethodAck (type = 0x0405, S->C)

Server -> client. Confirms the layout switch.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0405, payload_len=8
16       4    pane_id             (u32 LE)
20       2    active_layout_id    The now-active layout (u16 LE)
22       2    previous_layout_id  The previously active layout (u16 LE)
```

### 4.3 Per-Pane Layout State

Each pane independently tracks its active keyboard layout. This allows users to have:
- Pane 1: Korean input for a Korean document
- Pane 2: English input for code
- Pane 3: Japanese input for another document

Layout state is stored in the server's pane metadata and included in session snapshots.

---

## 5. Ambiguous Width Configuration

### 5.1 AmbiguousWidthConfig (type = 0x0406)

Client -> server (or server -> client during handshake). Configures how ambiguous-width Unicode characters are measured.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x0406, payload_len=6
16       4    pane_id             Target pane (u32 LE), 0xFFFFFFFF = all panes
20       1    ambiguous_width     1 = single-width (Western default)
                                  2 = double-width (East Asian default)
21       1    scope               0 = per-pane, 1 = per-session, 2 = global
```

**Affected characters**: Unicode characters with East Asian Width property "A" (Ambiguous):
- Box drawing (─ │ ┌ ┐ ┘ └)
- Greek letters (α β γ δ)
- Cyrillic letters
- Various symbols (° ± × ÷ ≤ ≥)

The server passes this configuration to libghostty-vt's Terminal, which uses it for cursor movement and line wrapping calculations. The client uses it for cell width computation during rendering.

---

## 6. Multi-Client Conflict Resolution

### 6.1 Problem Statement

When multiple clients are attached to the same pane, only one client can compose text at a time. Without coordination, concurrent preedit from two clients would corrupt the composition state.

### 6.2 Preedit Ownership Model

The server maintains a `preedit_owner` field per pane:

```
struct PanePreeditState {
    owner: ?u32,              // client_id of the composing client, null = no active composition
    session_id: u32,          // monotonic counter for composition sessions
    state: CompositionState,  // Korean state machine state
    preedit_text: []u8,       // current preedit string (UTF-8)
    cursor_x: u16,
    cursor_y: u16,
    layout_id: u16,
}
```

### 6.3 Ownership Rules

**Last-Writer-Wins** with explicit takeover notification:

1. **First composer**: When Client A sends a KeyEvent that triggers composition on a pane with no active preedit, Client A becomes the preedit owner.

2. **Concurrent attempt**: When Client B sends a composing KeyEvent on the same pane while Client A owns the preedit:
   - Server commits Client A's current preedit text to PTY
   - Server sends PreeditEnd to all clients with `reason=4 (replaced_by_other_client)`
   - Server starts a new composition session owned by Client B
   - Server sends PreeditStart to all clients with Client B as owner

3. **Owner disconnect**: When the preedit owner disconnects:
   - Server commits current preedit text to PTY (if any)
   - Server sends PreeditEnd with `reason=3 (client_disconnected)`

4. **Non-composing input from non-owner**: Regular (non-composing) KeyEvents from any client are always processed normally, regardless of preedit ownership. If a non-owner sends a regular key, the owner's preedit is committed first.

### 6.4 Conflict Resolution Sequence Diagram

```
Client A                Server                  Client B
────────                ──────                  ────────
KeyEvent(ㅎ) ──────►    Preedit owner = A
                        PreeditStart(owner=A) ────────────► (display indicator)
                        PreeditUpdate("ㅎ") ──────────────►
                        FrameUpdate(preedit) ──────────────►
◄── FrameUpdate(preedit)

                        ... Client A composing ...

                        KeyEvent(ㅏ) ◄──────── Client B starts typing

                        [Conflict! Commit A's preedit]
                        Write "ㅎ" to PTY
                        PreeditEnd(reason=replaced) ──────►
◄── PreeditEnd(reason=replaced)

                        [New session for B]
                        Preedit owner = B
                        PreeditStart(owner=B) ────────────►
◄── PreeditStart(owner=B)
                        PreeditUpdate("ㅏ") ──────────────►
◄── PreeditUpdate("ㅏ")
```

---

## 7. Race Condition Handling

### 7.1 Pane Close During Composition

**Scenario**: User closes a pane while Korean composition is active.

**Server behavior**:
1. Cancel the active composition (do NOT commit to PTY — the PTY is being closed)
2. Send PreeditEnd with `reason=2 (pane_closed)` to all clients
3. Proceed with pane close sequence

**Wire trace**:
```
Server → all clients: PreeditEnd(pane=X, reason=pane_closed, committed="")
Server → all clients: PaneClose(pane=X)  // from session management protocol
```

### 7.2 Client Disconnect During Composition

**Scenario**: The composing client's connection drops (network failure, crash).

**Server behavior**:
1. Detect disconnect (socket read returns 0 or error)
2. Commit current preedit text to PTY (best-effort: preserve the user's work)
3. Send PreeditEnd with `reason=3 (client_disconnected)` to remaining clients
4. Clear preedit ownership

**Timeout**: If the server receives no input from the preedit owner for 30 seconds, it commits the current preedit and ends the session. This handles cases where the client is frozen but the socket is still open.

### 7.3 Concurrent Preedit and Resize

**Scenario**: The terminal is resized while composition is active.

**Server behavior**:
1. Process the resize through libghostty-vt Terminal
2. Recalculate preedit cursor position (the cursor row/column may have changed due to reflow)
3. Send FrameUpdate with `dirty=full` (includes updated preedit section with new coordinates)
4. Send PreeditUpdate with updated cursor coordinates

The server MUST send FrameUpdate before PreeditUpdate when both are triggered by the same resize event. This ensures the client has the updated cell grid dimensions before repositioning the preedit overlay. However, since clients MUST use FrameUpdate's preedit section for rendering (not PreeditUpdate), the protocol is resilient to PreeditUpdate arriving late or being dropped.

The preedit text itself is not affected by resize — only its display position changes.

### 7.4 Screen Switch During Composition

**Scenario**: An application switches from primary to alternate screen (e.g., `vim` launches) while composition is active.

**Server behavior**:
1. Commit current preedit text to PTY before the screen switch
2. Send PreeditEnd with `reason=0 (committed)`
3. Process the screen switch
4. Send FrameUpdate with `dirty=full`, `screen=alternate`

**Rationale**: Alternate screen applications (vim, less, htop) have their own input handling. Carrying preedit state into the alternate screen would be confusing.

### 7.5 Rapid Keystroke Bursts

**Scenario**: User types Korean very quickly, generating multiple KeyEvents before the server processes them.

**Server behavior**:
1. Process all pending KeyEvents in order
2. Coalesce intermediate preedit states — only send the final PreeditUpdate for the burst
3. The FrameUpdate for the frame interval contains only the final preedit state

**Example**: User types ㅎ, ㅏ, ㄴ within 5ms (all arrive in one read batch):
- Server processes all three through IME engine
- Server sends ONE PreeditUpdate with state=syllable_with_tail, text="한"
- Server sends ONE FrameUpdate with preedit="한"

Intermediate states (ㅎ, 하) are not transmitted because they were superseded within the same frame interval.

### 7.6 Layout Query After Reconnection

When a client reconnects or a new client attaches, it can query the current layout tree via `LayoutGetRequest` (doc 03). The layout response includes a per-pane `preedit_active` flag in the leaf node metadata. For panes with active composition, the server additionally sends `PreeditSync` (0x0403) with the full preedit state snapshot.

---

## 8. Preedit in Session Snapshots

### 8.1 Snapshot Format

When the server serializes session state to disk (for persistence across daemon restart), preedit state is included:

```json
{
  "panes": [
    {
      "pane_id": 1,
      "preedit": {
        "active": true,
        "session_id": 42,
        "owner_client_id": 7,
        "composition_state": "syllable_with_tail",
        "preedit_text": "한",
        "cursor_x": 15,
        "cursor_y": 3,
        "layout_id": 1
      }
    }
  ]
}
```

### 8.2 Restore Behavior

When the daemon restarts and restores a session:

1. **Preedit was active**: The preedit text is committed to the PTY. The composition session is not resumed.
   - **Rationale**: The client that was composing is no longer connected after a daemon restart. Resuming a partial composition would be confusing — the user would see a half-composed character with no way to continue it (since the original client's keyboard state is lost).

2. **Layout state**: Per-pane layout IDs are restored. When a client reconnects, it receives the pane's saved layout ID via PreeditSync.

### 8.3 Alternative: Resume Composition (Future)

A future enhancement could allow composition resumption:
1. Server sends PreeditSync to the reconnecting client with the saved state
2. Client displays the preedit overlay
3. User can continue typing to advance the composition or press Backspace to decompose

This requires the client to initialize its composition state from the server's snapshot, which is feasible for Korean (the state machine is simple) but complex for Japanese/Chinese (candidate lists would need to be regenerated).

**Decision**: For v1, commit-on-restore. Defer resume-on-restore to v2.

---

## 9. Preedit Rendering Protocol

### 9.1 Client Rendering Responsibilities

The client renders preedit using the `preedit` section from FrameUpdate (see Doc 04, Section 4.5). This is the authoritative rendering source. The rendering approach:

1. Draw the terminal grid normally (all cells from DirtyRows)
2. At position `(preedit_cursor_x, preedit_cursor_y)`, overlay the preedit text:
   - Background: slightly different from the terminal background (e.g., lighter/darker by 10%)
   - Text: same font as terminal text, with underline decoration
   - Width: use `display_width` from PreeditUpdate for cell count

**Cursor style during composition**: The server automatically adjusts `cursor_style` in FrameUpdate during composition (see doc 04, Section 4.4). Specifically:
- `cursor_style` is set to block (0) and `cursor_blinking` to steady (0) during composition
- `cursor_x` and `cursor_y` equal `preedit_cursor_x` and `preedit_cursor_y` — the block cursor visually encloses the composing character
- Clients render the cursor as specified in FrameUpdate's cursor section without any preedit-specific overrides

```
During composition of "한" (2 cells wide):
┌──────────────────────────────────────────────┐
│ $ echo "hello"                               │
│ hello                                        │
│ $ [한]                                       │  ← block cursor encloses composing char
│    ──                                        │  ← underline decoration
└──────────────────────────────────────────────┘

After commit (cursor advances past committed char):
┌──────────────────────────────────────────────┐
│ $ echo "hello"                               │
│ hello                                        │
│ $ 한█                                        │  ← bar cursor at insertion point
│                                              │
└──────────────────────────────────────────────┘
```

### 9.2 Preedit for Observer Clients

Non-owner clients (observers) also render the preedit overlay. They additionally MAY display an indicator showing which client is composing:

```
┌──────────────────────────────────────────────┐
│ $ [한]                                       │
│    ── [Client A composing]                   │  ← optional indicator
└──────────────────────────────────────────────┘
```

The `preedit_owner` field from PreeditSync/PreeditStart provides the client ID for this indicator.

---

## 10. Error Handling

### 10.1 Invalid Composition State

If the server's IME engine reaches an invalid state (should not happen with correctly implemented Korean algorithms):

1. Log the error with full state dump
2. Commit whatever preedit text exists to PTY
3. Reset composition state to `empty`
4. Send PreeditEnd with `reason=1 (cancelled)` to all clients
5. Send a diagnostic notification to the composing client (optional)

### 10.2 Malformed Preedit Messages

If the server receives a message with invalid fields:

| Error | Response |
|-------|----------|
| Unknown layout_id | Ignore the layout switch, send error response |
| preedit_session_id mismatch | Ignore the message (stale) |
| preedit_text not valid UTF-8 | Drop message, log error |
| pane_id does not exist | Send error response with error code |

### 10.3 Error Response (type = 0x04FF)

Generic error response for CJK/IME operations.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      16    [header]            type=0x04FF, payload_len=8+N
16       4    pane_id             Related pane (u32 LE)
20       2    error_code          Error identifier (u16 LE)
22       2    detail_len          Length of error detail (u16 LE)
24       N    detail              UTF-8 error description
```

**Error codes**:

| Code | Meaning |
|------|---------|
| `0x0001` | Unknown layout ID |
| `0x0002` | Pane does not exist |
| `0x0003` | Invalid composition state transition |
| `0x0004` | Preedit session ID mismatch |
| `0x0005` | UTF-8 encoding error in preedit text |
| `0x0006` | Layout not supported by server |

---

## 11. Message Type Summary

| Type | Name | Direction | Size (typical) | Description |
|------|------|-----------|----------------|-------------|
| `0x0400` | PreeditStart | S -> C | 35 B | New composition session begins |
| `0x0401` | PreeditUpdate | S -> C | ~34 B | Composition state changed |
| `0x0402` | PreeditEnd | S -> C | ~29 B | Composition session ended |
| `0x0403` | PreeditSync | S -> C | ~37 B | Full preedit snapshot for late-joining client |
| `0x0404` | InputMethodSwitch | C -> S | 26 B | Request keyboard layout change |
| `0x0405` | InputMethodAck | S -> C | 24 B | Confirm layout change |
| `0x0406` | AmbiguousWidthConfig | Bi | 22 B | Set ambiguous character width |
| `0x04FF` | IMEError | S -> C | ~26 B | Error response |

---

## 12. Bandwidth Analysis for Preedit

### 12.1 Korean Composition Bandwidth

Typing Korean at ~60 WPM (words per minute), approximately 5 syllables/second. Each syllable requires ~3 keystrokes (consonant + vowel + tail consonant), generating ~3 PreeditUpdate messages.

| Message | Size | Per-second | Bandwidth |
|---------|------|------------|-----------|
| PreeditUpdate | ~34 B | ~15/s | 510 B/s |
| FrameUpdate (preedit section) | ~90 B | ~15/s | 1.35 KB/s |
| PreeditEnd (commit) | ~29 B | ~5/s | 145 B/s |
| **Total preedit overhead** | | | **~2.0 KB/s** |

This is negligible compared to the overall FrameUpdate bandwidth (~10 KB/s typical).

### 12.2 Multi-Client Overhead

With N clients attached, preedit messages are sent to each client:
- 2 clients: ~4.0 KB/s preedit overhead
- 5 clients: ~10 KB/s preedit overhead
- 10 clients: ~20 KB/s preedit overhead

All well within Unix socket capacity.

---

## 13. Integration with FrameUpdate

### 13.1 Preedit in FrameUpdate vs. Dedicated Messages

Both mechanisms are used because they serve different purposes:

| Mechanism | Purpose | Consumer |
|-----------|---------|----------|
| FrameUpdate preedit section | **Rendering**: Where to draw the preedit overlay | Rendering pipeline |
| PreeditStart/Update/End | **State tracking**: Composition details, ownership, conflict resolution | Session manager, debugging, multi-client sync |

**Authoritative rendering rule**: Clients MUST use FrameUpdate's preedit section for rendering, NOT PreeditUpdate's text field. The FrameUpdate preedit section is synchronized with the grid data in the same message, ensuring visual consistency. PreeditUpdate's text may arrive slightly before or after the corresponding FrameUpdate due to buffering. The dedicated messages add metadata (composition_state, owner, session_id) that the FrameUpdate does not carry.

A client that only needs to render can ignore PreeditUpdate messages and rely solely on FrameUpdate's preedit section.

**Capability interaction**: The FrameUpdate preedit section is always included when preedit is active, regardless of whether the client negotiated `CJK_CAP_PREEDIT`. The `CJK_CAP_PREEDIT` capability controls only the dedicated PreeditStart/Update/End/Sync messages. This means any client can render preedit overlays even without understanding the composition state machine — it simply paints the text at the specified position with an underline.

### 13.2 Message Ordering

For a single composition keystroke, the server sends messages in this order:

```
1. PreeditUpdate (0x0401)    -- state tracking (sent first for observers)
2. FrameUpdate (0x0300)      -- rendering (includes preedit section + any grid changes)
```

The PreeditUpdate is sent before FrameUpdate so that clients can update their internal state before the rendering frame arrives. However, clients MUST NOT depend on this ordering — either message may arrive first due to buffering. Since clients MUST use FrameUpdate for rendering, the protocol is resilient to PreeditUpdate being delayed or dropped.

For composition end:
```
1. PreeditEnd (0x0402)       -- state tracking
2. FrameUpdate (0x0300)      -- rendering (preedit_active=0, grid updated with committed text)
```

---

## 14. Open Questions

1. **Japanese/Chinese composition states**: The `composition_state` enum currently only covers Korean. When Japanese (Kana-to-Kanji) and Chinese (Pinyin) are added, what states are needed? For Japanese: `romaji_input`, `kana_input`, `candidate_selection`. For Chinese: `pinyin_input`, `candidate_selection`. These can be added as new enum values without breaking the protocol.

2. **Candidate window protocol**: Japanese and Chinese IMEs present a candidate list. How should this be forwarded to the client? Options:
   - Embed candidate list in PreeditUpdate (simple but potentially large)
   - Separate CandidateList message with pagination
   - Defer to v2 (current recommendation)

3. **Client-side prediction**: For high-latency connections, should the client perform local Korean composition prediction and display it immediately, then reconcile with the server's authoritative state? This would improve perceived latency but adds significant complexity.

4. **Preedit and selection interaction**: If a user selects text on a pane where preedit is active, should the selection replace the preedit? Current design: selection operations commit the preedit first, then proceed with selection.

5. **Multiple simultaneous compositions**: Should the protocol support preedit on multiple panes simultaneously (one per pane, same client)? Current design: Yes — each pane has independent preedit state. The client switches "active pane" focus, and the server maintains per-pane state machines.

6. **Undo during composition**: Should Cmd+Z during composition undo the last Jamo addition (similar to Backspace)? Or should it be forwarded to the terminal? Current thinking: Backspace handles decomposition; Cmd+Z is forwarded.
