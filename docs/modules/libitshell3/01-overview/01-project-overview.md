# libitshell3: Project Overview

## Vision

**libitshell3** is a portable Zig library that provides a terminal multiplexer session layer on top of **libghostty**. It exports C headers and shared libraries (`.dylib` / `.so`) for consumption by higher-level terminal emulator applications — starting with the **it-shell3** terminal emulator app for macOS, with future Linux support.

The library provides tmux/zellij-like session persistence with first-class CJK input composition support, including inside AI agent chat interfaces (Claude Code, Codex, Cursor).

### Scope Clarification

- **libitshell3**: The portable Zig library (this project) — daemon, client, protocol, PTY management, CJK preedit sync
- **libitshell3-ime**: A separate portable Zig library — native IME engine for English (QWERTY) and Korean (2-set, 3-set). No OS IME dependency. Purely algorithmic. Eliminates the need for a GUI-capable daemon process.
- **it-shell3**: The future complete terminal emulator app for macOS and iOS (starting with macOS) that consumes libitshell3 + libitshell3-ime + libghostty. It is a full replacement terminal emulator, not a wrapper or plugin.

## Problem Statement

Existing terminal multiplexers (tmux, zellij, screen) have fundamental limitations:

1. **CJK Input Composition**: IME preedit state (Korean Jamo decomposition, Japanese Kana-to-Kanji, Chinese Pinyin) is not properly synchronized between client and server. This causes broken input when composing CJK text inside multiplexed sessions.

2. **AI Agent Chat Interfaces**: Modern AI coding tools (Claude Code, Codex CLI, Cursor terminal) use custom input areas that need:
   - Shift+Enter for line breaks (not command execution)
   - Cmd+C / Cmd+V for clipboard (not SIGINT / raw paste)
   - Proper CJK composition within the agent's input buffer

3. **Cross-Device Session Continuity**: Sessions should persist across terminal app restarts and be accessible from multiple devices (macOS + iOS).

## Why libghostty?

Instead of writing a custom VT emulator, we leverage Ghostty's battle-tested terminal engine because:

- **CJK-ready Unicode**: Full grapheme clustering, emoji variation selectors, proper wide character handling
- **IME Preedit API**: Native `ghostty_surface_preedit()` and `ghostty_surface_ime_point()` for input composition
- **Metal Rendering**: GPU-accelerated rendering on macOS/iOS via Metal
- **HarfBuzz Font Shaping**: Proper CJK glyph shaping and ligatures
- **Embeddable C API**: `ghostty.h` with opaque types (`ghostty_app_t`, `ghostty_config_t`, `ghostty_surface_t`)
- **Split Support**: Built-in split direction, navigation, and resize primitives

## Architecture Summary

```
┌─────────────────────────────────────────────────────────┐
│                    it-shell3 Client                      │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ libghostty   │  │ IME/Preedit  │  │  Client-Side  │  │
│  │ Surface      │  │ Handler      │  │  Protocol     │  │
│  │ (Metal GPU)  │  │ (CJK Compose)│  │  Manager      │  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
└──────────────────────────┬──────────────────────────────┘
                           │ Unix Domain Socket / IPC
┌──────────────────────────┴──────────────────────────────┐
│                    it-shell3 Daemon                      │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ Session      │  │ PTY Manager  │  │  CJK Protocol │  │
│  │ Manager      │  │ (per-pane)   │  │  Extensions   │  │
│  │              │  │              │  │  (Preedit Sync)│  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Key Design Goals

1. **Session Persistence**: Daemon process keeps PTY sessions alive across client disconnects
2. **CJK Preedit Sync**: IME composition state synchronized between client(s) and daemon
3. **AI Agent Awareness**: Special input mode detection for Shift+Enter, Cmd+C/V in agent contexts
4. **Cross-Platform Client**: macOS (native) and iOS (via libghostty embedded apprt)
5. **Backward Compatibility**: Graceful fallback when CJK extensions aren't supported

## Reference Codebases

All reference code is available at `~/dev/git/references/`:

| Reference | Purpose | Language |
|-----------|---------|----------|
| `ghostty/` | Terminal engine (libghostty source) | Zig |
| `cmux/` | Existing libghostty-based macOS terminal app | Swift |
| `tmux/` | Canonical terminal multiplexer | C |
| `zellij/` | Modern terminal multiplexer | Rust |
| `iTerm2/` | macOS terminal with tmux integration | ObjC/Swift |
| `design-cjk-protocol-extensions.md` | CJK protocol extension design | Spec |
| `TMUX_CLIENT_PROTOCOL_ANALYSIS.md` | tmux client protocol spec | Spec |
| `tmux-server-protocol-analysis.md` | tmux server protocol spec | Spec |

## Document Index

| Document | Contents |
|----------|----------|
| [01-libghostty-api.md](./01-libghostty-api.md) | libghostty C API surface, types, and embedding patterns |
| [02-server-client-protocol.md](./02-server-client-protocol.md) | Protocol designs from tmux, zellij, cmux |
| [03-session-persistence.md](./03-session-persistence.md) | Session persistence mechanisms and strategies |
| [04-pty-management.md](./04-pty-management.md) | PTY creation, forwarding, and proxying |
| [05-cjk-input-composition.md](./05-cjk-input-composition.md) | CJK/IME handling across the stack |
| [06-input-handling.md](./06-input-handling.md) | Keyboard input, shortcuts, Shift+Enter, Cmd+C/V |
| [07-window-pane-management.md](./07-window-pane-management.md) | Window/pane hierarchy and layout systems |
| [08-feasibility-analysis.md](./08-feasibility-analysis.md) | Feasibility assessment and risk analysis |
| [09-recommended-architecture.md](./09-recommended-architecture.md) | Proposed architecture and technology choices |
| [10-iterm2-tmux-integration.md](./10-iterm2-tmux-integration.md) | iTerm2 tmux -CC control mode deep dive |
| [11-testing-strategy.md](./11-testing-strategy.md) | Testing tiers, coverage estimate, CI pipeline |
| [12-server-side-ime-architecture.md](./12-server-side-ime-architecture.md) | **SUPERSEDED** — Server-side IME processing (replaced by native IME in libitshell3-ime) |
| [13-render-state-protocol.md](./13-render-state-protocol.md) | Server-side rendering, RenderState extraction, wire format, client GPU pipeline |
| [14-architecture-validation-report.md](./14-architecture-validation-report.md) | Full architecture review, native IME decision, risk matrix, phased development path |

### Related: libitshell3-ime Documentation

See [../../libitshell3-ime/01-overview/00-project-overview.md](../../libitshell3-ime/01-overview/00-project-overview.md) for the native IME library documentation, including:
- Rationale (iOS vs macOS IME history, 4 failed iterations)
- libhangul API reference
- Korean composition rules
- Architecture and integration with libitshell3
- Build system and LGPL-2.1 licensing
