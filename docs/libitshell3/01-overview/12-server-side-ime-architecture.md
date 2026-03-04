# Server-Side IME Architecture

> **UPDATE**: The approach in this document (using macOS NSTextInputContext on the server) has been **superseded** by the native IME decision documented in [14-architecture-validation-report.md](./14-architecture-validation-report.md). The IME engine will be implemented natively in Zig as a separate library called **libitshell3-ime**, eliminating the GUI process dependency entirely. This document is retained for historical context on why the macOS IME approach was considered and its limitations.

## The Original Proposal (Superseded)

Instead of each client platform (macOS, iOS) handling CJK input composition independently via its own native IME APIs, **move all IME processing to the libitshell3 server side**:

1. **Client** captures raw hardware key events (keycodes + modifiers) and sends them to the server
2. **Server** (running on macOS) processes key events through macOS's IME pipeline (`NSTextInputContext` + `NSTextInputClient`) and libghostty's key event handling
3. **Server** produces rendered terminal state including preedit
4. **Client** simply displays the rendered state — no local IME logic needed

On iOS, where the software keyboard cannot provide raw key events, **build a custom in-app keyboard** for English, Japanese, and Korean that emits the same raw key event format as a hardware keyboard.

---

## Why This Architecture?

### The Problem It Solves

The it-shell project (`~/dev/git/powdream/cjk-compatible-terminal-for-ipad/`) went through **four design iterations** (v2.1 → v2.4) to handle CJK input on iOS, revealing fundamental incompatibilities:

| Aspect | macOS (`NSTextInputClient`) | iOS (`UITextInput`) |
|--------|----------------------------|---------------------|
| Key → text flow | **Synchronous** — `interpretKeyEvents()` calls `insertText`/`setMarkedText` before returning | **Asynchronous** — `super.pressesBegan()` returns immediately; `insertText`/`setMarkedText` fire later |
| Accumulator pattern | Works — collect text during `interpretKeyEvents`, send with original keycode after | **Broken** — accumulator is empty 98.4% of the time (549/558 calls had empty accumulator) |
| Character → keycode mapping | `characters(byApplyingModifiers: [])` respects keyboard layout | Not available — must use static US ANSI mapping |
| `consumed_mods` | Heuristic: `modifierFlags.subtracting([.control, .command])` | Always `GHOSTTY_MODS_NONE` (platform limitation) |
| Software keyboard | N/A (always hardware keyboard on macOS) | No raw key events — only composed text via `insertText:` |

**Root cause of the Korean doubling bug**: `insertText()` on iOS was routing through `ghostty_surface_text()` (the clipboard paste path with bracketed paste wrapping) instead of `ghostty_surface_key()` (the key event path with proper Kitty Keyboard Protocol encoding). When zellij/Claude Code uses bracketed paste mode, this caused every character to be doubled.

**By moving IME to the server (macOS), we use ONE proven code path for all clients.**

---

## Detailed Architecture

```
┌───────────────────────────────────────────────────────┐
│                iOS Client (it-shell3 app)              │
│                                                        │
│  ┌──────────────────┐    ┌──────────────────────────┐ │
│  │ Custom Keyboard   │    │ Hardware Keyboard         │ │
│  │ (English/日本語/  │    │ pressesBegan → UIKey      │ │
│  │  한국어)          │    │ → HID keyCode + mods      │ │
│  │ → HID keyCode     │    │                           │ │
│  │   + mods           │    │                           │ │
│  └────────┬──────────┘    └───────────┬──────────────┘ │
│           │                           │                 │
│           └───────────┬───────────────┘                 │
│                       │                                 │
│                       ▼                                 │
│           ┌───────────────────────┐                     │
│           │ Raw Key Event Sender  │                     │
│           │ (keycode, mods, action│                     │
│           │  — NO text, NO IME)   │                     │
│           └───────────┬───────────┘                     │
│                       │                                 │
│                       │ Unix Socket / Network           │
│                       ▼                                 │
│           ┌───────────────────────┐                     │
│           │ State Receiver        │                     │
│           │ → Render terminal     │                     │
│           │ → Display preedit     │                     │
│           │   (NO local IME)      │                     │
│           └───────────────────────┘                     │
└───────────────────────────────────────────────────────┘
                        │
                        │ Protocol (raw key events ↑, rendered state ↓)
                        │
┌───────────────────────┼───────────────────────────────┐
│                       ▼                                │
│              libitshell3 Server                        │
│              (macOS, GUI-capable process)               │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │              IME Processing Layer                 │ │
│  │                                                   │ │
│  │  Raw key event                                    │ │
│  │       │                                           │ │
│  │       ▼                                           │ │
│  │  Construct NSEvent (keyCode, mods, chars)          │ │
│  │       │                                           │ │
│  │       ▼                                           │ │
│  │  Hidden NSView.interpretKeyEvents([event])         │ │
│  │       │ (SYNCHRONOUS on macOS ✓)                   │ │
│  │       │                                           │ │
│  │       ├──→ setMarkedText("ㅎ") → preedit update   │ │
│  │       ├──→ setMarkedText("하") → preedit update   │ │
│  │       ├──→ insertText("한")   → commit text       │ │
│  │       └──→ ...                                    │ │
│  └──────────────────────┬───────────────────────────┘ │
│                         │                              │
│                         ▼                              │
│  ┌──────────────────────────────────────────────────┐ │
│  │         libghostty Key Event Handling             │ │
│  │                                                   │ │
│  │  ghostty_surface_key(keycode, mods, text, ...)    │ │
│  │  ghostty_surface_preedit(preedit_text)            │ │
│  │       │                                           │ │
│  │       ▼                                           │ │
│  │  Terminal state updated (VT, grid, preedit)       │ │
│  └──────────────────────┬───────────────────────────┘ │
│                         │                              │
│                         ▼                              │
│  ┌──────────────────────────────────────────────────┐ │
│  │         State Snapshot & Broadcast                │ │
│  │                                                   │ │
│  │  Terminal grid + preedit + cursor → all clients   │ │
│  └──────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────┘
```

