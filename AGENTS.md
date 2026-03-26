# AGENTS.md

> **Note**: `CLAUDE.md` is a symlink to this file (`AGENTS.md`). This is the
> canonical source.

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

**it-shell3** is a terminal ecosystem providing terminal multiplexer session
management with first-class CJK input support, built on libghostty. The project
consists of three libraries and two applications:

### Applications

- **it-shell3** — Client terminal app (Swift/AppKit + libghostty Metal GPU).
  macOS first, iOS later. Connects to daemon.
- **it-shell3-daemon** — Server daemon process (Zig binary): PTY owner, session
  persistence, I/O mux, client connections via Unix socket. Runs as LaunchAgent
  or standalone process.

### Libraries

- **libitshell3** — Core Zig library: session/pane state, PTY layer, RenderState
  export/import. Exports C API for Swift/other consumers.
- **libitshell3-protocol** — Wire protocol library shared by daemon and client:
  message types, serialization, capability negotiation, CJK preedit sync.
- **libitshell3-ime** — Native IME engine in Zig (wraps libhangul for Korean).
  Purely algorithmic, no OS IME dependency. Covers English QWERTY + Korean
  2-set.
- **libghostty** — External dependency: terminal engine providing VT parser,
  font/Unicode, RenderState API, Metal rendering.

## Current State

The repository is in the **design/planning phase** — documentation only, no
source code yet. Implementation begins with Phase 1 (daemon + client +
RenderState pipeline).

## Build System (Planned)

Zig build system (`build.zig`) targeting Zig 0.14+. Will produce static `.a` and
shared `.dylib`/`.so` libraries with C header export.

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

**Protocol wire format:** 16-byte fixed header (`magic 0x4954` + version +
flags + msg_type + length + sequence) with variable payload. Max payload 16 MiB.

**Key design decisions:**

- IME is native Zig (not OS IME) — eliminates iOS async UITextInput and macOS
  NSTextInputClient issues
- RenderState protocol (structured cell data with dirty tracking) instead of VT
  re-serialization
- Session hierarchy: Session > Pane (binary split tree, JSON-serializable)
- Capability negotiation at handshake (not version guessing)

**Daemon lifecycle:** The daemon binary is bundled inside the client app
(`it-shell3.app/Contents/Helpers/it-shell3-daemon`). Distributed as notarized
DMG or Homebrew Cask (not Mac App Store — LaunchAgent requires sandbox escape).
On launch, the client connects to the Unix socket; if the daemon is not running,
it registers a LaunchAgent and starts it. For remote (SSH) connections, the
daemon is started via `fork+exec` without LaunchAgent (similar to `tmux` server
auto-start); version compatibility is ensured via protocol negotiation. See
daemon design docs for lifecycle details, version conflict handling, and
reconnection procedures.

## Documentation Structure

- `docs/modules/libitshell3/` — 15 design documents (00–14) covering project
  overview, API analysis, protocol, PTY, CJK input, architecture, testing
  strategy, and validation
- `docs/modules/libitshell3/design/server-client-protocols/` — 6 detailed
  protocol specs (handshake, session/pane mgmt, input/renderstate, CJK preedit,
  flow control)
- `docs/modules/libitshell3-ime/` — 7 documents covering Korean composition
  rules, libhangul API, IME architecture, integration protocol, build/licensing
- [**`docs/insights/`**](docs/insights/) — Cross-cutting architectural insights.
  Read before design discussions to avoid re-researching solved questions.
  - [Design Principles](docs/insights/design-principles.md) — Living document of
    validated protocol design principles, architectural insights, and process
    lessons. Updated after each revision cycle.
  - [Reference Codebase Learnings](docs/insights/reference-codebase-learnings.md)
    — Multi-client output delivery, dirty tracking, frame recovery, concurrency,
    and backpressure patterns from ghostty, tmux, zellij.

## Vendored Dependencies

Located at `vendors/`:

- **ghostty** (Zig) — Terminal engine (libghostty). API not yet stable; pin
  commits and use abstraction layer.
- **libhangul** (C, LGPL-2.1) — Korean Hangul composition for libitshell3-ime.
  Must handle LGPL compliance (dynamic linking or offer source).

## Reference Codebases

External projects used for design reference (not vendored — local paths are in
auto memory):

