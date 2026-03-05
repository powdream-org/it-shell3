# AGENTS.md

> **Note**: `CLAUDE.md` is a symlink to this file (`AGENTS.md`). This is the canonical source.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**libitshell3** is a portable Zig library providing terminal multiplexer session management with first-class CJK input support, built on libghostty. The project consists of four components:

- **libitshell3** — Core library: daemon (PTY owner, session state, I/O mux), client (socket connection, protocol, surface feeder), binary protocol, PTY layer. Exports C API for Swift/other consumers.
- **libitshell3-ime** — Native IME engine in Zig (wraps libhangul for Korean). Purely algorithmic, no OS IME dependency. Covers English QWERTY + Korean 2-set.
- **it-shell3** — Terminal app (Swift/AppKit + libitshell3 + libghostty Metal GPU). macOS first, iOS later.
- **libghostty** — External dependency: terminal engine providing VT parser, font/Unicode, RenderState API, Metal rendering.

## Current State

The repository is in the **design/planning phase** — documentation only, no source code yet. Implementation begins with Phase 1 (daemon + client + RenderState pipeline).

## Build System (Planned)

Zig build system (`build.zig`) targeting Zig 0.14+. Will produce static `.a` and shared `.dylib`/`.so` libraries with C header export.

## Architecture

**Daemon + Client over Unix socket:**

```
Server (Daemon)                    Client (App)
┌─────────────────┐                ┌──────────────┐
│ PTY master FDs  │                │ UI Layer     │
│ Session state   │  Unix socket   │ (Swift/Metal)│
│ libitshell3-ime │◄──────────────►│              │
│ libghostty-vt   │  binary msgs   │ libghostty   │
│ I/O multiplexer │                │ surface      │
└─────────────────┘                └──────────────┘
```

**Protocol wire format:** 16-byte fixed header (`magic 0x4954` + version + flags + msg_type + length + sequence) with variable payload. Max payload 16 MiB.

**Key design decisions:**
- IME is native Zig (not OS IME) — eliminates iOS async UITextInput and macOS NSTextInputClient issues
- RenderState protocol (structured cell data with dirty tracking) instead of VT re-serialization
- Session hierarchy: Session > Tab > Pane (binary split tree, JSON-serializable)
- Capability negotiation at handshake (not version guessing)

## Documentation Structure

- `docs/libitshell3/` — 15 design documents (00–14) covering project overview, API analysis, protocol, PTY, CJK input, architecture, testing strategy, and validation
- `docs/libitshell3/design/server-client-protocols/` — 6 detailed protocol specs (handshake, session/pane mgmt, input/renderstate, CJK preedit, flow control)
- `docs/libitshell3-ime/` — 7 documents covering Korean composition rules, libhangul API, IME architecture, integration protocol, build/licensing

## Reference Codebases

Located at `~/dev/git/references/`:

| Reference | Purpose |
|-----------|---------|
| `ghostty/` | Terminal engine source (core dependency) |
| `cmux/` | libghostty-based macOS terminal (embedding pattern) |
| `tmux/` | Daemon/protocol pattern reference |
| `zellij/` | Multi-threaded architecture reference |
| `iTerm2/` | tmux -CC integration, native UI mapping |

## Dependencies

- **libghostty** (Zig) — Terminal engine, will be git submodule. API not yet stable; pin commits and use abstraction layer.
- **libhangul** (C, LGPL-2.1) — Korean Hangul composition for libitshell3-ime. Must handle LGPL compliance (dynamic linking or offer source).

## Development Phases

1. Daemon + client + RenderState pipeline
2. Native IME (QWERTY + Korean 2-set) — parallel with Phase 1
3. Multi-pane, tabs, sessions, layout
4. Session persistence — parallel with Phase 3
5. CJK preedit sync protocol
6. iOS client + network TLS
7. Polish: config, theming, 3-set Korean

## Conventions

> **⚠️ MANDATORY: You MUST read and strictly follow all convention docs under `docs/conventions/` before making any changes. No exceptions.**

- [**Commit Messages**](docs/conventions/commit-messages.md) — Conventional commits format. **English only.**
- [**Review Notes & Handover Docs**](docs/conventions/review-and-handover-docs.md) — Naming conventions, document format, and content requirements for all review artifacts (review notes, resolutions, research reports, handovers).

## Work Styles

> **⚠️ MANDATORY: You(main agent, team leader) MUST read and strictly follow all work-style docs under `docs/work-styles/` before starting any team-based work. No exceptions.**
>
> **You are a facilitator, NOT a doer.** Never do research, writing, or implementation yourself — always delegate to teammates. Never micromanage teammates with specific instructions like "change line X to Y" — state the goal and let them figure out the approach. Never proxy messages between agents — they must communicate directly with each other.

- [**Agent Team Design Workflow**](docs/work-styles/agent-team-design-workflow.md) — **Defines how you operate.** Covers the full lifecycle: parallel drafting (Phase 1) → review discussion (Phase 2) → cross-component review (Phase 2b) → applying revisions (Phase 3) → handover document (Phase 4). Also defines custom agent registration and team communication patterns.
- [**Agent Team Definitions**](docs/work-styles/agent-team-definition.md) — **Defines who you work with.** Lists available agent teams, their purposes, and agent file locations under `.claude/agents/`.