---

## Feasibility Analysis

### 1. Server-Side IME on macOS — FEASIBLE (with constraint)

**Constraint: The server process must be connected to the macOS window server.**

macOS's IME pipeline (`NSTextInputContext` → input method → `NSTextInputClient` callbacks) requires:
- An `NSApplication` run loop connected to the window server
- An `NSWindow` (can be hidden/offscreen)
- An `NSView` as first responder conforming to `NSTextInputClient`
- The `interpretKeyEvents:` call is **synchronous** — this is the key advantage over iOS

**This means the libitshell3 server on macOS cannot be a true headless daemon (LaunchDaemon). It must be either:**

| Option | Description | Viable? |
|--------|-------------|---------|
| **A) LSUIElement app** | No dock icon, no menu bar, but connected to window server. Hidden NSWindow for IME. | **Yes — recommended** |
| **B) Part of it-shell3 app** | The macOS terminal app runs the server in-process. Already has GUI. | **Yes — simplest for v1** |
| **C) LSBackgroundOnly app** | Background process with window server access. | **Yes** |
| **D) LaunchDaemon** | No window server access. Cannot use IME. | **No** |
| **E) Standalone IME libs** | libhangul + librime in-process, no window server needed. | **Possible but complex** |

**Recommendation for phased approach:**
- **Phase 1**: Option B — server runs inside the macOS app (simplest, already has GUI)
- **Phase 2**: Option A — extract server to LSUIElement for session persistence across app restarts

### 2. Constructing NSEvents from Raw Key Codes — FEASIBLE

macOS provides `NSEvent.keyEvent(with:...)` to construct synthetic key events:

```swift
let event = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: modifierFlags,        // from client
    timestamp: ProcessInfo.processInfo.systemUptime,
    windowNumber: hiddenWindow.windowNumber,
    context: nil,
    characters: "",                       // empty — let IME fill this
    charactersIgnoringModifiers: "",       // could derive from keycode
    isARepeat: false,
    keyCode: macVirtualKeyCode             // translated from client's HID code
)

// Feed through IME synchronously:
hiddenView.interpretKeyEvents([event])
// → insertText/setMarkedText callbacks fire HERE, synchronously
```

**Key code translation**: The client sends HID usage codes (same space as iOS `UIKeyboardHIDUsage`). The server translates to macOS virtual keycodes using a static mapping table (this mapping already exists in the it-shell project at `KeyMapping.swift`).

**Important detail from ghostty's code**: Korean input requires NSEvent **object identity** — you must reuse the original event object in certain cases. The server must be careful about event object lifecycle.

### 3. iOS Custom Keyboard — FEASIBLE

Building a custom in-app keyboard that emits raw HID keycodes is straightforward:

