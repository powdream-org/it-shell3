# Why We're Building a Native IME: The Full Story

## TL;DR

After four design iterations on the **it-shell** iOS terminal project (`../cjk-compatible-terminal-for-ipad/`), we discovered that **iOS and macOS have fundamentally incompatible IME architectures**. No amount of clever workarounds can make iOS's asynchronous UITextInput behave like macOS's synchronous `interpretKeyEvents()`. Rather than maintaining two divergent input paths forever, we chose to bypass OS IME entirely and implement composition natively.

---

## The Problem: CJK Input in Terminal Multiplexers

Terminal multiplexers (tmux, zellij, screen) and AI agent chat interfaces (Claude Code, Codex CLI) have never properly supported CJK input composition. The core issue:

1. **IME preedit state** (the in-progress composition shown with underline) is a GUI concept — it lives in the input method framework, not in the terminal's byte stream.
2. **Terminal multiplexers** operate on byte streams between PTY and client — they have no concept of preedit.
3. **Bracketed paste mode** (used by zellij, Claude Code) wraps input in escape sequences `\e[200~...\e[201~`. When IME committed text goes through the paste path, each character becomes a separate paste event, causing **Korean text doubling**.

## The iOS vs macOS IME Incompatibility

### macOS: Synchronous (Works Perfectly)

On macOS, Ghostty's proven input flow:

```swift
// macOS: SurfaceView_AppKit.swift (keyDown)
override func keyDown(with event: NSEvent) {
    self.keyTextAccumulator = []           // 1. Setup accumulator
    self.interpretKeyEvents([event])        // 2. SYNCHRONOUS — triggers callbacks:
    //   → insertText() fires HERE, appends to accumulator
    //   → setMarkedText() fires HERE for preedit
    // 3. interpretKeyEvents returns — accumulator has text
    let text = keyTextAccumulator           // 4. Read accumulated text
    ghostty_surface_key(surface, ...)       // 5. Send with original keycode
}
```

`interpretKeyEvents()` is a dedicated `NSResponder` API that **synchronously** routes the key event through macOS's text input system. All IME callbacks (`insertText`, `setMarkedText`) fire **before** it returns. The accumulator pattern reliably collects committed text alongside the original physical keycode.

### iOS: Asynchronous (Fundamentally Broken for This Pattern)

On iOS, there is **no equivalent** of `interpretKeyEvents()`:

```swift
// iOS: what we tried in v2.3
override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    self.keyTextAccumulator = []            // 1. Setup accumulator
    super.pressesBegan(presses, with: event) // 2. Returns IMMEDIATELY
    // → insertText() fires LATER (next main queue cycle)
    // → setMarkedText() fires LATER
    // 3. super returns — accumulator is EMPTY
    let text = keyTextAccumulator            // 4. Empty 98.4% of the time!
    // ... wrong branch taken, causes doubling
}
```

`super.pressesBegan()` dispatches the event to UIKit's responder chain and returns immediately. UITextInput callbacks fire **asynchronously on a separate UIKit text input system path**, typically on the next main queue cycle.

### The Five Specific Differences

| Aspect | macOS (NSTextInputClient) | iOS (UITextInput) |
|--------|--------------------------|-------------------|
| Key-to-text flow | **Synchronous** — `interpretKeyEvents()` triggers callbacks before returning | **Asynchronous** — `super.pressesBegan()` returns immediately; callbacks fire later |
| Accumulator pattern | Works — collect text during `interpretKeyEvents` | **Broken** — accumulator empty 98.4% of the time (549/558 calls) |
| Character-to-keycode mapping | `characters(byApplyingModifiers: [])` respects keyboard layout | Not available — must use static US ANSI mapping |
| `consumed_mods` | Heuristic: `modifierFlags.subtracting([.control, .command])` | Always `GHOSTTY_MODS_NONE` (platform limitation) |
| Software keyboard | N/A (always hardware keyboard on macOS) | No raw key events — only composed text via `insertText:` |

### The NSEvent Object Identity Problem

A subtle but critical issue discovered in the macOS Ghostty codebase:

```swift
// From Ghostty SurfaceView_AppKit.swift:
// IMPORTANT: we MUST reuse the old event if they're equal because
// this keeps things like Korean input working. There must be some object
// equality happening in AppKit somewhere because this is required.
```

Korean input in macOS depends on **reusing the original NSEvent object** — not constructing a new one. AppKit appears to perform object identity checks internally. This means any approach that constructs synthetic NSEvents from raw keycodes (like the server-side IME proposal) is at risk of breaking Korean composition.

