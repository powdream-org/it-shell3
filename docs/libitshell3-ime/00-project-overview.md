# libitshell3-ime: Project Overview

## What Is libitshell3-ime?

**libitshell3-ime** is a portable Zig library that provides a native Input Method Editor (IME) engine for terminal input. It wraps **libhangul** (C, LGPL-2.1) for Korean composition and implements English QWERTY layout mapping directly. It has **zero OS IME dependency** — no NSTextInputContext, no UITextInput, no window server connection needed.

The library is consumed by **libitshell3** (the terminal multiplexer session layer), which runs as a headless daemon. Together, they enable correct CJK text input in terminal sessions without requiring any GUI process.

### Scope

| Responsibility | In Scope | Out of Scope |
|---|---|---|
| English QWERTY layout | HID keycode → ASCII character mapping | Non-QWERTY Latin layouts (Dvorak, Colemak) — future |
| Korean 2-set (두벌식) | Full Hangul composition via libhangul | — |
| Korean 3-set variants | Sebeolsik 390, Final, Noshift, etc. via libhangul | — |
| Korean Romaja | Latin-to-Hangul transliteration via libhangul | — |
| Modifier key handling | Flush composition on Ctrl/Alt/Cmd combos, pass through | — |
| Arrow/function keys | Flush composition, pass through to terminal | — |
| Backspace during composition | Jamo-level undo (한→하→ㅎ→empty) via libhangul | — |
| Japanese (future) | — | libkkc or libmozc integration |
| Chinese (future) | — | librime integration |
| Candidate window UI | — | App layer responsibility |

### Relationship to Other Components

```
┌──────────────────────────────────────────────────────────────┐
│                      it-shell3 App                            │
│  (macOS: AppKit/Metal, iOS: UIKit/Metal + custom keyboard)   │
│                                                               │
│  Raw HID keycode + modifiers ──────────────────────┐         │
│                                                     │         │
│              rendered terminal state                │         │
│              ◄───────────────────────               │         │
└─────────────────────────────────────────────────────┼─────────┘
                                                      │
                          Unix Domain Socket / IPC    │
                                                      │
┌─────────────────────────────────────────────────────┼─────────┐
│                   libitshell3 Daemon                 │         │
│                                                     ▼         │
│  ┌─────────────────┐    ┌──────────────────────────────────┐ │
│  │ Session/PTY      │    │       libitshell3-ime             │ │
│  │ Manager          │    │                                   │ │
│  │                  │    │  HID keycode + layout ID          │ │
│  │  PTY write ◄─────┤    │        │                          │ │
│  │                  │    │        ▼                          │ │
│  │  preedit ────────┤    │  Layout Mapper (HID → character) │ │
│  │  events          │    │        │                          │ │
│  │                  │    │        ▼                          │ │
│  │                  │    │  Composition Engine (libhangul)   │ │
│  │                  │    │        │                          │ │
│  │                  │    │        ▼                          │ │
│  │                  │    │  ImeResult { committed, preedit,  │ │
│  │                  │    │             forward_key }         │ │
│  └─────────────────┘    └──────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

## Why Build a Native IME?

See [01-rationale.md](./01-rationale.md) for the full history. In brief:

1. **iOS's UITextInput is asynchronous** — the macOS `interpretKeyEvents()` accumulator pattern fails on iOS (empty 98.4% of the time), causing text doubling and broken Korean input.
2. **macOS NSTextInputContext requires a GUI process** — a daemon using `interpretKeyEvents()` must be an LSUIElement app with window server access, not a true LaunchDaemon.
3. **NSEvent construction is fragile** — Korean input in macOS depends on undocumented NSEvent object identity; synthetic events may break composition.
4. **Native IME eliminates all platform differences** — one deterministic code path for macOS, iOS, and future Linux.

## Document Index

| Document | Contents |
|----------|----------|
| [00-project-overview.md](./00-project-overview.md) | This document — scope, relationships, rationale summary |
| [01-rationale.md](./01-rationale.md) | Full history: iOS vs macOS IME, 4 failed iterations, why native IME |
| [02-libhangul-api.md](./02-libhangul-api.md) | Complete libhangul C API reference |
| [03-hangul-composition.md](./03-hangul-composition.md) | Korean composition rules, jamo tables, state machine |
| [04-architecture.md](./04-architecture.md) | libitshell3-ime architecture, key processing flow, Zig wrapper design |
| [05-integration-with-libitshell3.md](./05-integration-with-libitshell3.md) | How libitshell3-ime integrates with the libitshell3 daemon |
| [06-build-and-licensing.md](./06-build-and-licensing.md) | Build system, libhangul compilation, LGPL-2.1 compliance |

## Reference Codebases

| Reference | Path | Purpose |
|-----------|------|---------|
| libhangul | https://github.com/libhangul/libhangul | Korean composition engine (C, LGPL-2.1) |
| ibus-hangul | https://github.com/libhangul/ibus-hangul | Reference: how ibus wraps libhangul |
| fcitx5-hangul | https://github.com/fcitx/fcitx5-hangul | Reference: how fcitx5 wraps libhangul |
| it-shell (prior project) | `../cjk-compatible-terminal-for-ipad/` | The iOS terminal project where we discovered the iOS IME problems |
| Ghostty SurfaceView_AppKit | `../cjk-compatible-terminal-for-ipad/ghostty/macos/Sources/Ghostty/SurfaceView_AppKit.swift` | macOS `interpretKeyEvents` reference implementation |
| it-shell TerminalSurfaceView | `../cjk-compatible-terminal-for-ipad/ios/Sources/Terminal/TerminalSurfaceView.swift` | iOS `pendingKeyInfo` pattern (v2.4) |