```
┌─────────────────────────────────────────────┐
│              Custom Keyboard View            │
│                                              │
│  ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐ │
│  │ ㅂ│ ㅈ│ ㄷ│ ㄱ│ ㅅ│ ㅛ│ ㅕ│ ㅑ│ ㅐ│ ㅔ│ │  Korean layout
│  ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤ │
│  │ ㅁ│ ㄴ│ ㅇ│ ㄹ│ ㅎ│ ㅗ│ ㅓ│ ㅏ│ ㅣ│   │ │
│  ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤ │
│  │ ㅋ│ ㅌ│ ㅊ│ ㅍ│ ㅠ│ ㅜ│ ㅡ│   │   │   │ │
│  └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘ │
│                                              │
│  Each key tap → sends HID keyCode + mods     │
│  (NOT Korean characters — just physical key  │
│   identity, same as what a HW keyboard sends)│
└─────────────────────────────────────────────┘
```

**Implementation approach:**
- Each key button knows its HID usage code (e.g., ㅂ is on the Q key → `UIKeyboardHIDUsage.keyboardQ` = 0x14)
- Tapping a key sends `(keyCode: 0x14, mods: [], action: .press)` to the server
- The server's macOS IME processes this as Q-key on Korean input layout → produces ㅂ
- **No iOS IME involvement at all**

**UX considerations:**
- Must support keyboard layout switching (EN ↔ KR ↔ JP ↔ ...)
- Must support Shift, Ctrl, Alt, Cmd modifier keys
- Must support special keys: Enter, Backspace, Tab, Escape, Arrow keys
- Key labels change per layout (Q → ㅂ for Korean, Q → た for Japanese)
- Could optionally fall through to hardware keyboard's `pressesBegan` when external keyboard is connected

**Precedent**: Many iOS terminal apps (Blink Shell, Termius) already build custom keyboard accessory views with special keys. Extending this to a full keyboard is more work but not architecturally novel.

### 4. Sending Rendered State Back to Client — FEASIBLE

libghostty-vt provides everything needed to snapshot terminal state without GPU:

```zig
// On the server:
var terminal: ghostty_vt.Terminal = try .init(alloc, .{ .cols = 80, .rows = 24 });
var stream = terminal.vtStream();

// Feed PTY output through VT parser
try stream.nextSlice(pty_output_bytes);

// Snapshot options:

// Option A: Full VT re-serialization (send escape sequences to client)
const formatter: ghostty_vt.formatter.ScreenFormatter = .init(
    &terminal.screens.active, .{ .emit = .vt }
);

// Option B: Structured cell data (row/col/char/attrs)
var render_state: ghostty_vt.RenderState = undefined;
render_state.update(&terminal);

// Option C: Plain text (for debugging)
const text = try terminal.plainString(alloc);
```