---

## The Four Failed Design Iterations

All iterations are documented in the it-shell project at `../cjk-compatible-terminal-for-ipad/docs/`.

### v2.1: Original Implementation (insertText → ghostty_surface_text)

**Approach**: Route all committed text from UITextInput's `insertText()` through `ghostty_surface_text()`.

**Why it failed**: `ghostty_surface_text()` is Ghostty's **clipboard paste API**. Internally it calls `completeClipboardPaste(text, true)`, which wraps text in bracketed paste markers when bracketed paste mode is active. Every Korean character committed via IME became a separate paste event:

```
User types: 한글
Terminal receives: \e[200~한\e[201~\e[200~글\e[201~
Display shows: 하하한한그그글글    ← DOUBLED
```

The correct path is `ghostty_surface_key()`, which goes through the KeyEncoder — KKP-aware, never uses bracketed paste wrapping.

### v2.2: Direct Call Pattern (insertText → ghostty_surface_key directly)

**Approach**: Route `insertText()` through `ghostty_surface_key()` instead, using a stored `lastPassedThroughKeycode` from the most recent `pressesBegan`.

**Why it was insufficient**:
- A composing post-check in `pressesBegan` sent `ghostty_surface_key(composing=true)` after passing through to UITextInput, which interfered with Japanese preedit display (Bug #2).
- `lastPassedThroughKeycode` could become stale if `insertText` was not called for a particular key press.
- Composing detection relied on `markedText.length` as a proxy — unreliable.

### v2.3: Accumulator Pattern (Mirror macOS)

**Design doc**: `../cjk-compatible-terminal-for-ipad/docs/design-v2.3.md`

**Approach**: Exactly mirror macOS Ghostty's `keyTextAccumulator` pattern on iOS.

1. Set `keyTextAccumulator = []` before `super.pressesBegan()`.
2. `insertText()` accumulates text instead of sending when accumulator is non-nil.
3. After `super.pressesBegan()` returns, branch on accumulator contents:
   - **Case A**: Text accumulated → send committed text via `ghostty_surface_key(composing: false)`.
   - **Case B**: No text but marked text exists → composing state, send `composing: true`.
   - **Case C**: No text, no marked text → plain key (dead key, system-consumed).

**Why it COMPLETELY FAILED on real iPad Pro M4**:

The entire design assumed `super.pressesBegan()` is synchronous. **It is not.**

Real device testing results:
- **English**: "a" became "aa" (doubling). Accumulator empty → Case C-plain fired → sent "a". Later, `insertText("a")` fired asynchronously → sent "a" again.
- **Korean**: "g" became "gㅎ" (ASCII + Korean jamo). Case C-plain sent ASCII "g". Later, `setMarkedText("ㅎ")` fired asynchronously.
- **Japanese**: First character appeared as raw alphabet before IME could convert to kana.

Console logs confirmed: `keyTextAccumulator` was empty in **549 out of 558 calls (98.4%)**.

### v2.4: Pending Keycode Pattern (Accepted iOS Async Nature)

**Design doc**: `../cjk-compatible-terminal-for-ipad/docs/design-v2.4.md`

**Approach**: Completely invert the control flow. Accept that iOS is asynchronous. `pressesBegan` only **stores** the physical keycode. UITextInput callbacks **consume** the stored keycode and send.

```swift
// v2.4 flow:
override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    self.pendingKeyInfo = (keycode: macKeycode, mods: mods)  // 1. Store keycode only
    super.pressesBegan(presses, with: event)                  // 2. Let UIKit process
    // Schedule async fallback for dead keys / system-consumed keys
    DispatchQueue.main.async { self.handleAsyncFallback() }
}

func insertText(_ text: String) {  // Fires asynchronously
    if let pending = self.pendingKeyInfo {
        // Hardware keyboard path: use physical keycode
        self.pendingKeyInfo = nil
        ghostty_surface_key(text: text, keycode: pending.keycode, ...)
    } else {
        // Software keyboard path: derive keycode from character
        ghostty_surface_key(text: text, keycode: derivedKeycode, ...)
    }
}
```

**Architectural invariant**: Text is NEVER sent from `pressesBegan` for printable keys. Only two places send committed text: `insertText` (sole path for committed text) and `handleKeyPress` (for special keys and ctrl/alt/cmd combos only).

**This works on iOS** — but it's a complex, fragile pattern with async timing concerns, and it only solves the iOS client side. The macOS and iOS paths remain fundamentally different.

---

## The Server-Side IME Proposal (Considered and Rejected)

### The Idea

After the iOS struggles, a radical proposal emerged for the libitshell3 architecture: move ALL IME processing to the server.

```
Client → raw HID keycodes → Server → NSTextInputContext → committed text → PTY
                                    → preedit state → FrameUpdate → Client display
```

### Why It Was Attractive

- **One proven code path** — macOS `interpretKeyEvents` is synchronous and well-understood
- **Eliminates iOS async problem** — clients just send raw key events
- **Session handoff** — preedit state lives on server, device switching mid-composition works

### Why It Was Rejected

Documented in `docs/modules/libitshell3/14-architecture-validation-report.md`:

| Risk | Severity | Details |
|------|----------|---------|
| **GUI process requirement** | Critical | `NSTextInputContext` requires window server access. The daemon cannot be a true LaunchDaemon, cannot run over SSH, cannot run on Linux. |
| **NSEvent construction fidelity** | Critical | Korean input depends on NSEvent object identity (undocumented AppKit behavior). Synthetic events constructed from HID keycodes may break composition. No way to verify without full proof-of-concept. |
| **Candidate window forwarding** | High | Japanese/Chinese candidate selection windows cannot be captured and forwarded to remote clients. No public API for extracting candidate lists from NSTextInputClient. |
| **macOS-only** | High | Entire approach ties the server to macOS. Future Linux support impossible. |

The Architecture Validation Report rated confidence at 7.5/10 with server-side NSTextInputContext, versus 9/10 with native IME. The NSEvent risk alone was enough to reject the approach.

---

## The Decision: Native IME with libhangul

### Why Native

| Aspect | OS IME (NSTextInputContext) | Native IME (libhangul) |
|--------|---------------------------|------------------------|
| Daemon portability | GUI-capable process only | True headless daemon |
| Platform dependency | macOS only | Zero OS dependency |
| NSEvent risk | **HIGH** — undocumented object identity | **Eliminated** |
| iOS support | Complex async workarounds | Same code path as macOS |
| Korean composition | OS-dependent behavior | Deterministic Unicode algorithm |
| Testability | Requires GUI context | Pure unit tests |
| Linux future | Impossible | Same library works |

### Why libhangul

- **Battle-tested**: Used by ibus-hangul, fcitx-hangul, nabi — every Linux Korean IME framework
- **Zero dependencies**: Core library needs only a C compiler (no Expat, no ICU, no OS frameworks)
- **Complete coverage**: 9 keyboard layouts (2-set, 3-set variants, Romaja)
- **Jamo-level backspace**: Built-in stack-based undo (한→하→ㅎ→empty)
- **Small footprint**: 4 source files, ~3000 lines of C
- **Well-defined API**: `hangul_ic_process()` returns true/false for consumed/not-consumed, clean separation of concerns
- **LGPL-2.1**: Compatible with dynamic linking; Zig wrapper can use any license

### Why Korean First

Korean is the **ideal** first language because:

1. **Purely algorithmic** — Hangul composition follows a deterministic Unicode formula. No dictionary lookup, no ambiguity, no candidate selection.
2. **No candidate UI needed** — Unlike Japanese (kana→kanji) and Chinese (pinyin→hanzi), Korean never needs a candidate selection window.
3. **The user's primary need** — The it-shell project was built specifically for CJK input on iPad, with Korean as the primary language.
4. **Validates the architecture** — If native Korean IME works end-to-end (HID keycode → composition → preedit → commit → PTY), the same architecture extends to Japanese/Chinese with library swaps.

### Phased Language Roadmap

| Phase | Language | Engine | Candidate UI |
|-------|----------|--------|-------------|
| v1 | English (QWERTY) | Static HID→ASCII table | None |
| v1 | Korean (2-set) | libhangul | None |
| v1 | Korean (3-set, Romaja, etc.) | libhangul (all 9 layouts) | None |
| Future | Japanese | libkkc or libmozc | Required — app layer |
| Future | Chinese | librime | Required — app layer |
| Future | European dead keys | Compose table | None |

### Confidence Assessment

| Approach | Confidence | Rationale |
|----------|-----------|-----------|
| macOS NSTextInputContext on server | 7.5/10 | NSEvent construction risk, GUI process requirement |
| Native IME with libhangul | **9/10** | Deterministic, testable, portable, battle-tested library |

The 1/10 gap to perfect confidence is for future Japanese/Chinese support, which will require candidate UI — a known, well-scoped challenge.
