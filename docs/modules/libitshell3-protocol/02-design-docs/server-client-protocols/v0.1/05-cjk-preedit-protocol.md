# 05 — CJK Preedit Sync and IME Protocol

**Status**: Draft v0.1
**Author**: rendering-cjk-specialist
**Date**: 2026-03-04
**Depends on**: 01-message-framing.md, 04-input-and-renderstate.md (FrameUpdate, KeyEvent)

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

```
Client A (active typist)          Server (libitshell3-ime)         Client B (observer)
────────────────────────          ──────────────────────           ────────────────────

KeyEvent(HID keycode)  ─────►    IME Composition Engine
                                       │
                                       ├── Preedit changed?
                                       │     ├── Yes: Update preedit state
                                       │     │         │
                                       │     │         ├── FrameUpdate (preedit section) ──► Client A
                                       │     │         ├── FrameUpdate (preedit section) ──► Client B
                                       │     │         └── PreeditUpdate (state tracking) ──► Client B
                                       │     │
                                       │     └── No: process normally
                                       │
                                       └── Text committed?
                                             ├── Write to PTY
                                             └── PreeditEnd ──► Client A, Client B
```

**Dual-channel design**: Preedit state is communicated through TWO mechanisms:

1. **FrameUpdate preedit section (0x0300)**: For rendering. Contains the preedit text and cursor position within the terminal frame. This is the primary rendering path — clients use this to draw the preedit overlay.

2. **Dedicated preedit messages (0x0400-0x04FF)**: For state tracking. Contains composition state details (Korean Jamo state, layout info) useful for debugging, multi-client conflict resolution, and session snapshots. Observers (non-typing clients) can use these to display composition state indicators.

### Message Type Range

| Range | Category | Direction |
|-------|----------|-----------|
| `0x0400`-`0x04FF` | CJK/IME messages | Bidirectional |

---

## 2. Preedit Lifecycle Messages

### 2.1 PreeditStart (type = 0x0400)

Sent by the server when a new composition session begins on a pane. This occurs when the first composing keystroke is processed by the IME engine.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      14    [header]            type=0x0400, length=33
14       4    pane_id             Target pane (u32 LE)
18       4    client_id           Client that initiated composition (u32 LE)
22       2    cursor_x            Composition start column (u16 LE)
24       2    cursor_y            Composition start row (u16 LE)
26       2    active_layout_id    Keyboard layout (u16 LE, same IDs as KeyEvent)
28       1    composition_state   Initial state: 0=empty (always 0 for start)
29       4    preedit_session_id  Unique ID for this composition session (u32 LE)
```

**Total with header**: 33 bytes.

The `preedit_session_id` is a monotonically increasing counter per pane. It disambiguates overlapping composition sessions (e.g., one ends and another starts quickly).

### 2.2 PreeditUpdate (type = 0x0401)

Sent by the server each time the composition state changes (keystroke adds/removes a Jamo, composition advances).

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      14    [header]            type=0x0401, length=14+15+N
14       4    pane_id             (u32 LE)
18       4    preedit_session_id  Matches PreeditStart (u32 LE)
22       2    cursor_x            Current preedit cursor column (u16 LE)
24       2    cursor_y            Current preedit cursor row (u16 LE)
26       1    composition_state   Current state enum (u8, see Section 3)
27       1    display_width       Width of preedit text in cells (u8)
28       1    preedit_text_len    Length of preedit text in bytes (u8)
29       N    preedit_text        UTF-8 encoded preedit string
```

**Typical size**: 29 + 3 (single Korean syllable UTF-8) = **32 bytes**.

**Note**: `display_width` is the visual width in terminal cells, which may differ from the byte length or codepoint count. A single Hangul syllable is 2 cells wide. The client uses this for overlay positioning.

### 2.3 PreeditEnd (type = 0x0402)

Sent when composition ends, either by committing text or cancelling.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      14    [header]            type=0x0402, length=14+11+N
14       4    pane_id             (u32 LE)
18       4    preedit_session_id  Matches PreeditStart (u32 LE)
22       1    reason              0=committed, 1=cancelled, 2=pane_closed,
                                  3=client_disconnected, 4=replaced_by_other_client