| Reference                                      | Purpose                                             |
| ---------------------------------------------- | --------------------------------------------------- |
| [tmux](https://github.com/tmux/tmux)           | Daemon/protocol pattern reference                   |
| [zellij](https://github.com/zellij-org/zellij) | Multi-threaded architecture reference               |
| [iTerm2](https://github.com/gnachman/iTerm2)   | tmux -CC integration, native UI mapping             |
| [cmux](https://github.com/manaflow-ai/cmux)    | libghostty-based macOS terminal (embedding pattern) |

## Development Phases

See `docs/superpowers/plans/ROADMAP.md` for the detailed implementation roadmap
(Plans 1-7+), dependency graph, per-plan status, and test/coverage commands.

High-level phases (updated to reflect actual implementation order):

1. **Core daemon** — Types, event loop, PTY, socket, ghostty integration (Done)
2. **Wire protocol** — Message types, framing, handshake, local transport (Done)
3. **Frame pipeline** — Ring buffer, I/P-frame delivery, dirty tracking
4. **IME integration** — Wire libitshell3-ime into daemon event loop
5. **Runtime policies** — Adaptive coalescing, health escalation, flow control
6. **Cascades** — Pane exit, session destroy, client disconnect atomics
7. **SSH transport** — libssh2 client in libitshell3-protocol (spec §2.2,
   §5.5.2)
8. **macOS client app** — Swift/AppKit + libghostty Metal GPU
9. **iOS client** — UIKit adaptation + SSH-only connectivity
10. **Polish** — Config, theming, 3-set Korean, session persistence

## Conventions

> **⚠️ MANDATORY: You MUST read and strictly follow all convention docs under
> `docs/conventions/` before making any changes. No exceptions.**

- [**Zig Naming**](docs/conventions/zig-naming.md) — No abbreviations, buffer
  size constants, getter patterns. Applies to all Zig source.
- [**Commit Messages**](docs/conventions/commit-messages.md) — Conventional
  commits format. **English only.**
- [**Document Artifact Conventions**](docs/conventions/artifacts/documents/01-overview.md)
  — Naming, format, and content rules for all document artifacts (review notes,
  handovers, design resolutions, research reports, cross-team requests).
- [**Architecture Decision Records**](docs/conventions/artifacts/documents/10-adr.md)
  — Permanent log of significant design/implementation decisions. **Use
  `/adr <topic>` for any meaningful owner decision** (technology selection,
  protocol tradeoffs, architectural patterns, implementation strategy). The
  agent researches context and writes the full ADR autonomously.

### Design Document Metadata

Spec documents (numbered `01-*.md` through `99-*.md`) use bullet-item metadata
immediately after the `# Title` heading. Only these two properties are allowed:

```markdown
# Document Title

- **Date**: YYYY-MM-DD
- **Scope**: one-line description of what this document covers
```

Do NOT add Status, Version, Author, Depends on, Changes from, or any other
metadata. Status and version are encoded in the directory path
(`draft/v1.0-rN/`). Author and dependency info belong in changelogs or
resolution docs, not in the spec header.

Process artifacts (review notes, design resolutions, verification issues,
cross-team requests) have their own metadata conventions defined in
`docs/conventions/artifacts/documents/`.

### Cross-Document References

The deciding factor is **whether two documents share a revision cycle** (move
together), not whether they are in the same module.

- **Same revision cycle** (e.g., files within
  `interface-contract/draft/v1.0-r9/`): relative paths are fine — they always
  move together.
- **Independent revision cycles** (e.g., `interface-contract/draft/v1.0-r9/` →
  `behavior/draft/v1.0-r1/`, or any cross-module reference): **do NOT use exact
  file path links**. Exact paths encode revision numbers that break every time
  the target is revised.

Instead, use a loose prose reference:

```markdown
<!-- Avoid: exact path, breaks on every revision -->

See
[behavior/draft/v1.0-r1/02-scenario-matrix.md](../../../behavior/draft/v1.0-r1/02-scenario-matrix.md).
See
[daemon design doc 02 §4.2](../../../../../libitshell3/.../v1.0-r3/02-integration-boundaries.md#42-...).

<!-- Prefer: name the doc without the path; omit section numbers (they change too) -->

See `02-scenario-matrix.md` in the behavior docs for the complete scenario
matrix. See the `libitshell3` daemon design docs for details. See the
`libitshell3-protocol` server-client-protocols docs for details.
```

## CRITICAL: Never Change the Working Directory

**NEVER use `cd` to change the current directory from the project root.** Almost
all operations can be performed by passing the correct path to commands and
tools. Changing directories causes confusion and errors in subsequent
operations.

In the rare cases where changing directory is absolutely unavoidable, use a
subshell so the directory change does not persist:

```bash
(cd other-dir; command;)
```

## Work Styles

> **⚠️ MANDATORY: You(main agent, team leader) MUST read and strictly follow all
> work-style docs under `docs/work-styles/` before starting any team-based work.
> No exceptions.**
>
> **You are a facilitator, NOT a doer.** Never do research, writing, or
> implementation yourself — always delegate to teammates. Never micromanage
> teammates with specific instructions like "change line X to Y" — state the
> goal and let them figure out the approach. Never proxy messages between agents
> — they must communicate directly with each other.
>
> **⚠️ CRITICAL — Post-compaction teammate recovery:** After a context
> compaction (conversation compression), you lose awareness of previously
> spawned teammates. This is the **single most important thing** to handle after
> compaction. Immediately:
>
> 1. Run `TaskList` to discover all tracked tasks and their owners/statuses.
> 2. Identify any tasks still marked `in_progress` — these may have active
>    teammates working on them, or they may be zombies (agents from the
>    pre-compaction context that are no longer reachable).
> 3. For each `in_progress` task, attempt to contact the owning teammate (via
>    `SendMessage`) to verify they are alive and still working.
> 4. Shut down confirmed zombies and clean up their stale task entries.
> 5. Only after recovery is complete should you resume or start new work.

- [**Overview**](docs/work-styles/01-overview.md) — Entry point: how we work,
  document index.
- [**Team Collaboration**](docs/work-styles/02-team-collaboration.md) — Team
  structure, roles, communication rules, consensus policy, lessons learned.
- [**Design Workflow**](docs/work-styles/03-design-workflow/) — Rationale and
  reference for the revision/review cycles. **Execution is driven by the
  `design-doc-revision` skill** (`.claude/skills/design-doc-revision/`).
- [**PoC Workflow**](docs/work-styles/04-poc-workflow.md) — When, why, and how
  to run Proof-of-Concept experiments.
