# IME Interface Contract v0.8 — Overview

> **Version**: v0.8
> **Date**: 2026-03-10
> **Part of the IME Interface Contract v0.8. See this file for the document index.**
> **Changes from v0.7**: Daemon behavioral content extracted to daemon design docs v0.3. See [Appendix J: Changes from v0.7](99-appendices.md#appendix-j-changes-from-v07).

## Document Index

| Document | Contents |
|----------|----------|
| 01-overview.md | Overview, processing pipeline, responsibility matrix |
| 02-types.md | KeyEvent, ImeResult, modifier flush policy, input method identifiers |
| 03-engine-interface.md | ImeEngine vtable, setActiveInputMethod, HangulImeEngine, MockImeEngine |
| 04-ghostty-integration.md | Reference — ghostty integration is defined in daemon design docs |
| 05-extensibility-and-deployment.md | Future extensibility, C API boundary, session persistence |
| 99-appendices.md | Change history appendices (A-J) |

---

# 01 — libitshell3 <-> libitshell3-ime Interface Contract

> **Status**: Draft v0.8 — Daemon behavioral content extracted to daemon design docs v0.3 (cross-team revision).
> **Supersedes**: [v0.7/01-overview.md](../v1.0-r7/01-overview.md), [v0.6/01-overview.md](../v1.0-r6/01-overview.md), [v0.5/01-interface-contract.md](../v1.0-r5/01-interface-contract.md), [v0.4/01-interface-contract.md](../v1.0-r4/01-interface-contract.md), [v0.3/01-interface-contract.md](../v1.0-r3/01-interface-contract.md), [v0.2/01-interface-contract.md](../v1.0-r2/01-interface-contract.md), [v0.1/01-interface-contract.md](../v1.0-r1/01-interface-contract.md)
> **Date**: 2026-03-10
> **Review participants**: protocol-architect, protocol-swe, cjk-specialist, ime-expert, principal-architect, ime-architect, ime-swe
> **PoC validation**: `poc/02-ime-ghostty-real/poc-ghostty-real.m` — 22/24 tests pass (2 skipped due to libghostty VT parser bug, not IME code); `poc/03-macos-ime-suppression/` — macOS IME suppression validated; `poc/04-libhangul-states/probe.c` — composition_state factual errors confirmed; `poc/05-preedit-visual/` — preedit-as-cell-data rendering validated
> **Changes from v0.7**: See [Appendix J: Changes from v0.7](99-appendices.md#appendix-j-changes-from-v07)

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

The daemon routes keys through a 3-phase pipeline. Phase 1 (IME processing) is defined by this contract; Phases 0 (global shortcuts, language toggle) and 2 (ghostty integration, PTY writes, preedit overlay) are defined in [daemon design doc 02 §4.2](../../../../../libitshell3/02-design-docs/daemon/draft/v1.0-r3/02-integration-boundaries.md#42-phase-0---1---2-key-routing).

### Phase 1: IME Engine Processing

```
processKey(KeyEvent) -> ImeResult

Engine internally:
- Checks modifiers (Ctrl/Alt/Cmd) -> flush + forward
- Checks non-printable (arrow/F-key) -> flush + forward
- Feeds printable to libhangul -> compose
- Handles "not consumed" (hangul_ic_process()
  returns false): flush + forward rejected key
- Returns committed/preedit/forward_key
```

The engine receives a `KeyEvent` and produces an `ImeResult`. It has no knowledge of what happens before (Phase 0) or after (Phase 2) — it is a pure composition state machine.

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

This matrix covers IME engine responsibilities only. Daemon-side responsibilities (routing, PTY writes, ghostty integration, lifecycle management) are defined in [daemon design doc 02 §4.9](../../../../../libitshell3/02-design-docs/daemon/draft/v1.0-r3/02-integration-boundaries.md#49-daemon-side-responsibility-matrix).

| Responsibility | Owner | Rationale |
|---|---|---|
| HID keycode -> ASCII character | **libitshell3-ime** | IME needs ASCII for `hangul_ic_process()`. Mapping is layout-dependent (Korean 2-set vs 3-set). |
| Hangul composition (jamo assembly, backspace) | **libitshell3-ime** | Core IME logic. Wraps libhangul. |
| Modifier detection + flush decision | **libitshell3-ime** | Engine decides when Ctrl/Alt/Cmd flushes composition. Matches ibus-hangul/fcitx5-hangul pattern. All modifiers **flush** (commit), never reset (discard). |
| UCS-4 -> UTF-8 conversion | **libitshell3-ime** | libhangul outputs UCS-4. The rest of the system uses UTF-8. |
| Flushing on input method switch | **libitshell3-ime** | `setActiveInputMethod()` flushes pending composition internally (atomically). |

### What libitshell3-ime Does NOT Do

- Does NOT know about PTYs, sockets, sessions, panes, or protocols.
- Does NOT encode terminal escape sequences (no VT knowledge).
- Does NOT detect language toggle keys (that's libitshell3's keybinding concern).
- Does NOT decide when to switch input methods (libitshell3 calls `setActiveInputMethod()`).
- Does NOT interact with ghostty APIs (no ghostty dependency).
- Does NOT manage candidate window UI (app layer concern, future).
- Does NOT enumerate or manage language lists (framework concern).
- Does NOT track or route to pane identifiers. The engine is a pure composition state machine.
