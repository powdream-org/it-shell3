# 05 — CJK Preedit Sync and IME Protocol

**Status**: Draft v0.5
**Author**: rendering-cjk-specialist
**Date**: 2026-03-05
**Depends on**: 01-protocol-overview.md (header format), 04-input-and-renderstate.md (FrameUpdate, KeyEvent)

**Changes from v0.4** (cross-review: Protocol v0.4 x IME Interface Contract v0.3):
- **Issue 6: display_width computation**: Added UAX #11 reference and Korean preedit width rules to Section 2.2.
- **Issue 9: Escape PreeditEnd reason**: Fixed Escape from `"cancelled"` to `"committed"` and clarified `"cancelled"` definition in Section 2.3.
- **Issue 8: commit_current SHOULD recommendation**: Added SHOULD recommendation for `commit_current=true` and server implementation note for `commit_current=false` in Section 4.1.
- **Issue 10: Language identifier mapping**: Added cross-reference table mapping protocol strings to IME contract types in Section 4.1/4.3.
- **Consistency fix: composition_state ko_ prefix**: Updated all composition state string values to use `ko_` prefix (e.g., `"leading_jamo"` -> `"ko_leading_jamo"`) matching IME contract v0.4 CompositionStates constants. Added missing `"ko_vowel_only"` state. Updated cross-references from IME contract v0.3 to v0.4.
- **Input method identifier unification** (identifier consensus): Removed language identifier mapping table from Section 4.3 (previously mapped protocol strings to `LanguageId` enum + `layout_id`). Replaced with normative rule: the canonical `input_method` string flows unchanged to the IME engine constructor; the engine owns the sole translation to engine-internal types. Canonical registry now lives in IME Interface Contract, Section 3.7. Fixed bug: `"korean_3set_390"` was incorrectly mapped to `"3f"` (should be `"39"`).

**Changes from v0.3**:
- **Issue 6: String-based input method identifiers**: Renamed `active_layout_id` to `active_input_method` (string) in PreeditStart, PreeditSync, and InputMethodAck. Updated InputMethodSwitch to use string `input_method` + `keyboard_layout` instead of numeric `layout_id`. Removed all numeric layout ID references.
- **CO-1: Client MUST NOT override cursor style**: Added normative requirement that clients MUST NOT override cursor style based on local preedit state — render whatever the server sends in FrameUpdate.
- **Issue 9/Gap 3: Focus change during composition**: New Section 7.7 covering focus change race condition with PreeditEnd `reason="focus_changed"`. New Section 7.8 covering session detach during composition. New Section 7.9 covering InputMethodSwitch during active preedit with `reason="input_method_changed"`.
- **Issue 9: New PreeditEnd reason values**: Added `"focus_changed"` and `"input_method_changed"` to reason enum.
- **Issue 9: InputMethodAck broadcast**: InputMethodAck is now broadcast to ALL attached clients, not just the requesting client.
- **Issue 9: Readonly client preedit observation**: Added normative note that readonly clients receive all preedit broadcasts as observers.
- **Issue 9/Gap 12: Preedit-only FrameUpdate for paused clients**: Added Section 8.4 defining the format for preedit-bypass FrameUpdates sent to paused clients.
- **Issue 3: JSON optional field convention**: Updated JSON examples to omit absent fields rather than using `null`.

---

## 1. Overview

This document specifies the protocol messages for CJK Input Method Editor (IME) composition state synchronization. The design addresses:

1. **Preedit lifecycle management**: Start, update, end of composition sessions
2. **Multi-client sync**: Broadcasting preedit state to all attached clients
3. **Korean Hangul composition**: The most complex case — Jamo decomposition on backspace
4. **Input method switching**: Per-pane input method state
5. **Race condition handling**: Pane close during composition, client disconnect, concurrent preedit, focus change during composition
6. **Session persistence**: Serializing/restoring preedit state across daemon restart

### Architecture Context

The server owns the native IME engine (libitshell3-ime). The client sends ONLY raw HID keycodes via KeyEvent (doc 04, Section 2.1). The client NEVER sends preedit state or composition information — the server determines all composition state internally from the IME engine.

```
Client A (active typist)          Server (libitshell3-ime)         Client B (observer)
------------------------          ----------------------           --------------------

KeyEvent(HID keycode)  ----->    IME Composition Engine
                                       |
                                       +-- Preedit changed?
                                       |     +-- Yes: Update preedit state
                                       |     |         |
                                       |     |         +-- PreeditUpdate (S->C) ------> Client A
                                       |     |         +-- PreeditUpdate (S->C) ------> Client B
                                       |     |         +-- FrameUpdate (JSON preedit) -> Client A
                                       |     |         +-- FrameUpdate (JSON preedit) -> Client B
                                       |     |
                                       |     +-- No: process normally
                                       |
                                       +-- Text committed?
                                             +-- Write to PTY
                                             +-- PreeditEnd (S->C) ------> Client A
                                             +-- PreeditEnd (S->C) ------> Client B
```

**Dual-channel design**: Preedit state is communicated through TWO mechanisms:

1. **FrameUpdate JSON metadata blob (0x0300)**: For rendering. Contains the preedit text and cursor position as a JSON object within the FrameUpdate's metadata blob. This is the **authoritative rendering source** — clients MUST use this to draw the preedit overlay. The preedit section is always included when preedit is active, regardless of `CJK_CAP_PREEDIT` capability. Example:

   ```json
   {
     "preedit": {
       "active": true,
       "cursor_x": 5,
       "cursor_y": 10,
       "text": "한"
     }
   }
   ```

2. **Dedicated preedit messages (0x0400-0x04FF)**: For state tracking. Contains composition state details (Korean Jamo state, input method info) useful for debugging, multi-client conflict resolution, and session snapshots. Observers (non-typing clients) can use these to display composition state indicators. These messages are sent only to clients that negotiated `CJK_CAP_PREEDIT`.