**Preedit state** is managed externally (not in libghostty-vt's Terminal), but is trivial:

```zig
const PreeditState = struct {
    active: bool = false,
    text: []const u8 = &.{},   // UTF-8
    cursor_x: u32 = 0,
    cursor_y: u32 = 0,
};
```

### 5. Latency Considerations

| Path | Components | Expected Latency |
|------|-----------|-----------------|
| Local (macOS, Unix socket) | key → server IME → VT update → client render | < 1ms |
| Local (macOS, in-process) | key → IME → VT update → render | < 0.1ms |
| Remote (iOS → macOS, LAN) | key → network → server IME → VT update → network → render | 1-5ms |
| Remote (iOS → macOS, WAN) | key → network → server IME → VT update → network → render | 20-100ms |

**IME composition is latency-sensitive** — users expect immediate visual feedback while composing Korean/Japanese/Chinese text. On LAN, this should be fine. Over WAN, there may be perceptible delay.

**Mitigation for high-latency connections:**
- Client-side preedit prediction (show probable preedit locally while waiting for server confirmation)
- But this is an optimization for later — start without it

---

## Comparison with Alternative Approaches

| Approach | CJK Consistency | iOS Support | Complexity | Session Persistence |
|----------|----------------|-------------|------------|-------------------|
| **Server-side IME (this proposal)** | Perfect — one code path | Custom keyboard | Medium | Yes (server holds state) |
| Client-side IME (tmux model) | Each platform differs | Uses native IME | Low per-platform, high total | No preedit persistence |
| Standalone IME libs (libhangul etc.) | Good but not system IME | Works headless | High (bundle 3+ IME engines) | Yes |
| Hybrid (client IME + server sync) | Good | Complex | High (sync protocol) | Partial |

**Server-side IME wins because:**
1. **One code path** — macOS `interpretKeyEvents:` is synchronous and proven
2. **No iOS IME bugs** — the entire iOS async IME problem is eliminated
3. **Session handoff** — preedit state lives on the server, so switching devices mid-composition works
4. **Consistent KKP encoding** — `ghostty_surface_key()` path always used, no risk of bracketed paste contamination

---

## Critical Design Decisions

### Decision 1: Server Process Type

For the server to use macOS IME, it must be GUI-capable. Options:

**Recommended (phased):**
- **v1**: Server runs inside the it-shell3 macOS app. No separate process. The app IS the server. Session persistence via snapshot-to-disk (like cmux) + restore on relaunch.
- **v2**: Extract server to an LSUIElement helper process that persists in the background. Similar to iTerm2's FileDescriptorServer but with IME capability.

### Decision 2: Key Event Wire Format

What the client sends to the server:

```
KeyEventMessage {
    keycode: u16,       // HID usage code (UIKeyboardHIDUsage)
    action: u8,         // 0=press, 1=release, 2=repeat
    mods: u8,           // bitflags: shift|ctrl|alt|super
    timestamp: u64,     // for key repeat detection
}
```

**Notably absent**: No `text` field, no `characters` field. The server derives text through IME processing. The client is truly just a "remote keyboard."

### Decision 3: State Update Wire Format

What the server sends to the client. Two options:

**Option A: Differential VT stream**
- Send only the VT escape sequences that changed since last update
- Client feeds them into a local libghostty surface for rendering
- Pro: Compact, leverages libghostty's rendering on the client
- Con: Must track per-client diff state

**Option B: Full screen snapshot**
- Send rendered cell grid (rows × cols × cell data)
- Client renders directly without local VT parsing
- Pro: Simpler, no state tracking
- Con: Larger payload per update

**Option C: Hybrid (recommended)**
- Normal terminal output: differential VT stream (Option A)
- Preedit state: separate message with current preedit text + position
- Layout changes: separate structured messages

### Decision 4: Input Method Selection on Server

The server must know which input method to activate. Options:

- **Client-requested**: Client sends the desired input method (e.g., "com.apple.inputmethod.Korean.2SetKorean") and the server switches via `TISSelectInputSource()`
- **Server-configured**: Server uses whatever input method is active on macOS
- **Per-pane**: Each pane remembers its last input method

**Recommended**: Client sends input method identifier. Server switches. Per-pane memory for convenience.

### Decision 5: Custom Keyboard Layout Data

The custom iOS keyboard needs layout data (which key shows which label):

```json
{
  "korean-2set": {
    "rows": [
      [{"hid": "0x14", "label": "ㅂ", "shifted": "ㅃ"},
       {"hid": "0x1A", "label": "ㅈ", "shifted": "ㅉ"},
       ...],
      ...
    ]
  },
  "japanese-romaji": {
    "rows": [
      [{"hid": "0x14", "label": "Q"},  // Same as English
       ...],
    ]
  }
}
```

This data can be bundled with the iOS app. Japanese Romaji uses the same QWERTY layout as English (the IME on the server converts romaji → kana → kanji).

---

## Risks and Mitigations

### Risk 1: NSEvent Construction Fidelity

**Risk**: Synthetic NSEvents may not behave identically to real hardware events in all IME edge cases (especially Korean input, which is known to depend on NSEvent object identity in ghostty).

**Mitigation**: Test extensively with Korean 2-set, 3-set, Japanese Romaji, Japanese Kana, Chinese Pinyin, Chinese Wubi. Start with Korean as the most complex case.

**Validation experiment**: Build a minimal macOS app that constructs NSEvents from HID keycodes and feeds them through `interpretKeyEvents:`. Verify Korean ㅎ→하→한 composition works correctly.

### Risk 2: Input Method Switching

**Risk**: Programmatically switching input methods via `TISSelectInputSource()` may require accessibility permissions or not work for all IMEs.

**Mitigation**: Test with all target input methods. If `TISSelectInputSource()` is unreliable, the server could maintain multiple hidden views, each with a different input method active.

### Risk 3: WAN Latency for Preedit

**Risk**: Over slow connections, preedit feedback may feel laggy.

**Mitigation**: Accept for v1. For v2, consider client-side Hangul composition prediction (Korean composition rules are deterministic and can be computed locally for preview, then confirmed by server).

### Risk 4: Custom Keyboard UX

**Risk**: Users may not accept a non-standard keyboard on iOS.

**Mitigation**:
- Make the custom keyboard visually similar to iOS's native keyboard
- Support both custom keyboard AND hardware keyboard (pressesBegan passthrough)
- Allow falling back to iOS native keyboard for non-CJK input if desired
- The target audience (developers using AI agents) are likely to accept a specialized keyboard

### Risk 5: macOS Window Server Dependency

**Risk**: The server requires window server access, so it cannot run in SSH-only or headless macOS environments.

**Mitigation**: For headless scenarios, fall back to standalone IME libraries (libhangul for Korean, which is algorithmic and needs no GUI). This is a future enhancement, not a v1 blocker — the primary use case is a macOS desktop with a GUI session.

---

## Implementation Phases

### Phase 1: Proof of Concept — Server-Side IME

**Goal**: Validate that synthetic NSEvents produce correct IME output.

1. Create a minimal macOS app (LSUIElement)
2. Create a hidden NSWindow + custom NSTextInputClient view
3. Construct NSEvents from HID keycodes
4. Call `interpretKeyEvents:` and capture `insertText:`/`setMarkedText:` callbacks
5. Test with Korean 2-set: ㅎ→하→한, backspace decomposition (한→하→ㅎ→empty)
6. Test with Japanese Romaji: k→か, ka→か, kan→かん, kanji→漢字 (with candidate selection)
7. Test with Chinese Pinyin: basic composition + candidate selection

### Phase 2: Wire Protocol for Raw Key Events

1. Define `KeyEventMessage` in Zig
2. Implement Unix socket transport
3. Client sends key events → server receives and constructs NSEvents
4. Server sends terminal state updates back

### Phase 3: iOS Custom Keyboard

1. Build `KeyboardView` in Swift/UIKit
2. Korean 2-set layout
3. English QWERTY layout
4. Japanese Romaji layout (same as QWERTY, different label optional)
5. Layout switching UI
6. Modifier key support (Shift, Ctrl, Alt, Cmd)
7. Special keys (Enter, Backspace, Tab, Escape, Arrows)

### Phase 4: Integration with libghostty

1. Server feeds IME output through `ghostty_surface_key()` and `ghostty_surface_preedit()`
2. Use libghostty-vt for headless terminal state tracking
3. Snapshot terminal state and broadcast to clients
4. Client renders using local libghostty surface

---

## Candidate Window Problem & Scoping Decision

### The Problem

Japanese and Chinese IMEs require a **candidate selection dialog** (e.g., typing `kanji` → pick from 漢字/感じ/幹事/...). On macOS, this window is rendered by the input method process itself, positioned via `firstRect(forCharacterRange:)`. There is **no public API** to extract the candidate list contents from `NSTextInputClient`.

This means: when the server's hidden NSView triggers a candidate list, we cannot easily intercept that data and forward it to a remote iOS client.

**Korean does NOT have this problem** — Hangul composition is purely algorithmic (jamo → syllable block), no candidate selection needed.

### Decision: Phased CJK Support

| Phase | Language | Candidate Window | Approach |
|-------|----------|-----------------|----------|
| **v1** | **Korean** | Not needed | Server-side IME via `interpretKeyEvents:`. Works on all clients. |
| **v1** | **Japanese/Chinese on macOS local client** | System renders natively | macOS system candidate window appears on the same machine. Just works. |
| **Future** | **Japanese/Chinese on iOS remote client** | Custom candidate UI | Use standalone IME engines (librime for Chinese, libkkc/libmozc for Japanese) that expose candidate lists programmatically. Build custom candidate selection UI on the iOS client. |

### Why This Scoping Works

1. **Korean is the highest priority** — it has the most complex composition rules (Jamo decomposition) and is the language the user needs most urgently
2. **Korean needs zero candidate UI** — the entire composition is deterministic
3. **macOS local use** covers Japanese/Chinese for free — the system IME candidate window renders on the same machine
4. **Standalone IME engines exist** for when iOS Japanese/Chinese support is needed:
   - [librime](https://github.com/rime/librime) — Chinese (Pinyin, Wubi, etc.), C++ library, exposes candidates programmatically
   - [libkkc](https://github.com/ueno/libkkc) — Japanese Kana-Kanji conversion
   - [libhangul](https://github.com/libhangul/libhangul) — Korean (alternative to macOS IME for headless scenarios)

---

## Conclusion

**The server-side IME architecture is feasible and is the correct approach for this project.** It elegantly solves the fundamental iOS vs macOS IME incompatibility by eliminating client-side IME entirely. The custom iOS keyboard is the key enabler — without it, the approach would fail for software keyboard users.

The main constraint is that the macOS server must have window server access (not a true headless daemon), which is acceptable for the target use case of a macOS desktop running the it-shell3 app.

The candidate window problem is real but scoped out of v1 by focusing on Korean first and allowing macOS system IME to handle Japanese/Chinese for local clients.

**Validation priority**: The single most important experiment is Phase 1 — proving that synthetic NSEvents produce correct Korean IME composition through `interpretKeyEvents:`. If this works, everything else follows.
