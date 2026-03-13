# IME Interface Contract v0.7 — Overview

> **Version**: v0.7
> **Date**: 2026-03-07
> **Part of the IME Interface Contract v0.7. See this file for the document index.**
> **Changes from v0.6**: See [Appendix I: Changes from v0.6](99-appendices.md#appendix-i-changes-from-v06)

## Document Index

| Document | Contents |
|----------|----------|
| 01-overview.md | Overview, processing pipeline, responsibility matrix |
| 02-types.md | KeyEvent, ImeResult, modifier flush policy, input method identifiers |
| 03-engine-interface.md | ImeEngine vtable, setActiveInputMethod, HangulImeEngine, MockImeEngine |
| 04-ghostty-integration.md | ghostty integration, memory ownership |
| 05-extensibility-and-deployment.md | Future extensibility, C API boundary, session persistence |
| 99-appendices.md | Change history appendices (A-I) |

---

# 01 — libitshell3 <-> libitshell3-ime Interface Contract

> **Status**: Draft v0.7 — composition_state removed from ImeResult; preedit model simplified. Cross-team preedit overhaul resolutions applied.
> **Supersedes**: [v0.6/01-overview.md](../v1.0-r6/01-overview.md), [v0.5/01-interface-contract.md](../v1.0-r5/01-interface-contract.md), [v0.4/01-interface-contract.md](../v1.0-r4/01-interface-contract.md), [v0.3/01-interface-contract.md](../v1.0-r3/01-interface-contract.md), [v0.2/01-interface-contract.md](../v1.0-r2/01-interface-contract.md), [v0.1/01-interface-contract.md](../v1.0-r1/01-interface-contract.md)
> **Date**: 2026-03-07
> **Review participants**: protocol-architect, protocol-swe, cjk-specialist, ime-expert, principal-architect, ime-architect, ime-swe
> **PoC validation**: `poc/02-ime-ghostty-real/poc-ghostty-real.m` — 22/24 tests pass (2 skipped due to libghostty VT parser bug, not IME code); `poc/03-macos-ime-suppression/` — macOS IME suppression validated; `poc/04-libhangul-states/probe.c` — composition_state factual errors confirmed; `poc/05-preedit-visual/` — preedit-as-cell-data rendering validated
> **Changes from v0.3**: See [Appendix E: Changes from v0.3](99-appendices.md#appendix-e-changes-from-v03)
> **Changes from v0.4-pre**: See [Appendix F: Identifier Consensus Changes](99-appendices.md#appendix-f-identifier-consensus-changes)
> **Changes from v0.4**: See [Appendix G: Changes from v0.4](99-appendices.md#appendix-g-changes-from-v04)
> **Changes from v0.5**: See [Appendix H: Changes from v0.5](99-appendices.md#appendix-h-changes-from-v05)
> **Changes from v0.6**: See [Appendix I: Changes from v0.6](99-appendices.md#appendix-i-changes-from-v06)

## 1. Overview

This document defines the **exact interface** between libitshell3 (terminal multiplexer daemon) and libitshell3-ime (native IME engine). It specifies:

- The types that cross the boundary (input and output)
- Who is responsible for what
- How the IME output maps to libghostty API calls
- Memory ownership and lifetime rules
- Future extensibility for Japanese/Chinese without v1 overhead

### Design Principles

1. **Single interface for all languages.** No engine-type flags, no capability negotiation. Korean simply never populates candidates. (Informed by fcitx5/ibus: both use one `keyEvent` method for all languages.)
2. **Engine owns composition decisions.** The IME engine decides when to flush on modifiers, not the framework. (Informed by ibus-hangul, fcitx5-hangul patterns.)
3. **Struct return over callbacks.** `processKey()` returns an `ImeResult` struct — simpler and more testable than side-effect callbacks. Candidate lists (future) use a separate optional callback channel.
4. **Don't make the common path pay for the uncommon path.** English/Korean processing adds zero overhead for future Japanese/Chinese candidate support.
5. **Testable via trait.** libitshell3 depends on an `ImeEngine` interface, not the concrete implementation. Mock injection for tests.
6. **Framework owns input method management.** libitshell3 (the framework) decides what input methods are available and which is active. The engine receives `setActiveInputMethod()` calls and processes keys accordingly. (Informed by fcitx5/ibus: language enumeration and toggle logic live in the framework, not in individual engines.)

---

## 2. Processing Pipeline

### Three-Phase Key Processing

```
Client sends: HID keycode + modifiers + shift
                    |
                    v
+--------------------------------------------------+
|  Phase 0: Global Shortcut Check (libitshell3)    |
|                                                   |
|  - Language switch -> setActiveInputMethod(id)    |
|    (toggle key detection is libitshell3's concern)|
|  - App-level shortcuts that bypass IME entirely   |
|  - If consumed: STOP                              |
+----------------------+---------------------------+
                       | not consumed
                       v
+--------------------------------------------------+
|  Phase 1: IME Engine (libitshell3-ime)           |
|                                                   |
|  processKey(KeyEvent) -> ImeResult                |
|                                                   |
|  Engine internally:                               |
|  - Checks modifiers (Ctrl/Alt/Cmd) -> flush + fwd|
|  - Checks non-printable (arrow/F-key) -> flush+fwd|
|  - Feeds printable to libhangul -> compose        |
|  - Handles "not consumed" (hangul_ic_process()    |
|    returns false): flush + forward rejected key   |
|  - Returns committed/preedit/forward_key          |
+----------------------+---------------------------+
                       | ImeResult
                       v
+--------------------------------------------------+
|  Phase 2: ghostty Integration (libitshell3)      |
|                                                   |
|  committed_text -> ghostty_surface_key            |
|                   (composing=false, text=utf8)    |
|                   + RELEASE event (text=null)     |
|                                                   |
|  preedit_text   -> ghostty_surface_preedit        |
|                   (utf8, len)                     |
|                                                   |
|  forward_key    -> HID->ghostty_key mapping       |
|                 -> ghostty keybinding check        |
|                 -> if not bound: ghostty_surface_key|
|                   (composing=false, text=null*)   |
|                   + RELEASE event (text=null)     |
|                                                   |
|  * Exception: Space forward uses text=" "         |
+--------------------------------------------------+
```

### Why IME Runs Before Keybindings

When the user presses Ctrl+C during Korean composition (preedit = "하"):

1. **Phase 0 (shortcuts)**: libitshell3 checks — Ctrl+C is not a language toggle or global shortcut. Pass through.
2. **Phase 1 (IME)**: Engine detects Ctrl modifier -> flushes "하" -> returns `{ committed: "하", forward_key: Ctrl+C }`
3. **Phase 2 (ghostty)**: Committed text "하" is sent to PTY via `ghostty_surface_key`. Then Ctrl+C goes through ghostty's keybinding system. If Ctrl+C is bound to a keybinding, it fires. If not, `ghostty_surface_key` encodes it as `0x03` (ETX).

This ensures the user's in-progress composition is preserved before any keybinding action.

**Verified by PoC** (`poc/01-ime-key-handling/`): All 10 test scenarios pass — arrows, Ctrl+C, Ctrl+D, Enter, Escape, Tab, backspace jamo-undo, shifted keys, and mixed compose-arrow-compose sequences all work correctly with libhangul.

### Phase 1: hangul_ic_process() Return-False Handling

When `hangul_ic_process()` returns `false`, libhangul rejected the key (it is not a valid jamo for the current keyboard layout). This occurs with punctuation, certain number keys, and other characters libhangul does not recognize.

**Correct handling:**

1. Call `hangul_ic_process(hic, ascii)`.
2. **Regardless of return value**: Check `hangul_ic_get_commit_string()` and `hangul_ic_get_preedit_string()`. libhangul may update these even when returning false (e.g., a syllable break may produce committed text before the rejected character).
3. **If `hangul_ic_process()` returned false**:
   - If composition was non-empty, flush remaining composition via `hangul_ic_flush()`.
   - Forward the rejected key to the terminal.
4. Populate `ImeResult` with any committed text, updated preedit, and the forwarded key.

**Example**: User types "ㅎ" then ".":
- `hangul_ic_process(hic, '.')` returns false (period is not a jamo).
- `hangul_ic_get_commit_string()` returns empty (no syllable break triggered).
- `hangul_ic_get_preedit_string()` still returns "ㅎ" (still composing).
- Since not consumed: flush "ㅎ", forward ".".
- Result: `{ committed: "ㅎ", preedit: null, forward_key: '.', preedit_changed: true }`.

**Verified by PoC** (`poc/02-ime-ghostty-real/poc-ghostty-real.m` lines 298–324).

---

## 4. Responsibility Matrix

| Responsibility | Owner | Rationale |
|---|---|---|
| HID keycode -> ASCII character | **libitshell3-ime** | IME needs ASCII for `hangul_ic_process()`. Mapping is layout-dependent (Korean 2-set vs 3-set). |
| HID keycode -> platform-native keycode | **libitshell3** | ghostty's key encoder uses platform-native keycodes (`uint32_t`). IME-independent. |
| Hangul composition (jamo assembly, backspace) | **libitshell3-ime** | Core IME logic. Wraps libhangul. |
| Modifier detection + flush decision | **libitshell3-ime** | Engine decides when Ctrl/Alt/Cmd flushes composition. Matches ibus-hangul/fcitx5-hangul pattern. All modifiers **flush** (commit), never reset (discard). |
| UCS-4 -> UTF-8 conversion | **libitshell3-ime** | libhangul outputs UCS-4. The rest of the system uses UTF-8. |
| Language toggle key detection | **libitshell3** | Configurable keybinding (한/영, Right Alt, Caps Lock). Not an IME concern. |
| Active input method switching | **libitshell3** | Calls `setActiveInputMethod(input_method)` when user toggles. |
| Flushing on input method switch | **libitshell3-ime** | `setActiveInputMethod()` flushes pending composition internally (atomically). |
| Keybinding interception (Cmd+V, Cmd+C) | **libitshell3 via ghostty** | Keybindings run in Phase 2, after IME has flushed. |
| Calling `ghostty_surface_key()` | **libitshell3** | Daemon translates ImeResult into ghostty API calls. |
| Calling `ghostty_surface_preedit()` | **libitshell3** | Daemon forwards preedit to ghostty's renderer overlay. |
| Terminal escape sequence encoding | **ghostty** (via `ghostty_surface_key`) | ghostty's KeyEncoder runs daemon-side. We do NOT write our own encoder. |
| PTY writes | **ghostty** (internal to `ghostty_surface_key`) | ghostty handles PTY I/O internally after encoding. |
| Sending preedit/render state to remote client | **libitshell3** (protocol layer) | Part of the FrameUpdate protocol. |
| Rendering cell data (including preedit) on screen | **it-shell3 app** (client) | Client renders cell data via Metal. Preedit cells are injected server-side via `ghostty_surface_preedit()` and delivered as regular cell data in I/P-frames — the client has no concept of which cells are preedit. |
| Per-session ImeEngine lifecycle | **libitshell3** | Creates one engine per session. Destroys on session close. Calls activate/deactivate on session-level focus change. Calls flush() on intra-session pane focus change. Engine is pane-agnostic — it has no knowledge of pane_id or session_id. |
| Routing ImeResult to the correct pane's PTY | **libitshell3** | Server tracks which pane is focused and directs ImeResult accordingly. Engine produces results; server routes them. |
| New pane inheriting active input method | **libitshell3** | New panes inherit the session's `active_input_method` automatically. No engine call needed — the shared engine already has the correct state. |
| Language indicator in FrameUpdate | **libitshell3** | Metadata field derived from `active_input_method` string (e.g., `"direct"` vs `"korean_2set"`). ghostty has no language state. See protocol doc 05 for wire encoding. |
| Composing-capable check | **libitshell3** | Derives from input method string: `"direct" = no`, anything else = yes. Runtime check: `engine.isEmpty()`. No `LanguageDescriptor` needed. |
| `display_width` / UAX #11 character width computation | **libitshell3** | East Asian Width property lookup (narrow/wide/ambiguous) for CellData encoding. IME engine has no knowledge of display width — it only deals with key events and composition text. |

### What libitshell3-ime Does NOT Do

- Does NOT know about PTYs, sockets, sessions, panes, or protocols.
- Does NOT encode terminal escape sequences (no VT knowledge).
- Does NOT detect language toggle keys (that's libitshell3's keybinding concern).
- Does NOT decide when to switch input methods (libitshell3 calls `setActiveInputMethod()`).
- Does NOT interact with ghostty APIs (no ghostty dependency).
- Does NOT manage candidate window UI (app layer concern, future).
- Does NOT enumerate or manage language lists (framework concern).
- Does NOT track or route to pane identifiers. The engine is a pure composition state machine.