**Rendering rule**: Clients MUST use FrameUpdate's preedit JSON for rendering, NOT PreeditUpdate's text field. PreeditUpdate provides metadata (composition_state, session_id, owner) for state tracking only.

**Readonly client observation**: Readonly clients (attached with `readonly` flag, see doc 02) receive ALL preedit-related S->C messages (PreeditStart, PreeditUpdate, PreeditEnd, PreeditSync, InputMethodAck) as observers. They render preedit overlays identically to read-write clients. Readonly clients MUST NOT send InputMethodSwitch (0x0404) — the server rejects this with ERR_ACCESS_DENIED (see doc 04, Section 2.8).

### Message Type Range

| Range | Category | Direction |
|-------|----------|-----------|
| `0x0400`-`0x04FF` | CJK/IME messages | See per-message direction below |

---

## 2. Preedit Lifecycle Messages

All preedit lifecycle messages (PreeditStart, PreeditUpdate, PreeditEnd, PreeditSync) flow **S->C** (server to client). The server is the sole authority on composition state.

### 2.1 PreeditStart (type = 0x0400, S->C)

Sent by the server to ALL attached clients when a new composition session begins on a pane. This occurs when the first composing keystroke is processed by the IME engine.

#### JSON Payload

```json
{
  "pane_id": 1,
  "client_id": 7,
  "cursor_x": 5,
  "cursor_y": 10,
  "active_input_method": "korean_2set",
  "composition_state": "empty",
  "preedit_session_id": 42
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `client_id` | u32 | Client that initiated composition (assigned by ServerHello) |
| `cursor_x` | u16 | Composition start column |
| `cursor_y` | u16 | Composition start row |
| `active_input_method` | string | Input method identifier (e.g., `"korean_2set"`, `"direct"`) |
| `composition_state` | string | Initial state (always `"empty"` for start) |
| `preedit_session_id` | u32 | Unique ID for this composition session |

The `preedit_session_id` is a monotonically increasing counter per pane. It disambiguates overlapping composition sessions (e.g., one ends and another starts quickly).

### 2.2 PreeditUpdate (type = 0x0401, S->C)

Sent by the server to ALL attached clients each time the composition state changes (keystroke adds/removes a Jamo, composition advances).

#### JSON Payload

```json
{
  "pane_id": 1,
  "preedit_session_id": 42,
  "cursor_x": 5,
  "cursor_y": 10,
  "composition_state": "ko_syllable_with_tail",
  "display_width": 2,
  "text": "한"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `preedit_session_id` | u32 | Matches PreeditStart |
| `cursor_x` | u16 | Current preedit cursor column |
| `cursor_y` | u16 | Current preedit cursor row |
| `composition_state` | string | Current state enum (see Section 3) |
| `display_width` | u8 | Width of preedit text in cells |
| `text` | string | UTF-8 encoded preedit string |

**Note**: `display_width` is the visual width in terminal cells, which may differ from the byte length or codepoint count. A single Hangul syllable is 2 cells wide. The client uses this for overlay positioning.

**display_width computation**: The server computes `display_width` from the preedit text using the Unicode East Asian Width property (UAX #11). For Korean Hangul preedit text produced by libhangul, the value is always 2:

- Precomposed Hangul syllables (U+AC00-U+D7A3): East Asian Width = W = 2 cells
- Compatibility Jamo (U+3131-U+318E): East Asian Width = W = 2 cells

libhangul always outputs precomposed or compatibility forms for preedit text, so conjoining Jamo edge cases (U+1100-U+11FF, where width varies) do not arise in practice. For future CJK languages, the server applies UAX #11 to the preedit text codepoints.

### 2.3 PreeditEnd (type = 0x0402, S->C)

Sent by the server to ALL attached clients when composition ends, either by committing text or cancelling.

#### JSON Payload

```json
{
  "pane_id": 1,
  "preedit_session_id": 42,
  "reason": "committed",
  "committed_text": "한"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `preedit_session_id` | u32 | Matches PreeditStart |
| `reason` | string | End reason (see below) |
| `committed_text` | string | UTF-8 committed text (empty string if cancelled) |

**Committed text** is the final text written to the PTY. For Korean: if the user composed "한" and pressed Space, committed_text="한".

**Reason values**:
- `"committed"`: Normal completion (Space, Enter, non-Jamo key, **Escape**, modifier flush)
- `"cancelled"`: Composition discarded without committing (backspace-to-empty, explicit reset, `commit_current=false` on InputMethodSwitch)
- `"pane_closed"`: Pane was closed while composition was active
- `"client_disconnected"`: The composing client disconnected
- `"replaced_by_other_client"`: Another client started composing on the same pane
- `"focus_changed"`: Focus changed to a different pane during composition (see Section 7.7)
- `"input_method_changed"`: Input method was switched during composition (see Section 7.9)

**Note on Escape**: Escape causes the IME to flush (commit) the preedit text, then forwards the Escape key to the terminal. This matches ibus-hangul and fcitx5-hangul behavior. The PreeditEnd reason is `"committed"`, not `"cancelled"`. libitshell3 uses native IME (not OS IME), so the macOS NSTextInputClient convention of "Escape cancels composition" does not apply.

### 2.4 PreeditSync (type = 0x0403, S->C)

Server -> specific client. Sent when a client attaches to a pane that has an active composition session (e.g., a second client connects while Client A is mid-composition). This is a full state snapshot — self-contained, unlike PreeditUpdate which assumes the client has PreeditStart context.

#### JSON Payload

```json
{
  "pane_id": 1,
  "preedit_session_id": 42,
  "preedit_owner": 7,
  "cursor_x": 5,
  "cursor_y": 10,
  "composition_state": "ko_syllable_with_tail",
  "active_input_method": "korean_2set",
  "display_width": 2,
  "text": "한"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `preedit_session_id` | u32 | Current session ID |
| `preedit_owner` | u32 | Client ID that owns the composition |
| `cursor_x` | u16 | Preedit cursor column |
| `cursor_y` | u16 | Preedit cursor row |
| `composition_state` | string | Current state (see Section 3) |
| `active_input_method` | string | Input method identifier |
| `display_width` | u8 | Width of preedit text in cells |
| `text` | string | UTF-8 preedit string |

This is essentially a snapshot of the current preedit state for late-joining clients. It carries additional fields (`preedit_owner`, `active_input_method`) that are redundant in the normal PreeditUpdate flow but essential for initial sync.

---

## 3. Korean Composition State Machine

### 3.1 State Enum

The `composition_state` field is a string encoding the current Korean Hangul composition state:

| Value | Description |
|-------|-------------|
| `"empty"` | No composition active (initial/terminal state) |
| `"ko_leading_jamo"` | Single consonant: ㅎ, ㄴ, ㄱ, ... |
| `"ko_vowel_only"` | Standalone vowel: ㅏ, ㅓ, ㅗ, ... (with implicit ㅇ leading) |
| `"ko_syllable_no_tail"` | Consonant + vowel: 하, 나, 가, ... |
| `"ko_syllable_with_tail"` | Full syllable (C+V+C): 한, 난, 간, ... |
| `"ko_double_tail"` | Syllable with double final consonant: 읽 (ㅇ+ㅣ+ㄹㄱ) |
| `"non_korean"` | Non-Korean composition (future: Japanese, Chinese) |

### 3.2 State Transition Diagram

```
                    +---------------------------------------------+
                    |                                             |
                    |   +--------------------------------------+ |
                    |   |  non-jamo key / Space / Enter         | |
                    |   |  (commit current + pass through)      | |
                    |   |                                       | |
                    v   |                                       | |
              +--------+--+                                    | |
              |            |                                    | |
 consonant    |   empty    |<---- backspace                    | |
  -------->   |   (0x00)   |      (from ko_leading_jamo)          | |
              |            |                                    | |
              +-----+------+                                    | |
                    | consonant                                 | |
                    v                                           | |
              +------------+                                    | |
              |  leading    |---- non-jamo -------------------+ | |
  vowel       |  _jamo     |     (commit consonant + pass)     | |
  -------->   |  (0x01)    |                                    | |
              |  e.g., H   |<---- backspace                    | |
              +-----+------+      (from ko_syllable_no_tail)       | |
                    | vowel                                      | |
                    v                                            | |
              +------------+                                    | |
              |  syllable   |---- non-jamo ---------------------+ |
  consonant   |  _no_tail  |     (commit syllable + pass)        |
  -------->   |  (0x02)    |                                     |
              |  e.g., HA  |<---- backspace                     |
              +-----+------+      (from ko_syllable_with_tail)      |
                    | consonant                                   |
                    v                                             |
              +------------+                                     |
              |  syllable   |---- non-jamo ----------------------+
              |  _with_tail |     (commit syllable + pass)
              |  (0x03)    |
              |  e.g., HAN |
              +-----+------+
                    |
                    | vowel (Jamo reassignment)
                    | Split tail consonant: HAN + A -> commit HA,
                    |   new ko_syllable_no_tail NA
                    v
              +------------+
              |  syllable   |
              |  _no_tail  |<-----------------------------------+
              |  (0x02)    |
              |  (new)     |
              +------------+
```

### 3.3 Complete Transition Table

| Current State | Input | Next State | Preedit | Commit | Notes |
|---------------|-------|------------|---------|--------|-------|
| empty | consonant | ko_leading_jamo | "ㅎ" | -- | Begin composition |
| empty | vowel | ko_syllable_no_tail | "ㅇ+V" | -- | Implicit ㅇ leading (Korean convention) |
| empty | non-jamo | empty | -- | passthrough | Not a Korean character |
| ko_leading_jamo | vowel | ko_syllable_no_tail | "하" | -- | Form syllable |
| ko_leading_jamo | consonant | ko_leading_jamo | "ㄴ" | "ㅎ" | Commit previous, start new |
| ko_leading_jamo | non-jamo | empty | -- | "ㅎ" + passthrough | Commit consonant |
| ko_leading_jamo | backspace | empty | -- | -- | Remove consonant |
| ko_syllable_no_tail | consonant | ko_syllable_with_tail | "한" | -- | Add tail consonant |
| ko_syllable_no_tail | vowel | ko_syllable_no_tail | "해" | -- | Replace vowel (only certain transitions) |
| ko_syllable_no_tail | non-jamo | empty | -- | "하" + passthrough | Commit syllable |
| ko_syllable_no_tail | backspace | ko_leading_jamo | "ㅎ" | -- | Remove vowel |
| ko_syllable_with_tail | vowel | ko_syllable_no_tail | "나" | "하" | Jamo reassignment |
| ko_syllable_with_tail | consonant | ko_syllable_with_tail | "핝" | -- | Form double-tail (if valid) OR commit + new leading |
| ko_syllable_with_tail | non-jamo | empty | -- | "한" + passthrough | Commit syllable |
| ko_syllable_with_tail | backspace | ko_syllable_no_tail | "하" | -- | Remove tail consonant |
| ko_double_tail | vowel | ko_syllable_no_tail | "가" | "읽" | Split: commit base, new syllable with split consonant |
| ko_double_tail | backspace | ko_syllable_with_tail | "읽->일" | -- | Remove second tail consonant |

### 3.4 Backspace Decomposition Trace

Korean backspace is NOT "delete previous character" — it decomposes the composition step by step:

```
State              Preedit  Composition State      Backspace Result
-----              -------  -----------------      ----------------
한 (0xD55C)        "한"     ko_syllable_with_tail     -> "하" (remove ㄴ)
하 (0xD558)        "하"     ko_syllable_no_tail       -> "ㅎ" (remove ㅏ)
ㅎ (0x314E)        "ㅎ"     ko_leading_jamo           -> "" (clear, end composition)
```

**Cursor behavior during decomposition**: The cursor position remains at `preedit.cursor_x` throughout decomposition. The block cursor width follows the composing character's `display_width`: 2 cells for a Hangul syllable (하, 한), 1 cell for a standalone Jamo (ㅎ). The server updates `display_width` in both the FrameUpdate JSON preedit section and PreeditUpdate accordingly.

**Wire trace** (server sends to all clients):

```
1. PreeditUpdate: pane=1, state=ko_syllable_no_tail, text="하", width=2
   + FrameUpdate: JSON preedit {"active":true,"cursor_x":5,"cursor_y":10,"text":"하"}
     cursor: style=block (2 cells)

2. PreeditUpdate: pane=1, state=ko_leading_jamo, text="ㅎ", width=1
   + FrameUpdate: JSON preedit {"active":true,"cursor_x":5,"cursor_y":10,"text":"ㅎ"}
     cursor: style=block (1 cell)

3. PreeditEnd: pane=1, reason=cancelled, committed_text=""
   + FrameUpdate: JSON preedit {"active":false}
     cursor: style restored to pre-composition value
```

Note: Backspace during `ko_leading_jamo` produces a PreeditEnd with `reason="cancelled"` and empty committed text, because the composition was fully undone without committing anything.

---

## 4. Input Method Switching

### 4.1 InputMethodSwitch (type = 0x0404, C->S)

Client -> server. The client requests switching the active input method for a pane.

#### JSON Payload

```json
{
  "pane_id": 1,
  "input_method": "korean_2set",
  "keyboard_layout": "qwerty",
  "commit_current": true,
  "per_pane": true
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `input_method` | string | New input method identifier (e.g., `"direct"`, `"korean_2set"`) |
| `keyboard_layout` | string | Keyboard layout (optional; omit = keep current, default `"qwerty"` in v1) |
| `commit_current` | bool | If true, commit active preedit before switching; if false, cancel it |
| `per_pane` | bool | If true, only this pane; if false, all panes in session |

**Server behavior**:
1. If `commit_current=true` and preedit is active, commit current preedit text to PTY
2. If `commit_current=false` and preedit is active, cancel current preedit (PreeditEnd with `reason="cancelled"`)
3. Update the pane's (or session's) active input method and keyboard layout
4. Send InputMethodAck to ALL attached clients (broadcast)
5. If `per_pane=false`, broadcast input method change to all panes in the session

**Server-side hotkey detection**: In addition to the explicit InputMethodSwitch message, the server detects configurable mode-switch hotkeys (e.g., Right-Alt, Ctrl+Space) from raw KeyEvent and handles input method switching internally. Both paths produce InputMethodAck (0x0405) broadcast to all attached clients.

**SHOULD recommendation**: Clients SHOULD default to `commit_current=true` for InputMethodSwitch. The `commit_current=false` option is non-standard — no widely-used Korean IME framework discards composition on language switch. This option exists for future CJK language support where cancel-on-switch may be appropriate.

**Server implementation**:
- `commit_current=true`: Server calls `setActiveInputMethod(new_method)`. The IME flushes (commits) pending composition and switches. This is the standard behavior.
- `commit_current=false`: Server calls `reset()` to discard the current composition, then `setActiveInputMethod(new_method)` to switch. The server MUST hold the per-pane lock across both calls to ensure atomicity. The PreeditEnd reason is `"cancelled"`.

### 4.2 InputMethodAck (type = 0x0405, S->C)

Server -> ALL attached clients (broadcast). Confirms the input method switch and provides incremental state update. Together with LayoutChanged leaf node data (see doc 03), this forms the two-channel input method state model.

#### JSON Payload

```json
{
  "pane_id": 1,
  "active_input_method": "korean_2set",
  "previous_input_method": "direct",
  "active_keyboard_layout": "qwerty"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane |
| `active_input_method` | string | The now-active input method |
| `previous_input_method` | string | The previously active input method |
| `active_keyboard_layout` | string | The now-active keyboard layout |

**Broadcast semantics**: InputMethodAck is sent to ALL clients attached to the session, not just the client that requested the switch. This enables all clients to update their per-pane input method state consistently. Combined with `active_input_method` in LayoutChanged leaf nodes (doc 03), clients maintain per-pane input method state through two channels:

1. **LayoutChanged** (0x0180): Authoritative full state on attach and structural changes
2. **InputMethodAck** (0x0405): Incremental updates on input method switches

### 4.3 Per-Pane Input Method State

Each pane independently tracks its active input method. This allows users to have:
- Pane 1: Korean input for a Korean document
- Pane 2: English input for code
- Pane 3: Japanese input for another document

Input method state is stored in the server's pane metadata and included in session snapshots.

**Default for new panes**: `input_method: "direct"`, `keyboard_layout: "qwerty"`. This is a normative requirement — servers MUST initialize new panes with these defaults.

**Input method identifiers**: The protocol uses a single canonical string identifier for input methods (e.g., `"direct"`, `"korean_2set"`, `"korean_3set_390"`). This string is the ONLY representation that crosses component boundaries — it flows unchanged from client to server to IME engine constructor. The `keyboard_layout` field (e.g., `"qwerty"`, `"azerty"`) is a separate, orthogonal per-pane property and is NOT encoded in the `input_method` string.

The canonical registry of valid `input_method` strings and their engine-native mappings is defined in the IME Interface Contract, Section 3.7 (HangulImeEngine). The protocol does not maintain a separate mapping table — the IME engine constructor is the sole translation point between protocol strings and engine-internal types.

---

## 5. Ambiguous Width Configuration

### 5.1 AmbiguousWidthConfig (type = 0x0406)

Client -> server (or server -> client during handshake). Configures how ambiguous-width Unicode characters are measured.

#### JSON Payload

```json
{
  "pane_id": 1,
  "ambiguous_width": 2,
  "scope": "per_pane"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Target pane (`4294967295` for all panes) |
| `ambiguous_width` | u8 | `1` = single-width (Western default), `2` = double-width (East Asian default) |
| `scope` | string | `"per_pane"`, `"per_session"`, or `"global"` |

**Affected characters**: Unicode characters with East Asian Width property "A" (Ambiguous):
- Box drawing (-- | etc.)
- Greek letters (alpha beta gamma delta)
- Cyrillic letters
- Various symbols (degree, plus-minus, multiply, divide, etc.)

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
    input_method: []u8,       // active input method identifier string
}
```

### 6.3 Ownership Rules

**Last-Writer-Wins** with explicit takeover notification:

1. **First composer**: When Client A sends a KeyEvent that triggers composition on a pane with no active preedit, Client A becomes the preedit owner.

2. **Concurrent attempt**: When Client B sends a composing KeyEvent on the same pane while Client A owns the preedit:
   - Server commits Client A's current preedit text to PTY
   - Server sends PreeditEnd to all clients with `reason="replaced_by_other_client"`
   - Server starts a new composition session owned by Client B
   - Server sends PreeditStart to all clients with Client B as owner

3. **Owner disconnect**: When the preedit owner disconnects:
   - Server commits current preedit text to PTY (if any)
   - Server sends PreeditEnd with `reason="client_disconnected"`

4. **Non-composing input from non-owner**: Regular (non-composing) KeyEvents from any client are always processed normally, regardless of preedit ownership. If a non-owner sends a regular key, the owner's preedit is committed first.

### 6.4 Conflict Resolution Sequence Diagram

```
Client A                Server                  Client B
--------                ------                  --------
KeyEvent(H) ------>    Preedit owner = A
                        PreeditStart(owner=A) ------------> (display indicator)
                        PreeditUpdate("ㅎ") ---------------->
                        FrameUpdate(JSON preedit) ---------->
<-- FrameUpdate(JSON preedit)

                        ... Client A composing ...

                        KeyEvent(A) <-------- Client B starts typing

                        [Conflict! Commit A's preedit]
                        Write "ㅎ" to PTY
                        PreeditEnd(reason=replaced) -------->
<-- PreeditEnd(reason=replaced)

                        [New session for B]
                        Preedit owner = B
                        PreeditStart(owner=B) -------------->
<-- PreeditStart(owner=B)
                        PreeditUpdate("ㅏ") ---------------->
<-- PreeditUpdate("ㅏ")
```

---

## 7. Race Condition Handling

### 7.1 Pane Close During Composition

**Scenario**: User closes a pane while Korean composition is active.

**Server behavior**:
1. Cancel the active composition (do NOT commit to PTY — the PTY is being closed)
2. Send PreeditEnd with `reason="pane_closed"` to all clients
3. Proceed with pane close sequence

**Wire trace**:
```
Server -> all clients: PreeditEnd(pane=X, reason=pane_closed, committed="")
Server -> all clients: PaneClose(pane=X)  // from session management protocol
```

### 7.2 Client Disconnect During Composition

**Scenario**: The composing client's connection drops (network failure, crash).

**Server behavior**:
1. Detect disconnect (socket read returns 0 or error)
2. Commit current preedit text to PTY (best-effort: preserve the user's work)
3. Send PreeditEnd with `reason="client_disconnected"` to remaining clients
4. Clear preedit ownership

**Timeout**: If the server receives no input from the preedit owner for 30 seconds, it commits the current preedit and ends the session. This handles cases where the client is frozen but the socket is still open.

### 7.3 Concurrent Preedit and Resize

**Scenario**: The terminal is resized while composition is active.

**Server behavior**:
1. Process the resize through libghostty-vt Terminal
2. Recalculate preedit cursor position (the cursor row/column may have changed due to reflow)
3. Send FrameUpdate with `dirty=full` (includes updated JSON preedit section with new coordinates)
4. Send PreeditUpdate with updated cursor coordinates

The server MUST send FrameUpdate before PreeditUpdate when both are triggered by the same resize event. This ensures the client has the updated cell grid dimensions before repositioning the preedit overlay. However, since clients MUST use FrameUpdate's JSON preedit section for rendering (not PreeditUpdate), the protocol is resilient to PreeditUpdate arriving late or being dropped.

The preedit text itself is not affected by resize — only its display position changes.

### 7.4 Screen Switch During Composition

**Scenario**: An application switches from primary to alternate screen (e.g., `vim` launches) while composition is active.

**Server behavior**:
1. Commit current preedit text to PTY before the screen switch
2. Send PreeditEnd with `reason="committed"`
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
- Server sends ONE PreeditUpdate with state=ko_syllable_with_tail, text="한"
- Server sends ONE FrameUpdate with JSON preedit `{"active":true,"cursor_x":5,"cursor_y":10,"text":"한"}`

Intermediate states (ㅎ, 하) are not transmitted because they were superseded within the same frame interval.

### 7.6 Layout Query After Reconnection

When a client reconnects or a new client attaches, it can query the current layout tree via `LayoutGetRequest` (doc 03). The layout response includes per-pane `preedit_active`, `active_input_method`, and `active_keyboard_layout` fields in the leaf node metadata. For panes with active composition, the server additionally sends `PreeditSync` (0x0403) with the full preedit state snapshot.

### 7.7 Focus Change During Composition

**Scenario**: Client B sends FocusPaneRequest while Client A is composing Korean on the currently focused pane.

**Server behavior**:
1. Commit Client A's current preedit text to PTY (preserve the user's work)
2. Send PreeditEnd with `reason="focus_changed"` to all clients
3. Clear preedit ownership on the old pane
4. Process the focus change
5. Send LayoutChanged to all clients (reflecting the new focused pane)

**Wire trace**:
```
Client B                Server                  Client A
--------                ------                  --------
FocusPaneRequest -----> [Preedit active on pane 1]

                        [Commit preedit first]
                        Write "ㅎ" to PTY
                        PreeditEnd(pane=1, reason=focus_changed) --> Client A
                        PreeditEnd(pane=1, reason=focus_changed) --> Client B

                        [Process focus change]
                        LayoutChanged(focused_pane=2) ------------> Client A
                        LayoutChanged(focused_pane=2) ------------> Client B
```

This is consistent with all other preedit-interrupting events (screen switch in S7.4, pane close in S7.1). The preedit is always committed or cancelled before processing the interrupting action.

### 7.8 Session Detach During Composition

**Scenario**: The composing client sends DetachSessionRequest while composition is active.

**Server behavior**:
1. Commit current preedit text to PTY (preserve the user's work)
2. Send PreeditEnd with `reason="client_disconnected"` to remaining clients
3. Clear preedit ownership
4. Process the session detach normally

The `"client_disconnected"` reason is reused here because from the remaining clients' perspective, the effect is identical — the composing client is no longer attached.

### 7.9 InputMethodSwitch During Active Preedit

**Scenario**: A client sends InputMethodSwitch (0x0404) on a pane that has active composition.

**Server behavior**:
1. If `commit_current=true`: Commit current preedit text to PTY
2. If `commit_current=false`: Cancel current preedit (no commit)
3. Send PreeditEnd with `reason="input_method_changed"` to all clients
4. Switch the pane's input method
5. Send InputMethodAck to all attached clients

**Wire trace** (commit_current=true):
```
Client A                Server                  Client B
--------                ------                  --------
InputMethodSwitch(
  pane=1,
  input_method="direct",
  commit_current=true) ->
                        [Preedit active: "한"]
                        Write "한" to PTY
                        PreeditEnd(pane=1, reason=input_method_changed,
                                   committed_text="한") --------> Client A
                        PreeditEnd(pane=1, reason=input_method_changed,
                                   committed_text="한") --------> Client B
                        InputMethodAck(pane=1,
                          active_input_method="direct",
                          previous_input_method="korean_2set") -> Client A
                        InputMethodAck(pane=1, ...) -----------> Client B
```

**Note**: The server-side hotkey detection path (e.g., Right-Alt detected from KeyEvent) follows the same sequence. The `commit_current` behavior for hotkey-triggered switches is implementation-defined (recommended: `commit_current=true` as default).

---

## 8. Preedit Coalescing and Latency Requirements

### 8.1 4-Tier Adaptive Cadence Model

The server uses a 4-tier adaptive coalescing model for FrameUpdate delivery. Preedit is the highest-priority tier:

| Tier | Condition | Frame interval |
|------|-----------|----------------|
| **Preedit** | Active composition + keystroke | **Immediate (0ms)** |
| **Interactive** | PTY output <1KB/s + recent keystroke | Immediate (0ms) |
| **Active** | PTY 1-100 KB/s | 16ms (display Hz) |
| **Bulk** | PTY >100KB/s sustained 500ms | 33ms |
| **Idle** | No output 500ms | No frames sent |

### 8.2 Preedit Tier Rules (Normative)

The following rules are normative (MUST):

1. **Immediate flush on preedit state change**: When the preedit state changes (PreeditStart, PreeditUpdate, PreeditEnd), the server MUST flush the FrameUpdate immediately, regardless of the current coalescing tier. The preedit tier overrides all other tiers.

2. **Preedit bypasses PausePane**: Preedit-only frames (~90 bytes) MUST be exempt from PausePane flow control. Even when a pane is paused due to backpressure from a slow client, preedit FrameUpdates MUST still be delivered. The cost (~90 bytes/frame) is negligible compared to the user-perceived latency harm of dropping preedit frames.

3. **Preedit bypasses power throttling**: When the client reports `power_state` indicating battery/low-power mode via `ClientDisplayInfo`, the server reduces frame rates for Active and Bulk tiers (e.g., cap Active at 20fps, Bulk at 10fps). However, preedit FrameUpdates MUST always be delivered immediately regardless of `power_state`. Composition latency is a user-facing interaction that must never be degraded.

4. **Preedit latency target**: The end-to-end latency from KeyEvent receipt to FrameUpdate delivery MUST be less than **33ms** over a Unix domain socket. This is a normative requirement. The 33ms budget covers: KeyEvent read (~0ms) + IME processing (~0.1ms) + preedit state update (~0.1ms) + FrameUpdate serialization (~0.1ms) + socket write (~0ms) = ~0.3ms typical, with 32.7ms margin for scheduling jitter. Over SSH tunnel or other network transport, the server adds no additional delay; end-to-end latency is dominated by network RTT.

5. **Per-pane preedit cadence**: Coalescing tiers are tracked per (client, pane) pair. A pane with active composition runs at Preedit tier even if adjacent panes in the same session are in Bulk tier. The preedit tier applies only to the specific pane where composition is active; other panes continue at their current tier.

### 8.3 Tier Transition Thresholds

| Transition | Threshold | Hysteresis |
|-----------|-----------|------------|
| Idle -> Interactive | KeyEvent + PTY output within 5ms | None |
| Idle -> Active | PTY output without recent keystroke | None |
| Active -> Bulk | >100KB/s for 500ms | Drop back at <50KB/s for 1s |
| Active -> Idle | No output for 500ms | None |
| Any -> Preedit | Preedit state changed | 200ms timeout back to previous tier |

When preedit ends (PreeditEnd), the pane reverts to the tier it would have been in based on PTY throughput. The 200ms timeout allows a brief window for the user to start a new composition without tier oscillation.

### 8.4 Preedit-Only FrameUpdate for Paused Clients

When a pane is paused (PausePane flow control active) for a specific client, preedit state changes still bypass the pause (Rule 2 above). The preedit-bypass FrameUpdate uses a minimal format:

```json
{
  "preedit": {
    "active": true,
    "cursor_x": 5,
    "cursor_y": 10,
    "text": "한"
  }
}
```

**Wire format**: The FrameUpdate has `dirty_row_count=0` (section_flags bit 4 NOT set) with only the JSON metadata blob (section_flags bit 7 set) containing the preedit section. No grid cell data is included. This allows the client to update the preedit overlay without receiving full terminal grid state.

**Typical size**: 16 (header) + 20 (frame header) + 4 (json_len) + ~70 (JSON preedit) = **~110 bytes**.

**Edge case — preedit commit while paused**: When the composing user commits text (PreeditEnd with `reason="committed"`), the grid changes (committed character written to terminal) are NOT delivered to the paused client. The paused client receives:
1. PreeditEnd (state tracking) — always delivered
2. FrameUpdate with `preedit.active=false` and `dirty_row_count=0` — preedit overlay cleared

The actual grid update (committed character visible in terminal cells) is delivered when the client sends ContinuePane. The client will see the committed character appear in the grid at that point.

---

## 9. Preedit in Session Snapshots

### 9.1 Snapshot Format

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
        "composition_state": "ko_syllable_with_tail",
        "preedit_text": "한",
        "cursor_x": 15,
        "cursor_y": 3,
        "input_method": "korean_2set"
      }
    }
  ]
}
```

### 9.2 Restore Behavior

When the daemon restarts and restores a session:

1. **Preedit was active**: The preedit text is committed to the PTY. The composition session is not resumed.
   - **Rationale**: The client that was composing is no longer connected after a daemon restart. Resuming a partial composition would be confusing — the user would see a half-composed character with no way to continue it (since the original client's keyboard state is lost).

2. **Input method state**: Per-pane input method identifiers are restored. When a client reconnects, it receives the pane's saved input method via LayoutChanged leaf nodes and PreeditSync (if applicable).

### 9.3 Alternative: Resume Composition (Future)

A future enhancement could allow composition resumption:
1. Server sends PreeditSync to the reconnecting client with the saved state
2. Client displays the preedit overlay
3. User can continue typing to advance the composition or press Backspace to decompose

This requires the client to initialize its composition state from the server's snapshot, which is feasible for Korean (the state machine is simple) but complex for Japanese/Chinese (candidate lists would need to be regenerated).

**Decision**: For v1, commit-on-restore. Defer resume-on-restore to v2.

---

## 10. Preedit Rendering Protocol

### 10.1 Client Rendering Responsibilities

The client renders preedit using the JSON `preedit` section from FrameUpdate (see Doc 04, Section 4.2). This is the authoritative rendering source. The rendering approach:

1. Draw the terminal grid normally (all cells from DirtyRows)
2. At position `(preedit.cursor_x, preedit.cursor_y)`, overlay the preedit text:
   - Background: slightly different from the terminal background (e.g., lighter/darker by 10%)
   - Text: same font as terminal text, with underline decoration
   - Width: use `display_width` from PreeditUpdate for cell count

**Cursor style during composition (normative)**: The server automatically adjusts `cursor.style` in the FrameUpdate JSON metadata during composition (see doc 04, Section 4.2). Specifically:

- The server MUST set `cursor.style` to block (0) and `cursor.blinking` to false during composition
- `cursor.x` and `cursor.y` MUST equal `preedit.cursor_x` and `preedit.cursor_y` — the block cursor visually encloses the composing character
- The server MUST restore pre-composition `cursor.style` and `cursor.blinking` in the FrameUpdate following PreeditEnd
- **Client MUST NOT override cursor style**: Clients MUST NOT apply any local cursor style overrides based on preedit state. The client renders exactly what the server sends in the FrameUpdate's cursor section. All cursor styling decisions (block during composition, restore on commit) are made server-side and communicated via FrameUpdate.

```
During composition of "한" (2 cells wide):
+----------------------------------------------+
| $ echo "hello"                               |
| hello                                        |
| $ [한]                                       |  <- block cursor encloses composing char
|    --                                        |  <- underline decoration
+----------------------------------------------+

After commit (cursor advances past committed char):
+----------------------------------------------+
| $ echo "hello"                               |
| hello                                        |
| $ 한|                                        |  <- bar cursor at insertion point
|                                              |
+----------------------------------------------+
```

### 10.2 Preedit for Observer Clients

Non-owner clients (observers) also render the preedit overlay. They additionally MAY display an indicator showing which client is composing:

```
+----------------------------------------------+
| $ [한]                                       |
|    -- [Client A composing]                   |  <- optional indicator
+----------------------------------------------+
```

The `preedit_owner` field from PreeditSync/PreeditStart provides the client ID for this indicator. Clients can compare this with their own `client_id` (received in ServerHello, see doc 02, Issue 9/Gap 1) to determine if they are the owner or an observer.

---

## 11. Error Handling

### 11.1 Invalid Composition State

If the server's IME engine reaches an invalid state (should not happen with correctly implemented Korean algorithms):

1. Log the error with full state dump
2. Commit whatever preedit text exists to PTY
3. Reset composition state to `empty`
4. Send PreeditEnd with `reason="cancelled"` to all clients
5. Send a diagnostic notification to the composing client (optional)

### 11.2 Malformed Preedit Messages

If the server receives a message with invalid fields:

| Error | Response |
|-------|----------|
| Unknown input method | Ignore the switch, send error response |
| preedit_session_id mismatch | Ignore the message (stale) |
| preedit_text not valid UTF-8 | Drop message, log error |
| pane_id does not exist | Send error response with error code |

### 11.3 Error Response (type = 0x04FF)

Generic error response for CJK/IME operations.

#### JSON Payload

```json
{
  "pane_id": 1,
  "error_code": 1,
  "detail": "Unknown input method: foobar"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pane_id` | u32 | Related pane |
| `error_code` | u16 | Error identifier (see below) |
| `detail` | string | UTF-8 error description |

**Error codes**:

| Code | Meaning |
|------|---------|
| `0x0001` | Unknown input method |
| `0x0002` | Pane does not exist |
| `0x0003` | Invalid composition state transition |
| `0x0004` | Preedit session ID mismatch |
| `0x0005` | UTF-8 encoding error in preedit text |
| `0x0006` | Input method not supported by server |

---

## 12. Message Type Summary

| Type | Name | Direction | Encoding | Description |
|------|------|-----------|----------|-------------|
| `0x0400` | PreeditStart | S -> C | JSON | New composition session begins |
| `0x0401` | PreeditUpdate | S -> C | JSON | Composition state changed |
| `0x0402` | PreeditEnd | S -> C | JSON | Composition session ended |
| `0x0403` | PreeditSync | S -> C | JSON | Full preedit snapshot for late-joining client |
| `0x0404` | InputMethodSwitch | C -> S | JSON | Request input method change |
| `0x0405` | InputMethodAck | S -> C (broadcast) | JSON | Confirm input method change (all clients) |
| `0x0406` | AmbiguousWidthConfig | Bi | JSON | Set ambiguous character width |
| `0x04FF` | IMEError | S -> C | JSON | Error response |

All CJK/IME messages use JSON payloads (16-byte binary header with ENCODING=0 + JSON body). This provides debuggability (`socat | jq`), cross-language client support (Swift `JSONDecoder`), and schema evolution. The overhead is negligible at preedit message frequencies (~15/s).

---

## 13. Bandwidth Analysis for Preedit

### 13.1 Korean Composition Bandwidth

Typing Korean at ~60 WPM (words per minute), approximately 5 syllables/second. Each syllable requires ~3 keystrokes (consonant + vowel + tail consonant), generating ~3 PreeditUpdate messages.

| Message | Size (header + JSON) | Per-second | Bandwidth |
|---------|---------------------|------------|-----------|
| PreeditUpdate | ~130 B | ~15/s | 1.95 KB/s |
| FrameUpdate (JSON preedit) | ~120 B | ~15/s | 1.8 KB/s |
| PreeditEnd (commit) | ~90 B | ~5/s | 450 B/s |
| **Total preedit overhead** | | | **~4.2 KB/s** |

JSON payloads add ~30 bytes per message compared to binary encoding. This is negligible compared to the overall FrameUpdate bandwidth (~10 KB/s typical) and well worth the debuggability gain (seeing `"text": "한"` instead of hex bytes).

### 13.2 Multi-Client Overhead

With N clients attached, preedit messages are sent to each client:
- 2 clients: ~8.4 KB/s preedit overhead
- 5 clients: ~21 KB/s preedit overhead
- 10 clients: ~42 KB/s preedit overhead

All well within Unix socket capacity.

---

## 14. Integration with FrameUpdate

### 14.1 Preedit in FrameUpdate vs. Dedicated Messages

Both mechanisms are used because they serve different purposes:

| Mechanism | Purpose | Consumer |
|-----------|---------|----------|
| FrameUpdate JSON preedit section | **Rendering**: Where to draw the preedit overlay | Rendering pipeline |
| PreeditStart/Update/End | **State tracking**: Composition details, ownership, conflict resolution | Session manager, debugging, multi-client sync |

**Authoritative rendering rule**: Clients MUST use FrameUpdate's JSON preedit section for rendering, NOT PreeditUpdate's text field. The FrameUpdate preedit section is synchronized with the grid data in the same message, ensuring visual consistency. PreeditUpdate's text may arrive slightly before or after the corresponding FrameUpdate due to buffering. The dedicated messages add metadata (composition_state, owner, session_id) that the FrameUpdate does not carry.

A client that only needs to render can ignore PreeditUpdate messages and rely solely on FrameUpdate's JSON preedit section.

**Capability interaction**: The FrameUpdate JSON preedit section is always included when preedit is active, regardless of whether the client negotiated `CJK_CAP_PREEDIT`. The `CJK_CAP_PREEDIT` capability controls only the dedicated PreeditStart/Update/End/Sync messages. This means any client can render preedit overlays even without understanding the composition state machine — it simply paints the text at the specified position with an underline.

### 14.2 Message Ordering

For a single composition keystroke, the server sends messages in this order:

```
1. PreeditUpdate (0x0401)    -- state tracking (sent first for observers)
2. FrameUpdate (0x0300)      -- rendering (includes JSON preedit section + any grid changes)
```

The PreeditUpdate is sent before FrameUpdate so that clients can update their internal state before the rendering frame arrives. However, clients MUST NOT depend on this ordering — either message may arrive first due to buffering. Since clients MUST use FrameUpdate for rendering, the protocol is resilient to PreeditUpdate being delayed or dropped.

For composition end:
```
1. PreeditEnd (0x0402)       -- state tracking
2. FrameUpdate (0x0300)      -- rendering (preedit.active=false, grid updated with committed text)
```

---

## 15. Open Questions

1. **Japanese/Chinese composition states**: The `composition_state` enum currently only covers Korean. When Japanese (Kana-to-Kanji) and Chinese (Pinyin) are added, what states are needed? For Japanese: `romaji_input`, `kana_input`, `candidate_selection`. For Chinese: `pinyin_input`, `candidate_selection`. These can be added as new enum values without breaking the protocol.

2. **Candidate window protocol**: Japanese and Chinese IMEs present a candidate list. How should this be forwarded to the client? Options:
   - Embed candidate list in PreeditUpdate (simple but potentially large)
   - Separate CandidateList message with pagination
   - Defer to v2 (current recommendation)

3. **Client-side prediction**: For high-latency connections via SSH tunnel, should the client perform local Korean composition prediction and display it immediately, then reconcile with the server's authoritative state? This would improve perceived latency but adds significant complexity.

4. **Preedit and selection interaction**: If a user selects text on a pane where preedit is active, should the selection replace the preedit? Current design: selection operations commit the preedit first, then proceed with selection.

5. **Multiple simultaneous compositions**: Should the protocol support preedit on multiple panes simultaneously (one per pane, same client)? Current design: Yes — each pane has independent preedit state. The client switches "active pane" focus, and the server maintains per-pane state machines.

6. **Undo during composition**: Should Cmd+Z during composition undo the last Jamo addition (similar to Backspace)? Or should it be forwarded to the terminal? Current thinking: Backspace handles decomposition; Cmd+Z is forwarded.
