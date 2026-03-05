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
- [**`docs/insights/`**](docs/insights/) — Cross-cutting architectural insights distilled from reference codebase research. Read before design discussions to avoid re-researching solved questions.
  - [Reference Codebase Learnings](docs/insights/reference-codebase-learnings.md) — Multi-client output delivery, dirty tracking, frame recovery, concurrency, and backpressure patterns from ghostty, tmux, zellij.

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
- [**Document Artifact Conventions**](docs/conventions/artifacts/documents/01-overview.md) — Naming, format, and content rules for all document artifacts (review notes, handovers, design resolutions, research reports, cross-team requests).

## Work Styles

> **⚠️ MANDATORY: You(main agent, team leader) MUST read and strictly follow all work-style docs under `docs/work-styles/` before starting any team-based work. No exceptions.**
>
> **You are a facilitator, NOT a doer.** Never do research, writing, or implementation yourself — always delegate to teammates. Never micromanage teammates with specific instructions like "change line X to Y" — state the goal and let them figure out the approach. Never proxy messages between agents — they must communicate directly with each other.
>
> **⚠️ CRITICAL — Post-compaction teammate recovery:** After a context compaction (conversation compression), you lose awareness of previously spawned teammates. This is the **single most important thing** to handle after compaction. Immediately:
> 1. Run `TaskList` to discover all tracked tasks and their owners/statuses.
> 2. Identify any tasks still marked `in_progress` — these may have active teammates working on them, or they may be zombies (agents from the pre-compaction context that are no longer reachable).
> 3. For each `in_progress` task, attempt to contact the owning teammate (via `SendMessage`) to verify they are alive and still working.
> 4. Shut down confirmed zombies and clean up their stale task entries.
> 5. Only after recovery is complete should you resume or start new work.

- [**Overview**](docs/work-styles/01-overview.md) — Entry point: how we work, document index.
- [**Team Collaboration**](docs/work-styles/02-team-collaboration.md) — Team structure, roles, communication rules, consensus policy, lessons learned.
- [**Design Workflow**](docs/work-styles/03-design-workflow.md) — **Defines how you operate.** Revision cycle (discussion → resolution → writing → verification) and Review cycle (owner review → review notes → handover).
- [**PoC Workflow**](docs/work-styles/04-poc-workflow.md) — When, why, and how to run Proof-of-Concept experiments.