23       2    committed_text_len  Length of committed text (u16 LE, 0 if cancelled)
25       N    committed_text      UTF-8 committed text (absent if cancelled)
```

**Committed text** is the final text written to the PTY. For Korean: if the user composed "한" and pressed Space, committed_text="한".

**Cancel reasons**:
- `0=committed`: Normal completion (Space, Enter, non-Jamo key)
- `1=cancelled`: User pressed Escape during composition
- `2=pane_closed`: Pane was closed while composition was active
- `3=client_disconnected`: The composing client disconnected
- `4=replaced_by_other_client`: Another client started composing on the same pane

### 2.4 PreeditSync (type = 0x0403)

Server -> specific client. Sent when a client attaches to a pane that has an active composition session (e.g., a second client connects while Client A is mid-composition).

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      14    [header]            type=0x0403, length=14+17+N
14       4    pane_id             (u32 LE)
18       4    preedit_session_id  Current session ID (u32 LE)
22       4    preedit_owner       Client ID that owns the composition (u32 LE)
26       2    cursor_x            (u16 LE)
28       2    cursor_y            (u16 LE)
30       1    composition_state   Current state (u8)
31       2    active_layout_id    (u16 LE)
33       1    display_width       (u8)
34       1    preedit_text_len    (u8)
35       N    preedit_text        UTF-8 preedit string
```

This is essentially a snapshot of the current preedit state for late-joining clients.

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

**Wire trace** (server sends to all clients):

```
1. PreeditUpdate: pane=1, state=syllable_no_tail, text="하", width=2
   + FrameUpdate: preedit section with text="하"

2. PreeditUpdate: pane=1, state=leading_jamo, text="ㅎ", width=1
   + FrameUpdate: preedit section with text="ㅎ"

3. PreeditEnd: pane=1, reason=cancelled, committed_text=""
   + FrameUpdate: preedit section with active=0
```

Note: Backspace during `leading_jamo` produces a PreeditEnd with `reason=1 (cancelled)` and empty committed text, because the composition was fully undone without committing anything.

---

## 4. Input Method Switching

### 4.1 InputMethodSwitch (type = 0x0404)

Client -> server. The client requests switching the active keyboard layout for a pane.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      14    [header]            type=0x0404, length=24
14       4    pane_id             Target pane (u32 LE)
18       2    layout_id           New layout ID (u16 LE)
20       1    flags               Bit 0: commit_current (if 1, commit active preedit before switching)
                                  Bit 1: per_pane (if 1, only this pane; if 0, all panes in session)
21       3    reserved            Must be 0
```

**Server behavior**:
1. If `commit_current=1` and preedit is active, commit current preedit text to PTY
2. If `commit_current=0` and preedit is active, cancel current preedit (PreeditEnd with reason=cancelled)
3. Update the pane's (or session's) active layout
4. Send InputMethodAck to the requesting client
5. If `per_pane=0`, broadcast layout change to all panes in the session

### 4.2 InputMethodAck (type = 0x0405)

Server -> client. Confirms the layout switch.

```
Offset  Size  Field               Description
──────  ────  ─────               ───────────
 0      14    [header]            type=0x0405, length=22
14       4    pane_id             (u32 LE)
18       2    active_layout_id    The now-active layout (u16 LE)
20       2    previous_layout_id  The previously active layout (u16 LE)
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
 0      14    [header]            type=0x0406, length=20
14       4    pane_id             Target pane (u32 LE), 0xFFFFFFFF = all panes
18       1    ambiguous_width     1 = single-width (Western default)
                                  2 = double-width (East Asian default)
19       1    scope               0 = per-pane, 1 = per-session, 2 = global
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

The client renders preedit using the `preedit` section from FrameUpdate (see Doc 04, Section 4.5). The rendering approach:

1. Draw the terminal grid normally (all cells from DirtyRows)
2. At position `(preedit_cursor_x, preedit_cursor_y)`, overlay the preedit text:
   - Background: slightly different from the terminal background (e.g., lighter/darker by 10%)
   - Text: same font as terminal text, with underline decoration
   - Width: use `display_width` from PreeditUpdate for cell count

