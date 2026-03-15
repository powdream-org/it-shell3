# IME Interface Contract — Overview

## Document Index

| Document                           | Contents                                                                                               |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------ |
| 01-overview.md                     | Overview, design principles, responsibility matrix                                                     |
| 02-types.md                        | KeyEvent, ImeResult, modifier flush policy, input method identifiers                                   |
| 03-engine-interface.md             | ImeEngine vtable, setActiveInputMethod behavior, MockImeEngine                                         |
| 04-ghostty-integration.md          | Reference — ghostty integration is defined in daemon design docs; memory ownership and buffer lifetime |
| 05-extensibility-and-deployment.md | Future extensibility, C API boundary, session persistence                                              |
| 99-appendices.md                   | Change history appendices (A-K)                                                                        |

> **Scope**: This document set covers the caller-facing API only. For engine
> implementation details (internal algorithms, libhangul API usage, buffer
> layout, struct fields), see [behavior/](../../../behavior/).

> **Editorial policy**: The interface contract MUST NOT include internal
> implementation details of any `ImeEngine` concrete type or language-specific
> internals. Implementation content (internal decision trees, libhangul API call
> sequences, concrete struct fields, buffer layouts) belongs in the
> [behavior docs](../../../behavior/).

---

## 1. Overview

This document defines the **exact interface** between libitshell3 (terminal
multiplexer daemon) and libitshell3-ime (native IME engine). It specifies:

- The types that cross the boundary (input and output)
- Who is responsible for what
- How the IME output maps to libghostty API calls
- Memory ownership and lifetime rules
- Future extensibility for Japanese/Chinese without v1 overhead

### Design Principles

1. **Single interface for all languages.** No engine-type flags, no capability
   negotiation. Korean simply never populates candidates. (Informed by
   fcitx5/ibus: both use one `keyEvent` method for all languages.)
2. **Engine owns composition decisions.** The IME engine decides when to flush
   on modifiers, not the framework. (Informed by ibus-hangul, fcitx5-hangul
   patterns.)
3. **Struct return over callbacks.** `processKey()` returns an `ImeResult`
   struct — simpler and more testable than side-effect callbacks. Candidate
   lists (future) use a separate optional callback channel.
4. **Don't make the common path pay for the uncommon path.** English/Korean
   processing adds zero overhead for future Japanese/Chinese candidate support.
5. **Testable via trait.** libitshell3 depends on an `ImeEngine` interface, not
   the concrete implementation. Mock injection for tests.
6. **Framework owns input method management.** libitshell3 (the framework)
   decides what input methods are available and which is active. The engine
   receives `setActiveInputMethod()` calls and processes keys accordingly.
   (Informed by fcitx5/ibus: language enumeration and toggle logic live in the
   framework, not in individual engines.)

---

## 2. Responsibility Matrix

This matrix covers IME engine responsibilities only.

| Responsibility                                | Owner               | Rationale                                                                                                                                                 |
| --------------------------------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| HID keycode -> ASCII character                | **libitshell3-ime** | IME needs ASCII for `hangul_ic_process()`. Mapping is layout-dependent (Korean 2-set vs 3-set).                                                           |
| Hangul composition (jamo assembly, backspace) | **libitshell3-ime** | Core IME logic. Wraps libhangul.                                                                                                                          |
| Modifier detection + flush decision           | **libitshell3-ime** | Engine decides when Ctrl/Alt/Cmd flushes composition. Matches ibus-hangul/fcitx5-hangul pattern. All modifiers **flush** (commit), never reset (discard). |
| UCS-4 -> UTF-8 conversion                     | **libitshell3-ime** | libhangul outputs UCS-4. The rest of the system uses UTF-8.                                                                                               |
| Flushing on input method switch               | **libitshell3-ime** | `setActiveInputMethod()` flushes pending composition internally (atomically).                                                                             |

### What libitshell3-ime Does NOT Do

- Does NOT know about PTYs, sockets, sessions, panes, or protocols.
- Does NOT encode terminal escape sequences (no VT knowledge).
- Does NOT detect language toggle keys (that's libitshell3's keybinding
  concern).
- Does NOT decide when to switch input methods (libitshell3 calls
  `setActiveInputMethod()`).
- Does NOT interact with ghostty APIs (no ghostty dependency).
- Does NOT manage candidate window UI (app layer concern, future).
- Does NOT enumerate or manage language lists (framework concern).
- Does NOT track or route to pane identifiers. The engine is a pure composition
  state machine.