```
Terminal Grid (normal rendering):
┌──────────────────────────────────────────────┐
│ $ echo "hello"                               │
│ hello                                        │
│ $ █                                          │  ← cursor at (2, 2)
│                                              │
└──────────────────────────────────────────────┘

With Korean preedit "한" at cursor:
┌──────────────────────────────────────────────┐
│ $ echo "hello"                               │
│ hello                                        │
│ $ 한█                                        │  ← preedit overlay (2 cells wide)
│  ──                                          │  ← underline decoration
└──────────────────────────────────────────────┘
```

### 9.2 Preedit for Observer Clients

Non-owner clients (observers) also render the preedit overlay. They additionally MAY display an indicator showing which client is composing:

```
┌──────────────────────────────────────────────┐
│ $ 한█                                        │
│  ── [Client A composing]                     │  ← optional indicator
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
 0      14    [header]            type=0x04FF, length=14+8+N
14       4    pane_id             Related pane (u32 LE)
18       2    error_code          Error identifier (u16 LE)
20       2    detail_len          Length of error detail (u16 LE)
22       N    detail              UTF-8 error description
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
| `0x0400` | PreeditStart | S -> C | 33 B | New composition session begins |
| `0x0401` | PreeditUpdate | S -> C | ~32 B | Composition state changed |
| `0x0402` | PreeditEnd | S -> C | ~27 B | Composition session ended |
| `0x0403` | PreeditSync | S -> C | ~35 B | Full preedit snapshot for late-joining client |
| `0x0404` | InputMethodSwitch | C -> S | 24 B | Request keyboard layout change |
| `0x0405` | InputMethodAck | S -> C | 22 B | Confirm layout change |
| `0x0406` | AmbiguousWidthConfig | Bi | 20 B | Set ambiguous character width |
| `0x04FF` | IMEError | S -> C | ~24 B | Error response |

---

## 12. Bandwidth Analysis for Preedit

### 12.1 Korean Composition Bandwidth

Typing Korean at ~60 WPM (words per minute), approximately 5 syllables/second. Each syllable requires ~3 keystrokes (consonant + vowel + tail consonant), generating ~3 PreeditUpdate messages.

| Message | Size | Per-second | Bandwidth |
|---------|------|------------|-----------|
| PreeditUpdate | ~32 B | ~15/s | 480 B/s |
| FrameUpdate (preedit section) | ~80 B | ~15/s | 1.2 KB/s |
| PreeditEnd (commit) | ~27 B | ~5/s | 135 B/s |
| **Total preedit overhead** | | | **~1.8 KB/s** |

This is negligible compared to the overall FrameUpdate bandwidth (~10 KB/s typical).

### 12.2 Multi-Client Overhead

With N clients attached, preedit messages are sent to each client:
- 2 clients: ~3.6 KB/s preedit overhead
- 5 clients: ~9.0 KB/s preedit overhead
- 10 clients: ~18 KB/s preedit overhead

All well within Unix socket capacity.

---

## 13. Integration with FrameUpdate

### 13.1 Preedit in FrameUpdate vs. Dedicated Messages

Both mechanisms are used because they serve different purposes:

| Mechanism | Purpose | Consumer |
|-----------|---------|----------|
| FrameUpdate preedit section | **Rendering**: Where to draw the preedit overlay | Rendering pipeline |
| PreeditStart/Update/End | **State tracking**: Composition details, ownership, conflict resolution | Session manager, debugging, multi-client sync |

A client that only needs to render can ignore PreeditUpdate messages and rely solely on FrameUpdate's preedit section. The dedicated messages add metadata (composition_state, owner, session_id) that the FrameUpdate does not carry.

### 13.2 Message Ordering

For a single composition keystroke, the server sends messages in this order:

```
1. PreeditUpdate (0x0401)    -- state tracking (sent first for observers)
2. FrameUpdate (0x0300)      -- rendering (includes preedit section + any grid changes)
```

The PreeditUpdate is sent before FrameUpdate so that clients can update their internal state before the rendering frame arrives. However, clients MUST NOT depend on this ordering — either message may arrive first due to buffering.

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
