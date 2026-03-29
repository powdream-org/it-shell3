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
- **libitshell3-transport** — Transport layer library: Unix domain socket
  client/server, socket path management.
- **libitshell3-ime** — Native IME engine in Zig (wraps libhangul for Korean).
  Purely algorithmic, no OS IME dependency. Covers English QWERTY + Korean
  2-set.
- **libghostty** — External dependency: terminal engine providing VT parser,
  font/Unicode, RenderState API, Metal rendering.

## Current State

Three library modules are under active implementation. See
[`ROADMAP.md`](docs/superpowers/plans/ROADMAP.md) for per-plan status.

| Module                | Status                           |
| --------------------- | -------------------------------- |
| libitshell3-protocol  | Implemented, spec alignment next |
| libitshell3-transport | Implemented                      |
| libitshell3-ime       | Implemented (v0.7.0 finalized)   |
| libitshell3           | Implemented, spec alignment next |

Applications (it-shell3 client, it-shell3-daemon) are not yet started.

## Build & Test

**Prerequisites:** [mise](https://mise.jdx.dev/), Docker (for Linux tests and
coverage)

Zig build system (`build.zig`) per module. Managed via `mise` tasks:

```bash
mise run test:macos                # All modules — Debug
mise run test:macos:release-safe   # All modules — ReleaseSafe
mise run test:coverage             # kcov in Docker (Linux)
mise run test:linux                # All modules in Docker — Debug
mise run build:docker:zig-kcov     # Build the kcov Docker image
```

Single-module test (from project root):

```bash
(cd modules/libitshell3 && zig build test --summary all)
```

### Why Docker for coverage?

kcov cannot parse macOS DWARF debug info — it only works with Linux ELF
binaries. `Dockerfile.kcov` builds a `zig-kcov` image (kcov + mise + Zig
pre-installed) so macOS developers can produce ELF binaries and run coverage
inside a Linux container via `mise run test:coverage`.

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

- `docs/modules/libitshell3/` — Overview and design docs (daemon architecture,
  daemon behavior)
- `docs/modules/libitshell3-protocol/` — Protocol design docs
  (server-client-protocols)
- `docs/modules/libitshell3-ime/` — Overview and design docs
  (interface-contract, behavior)
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

See [`docs/superpowers/plans/ROADMAP.md`](docs/superpowers/plans/ROADMAP.md) for
the detailed implementation roadmap (Plans 1-16+), dependency graph, per-plan
status, and test/coverage commands.

## Conventions

> **⚠️ MANDATORY: You MUST read and strictly follow all convention docs under
> `docs/conventions/` before making any changes. No exceptions.**

- [**Zig Coding**](docs/conventions/zig-coding.md) — Standard-width integers
  only (no arbitrary u3/u5/u19). Packed struct and Unicode codepoint exceptions.
- [**Zig Naming**](docs/conventions/zig-naming.md) — No abbreviations, buffer
  size constants, getter patterns. Applies to all Zig source.
- [**Zig Documentation**](docs/conventions/zig-documentation.md) — Doc comment
  rules, spec reference policy (no section numbers), TODO format.
- [**Zig Testing**](docs/conventions/zig-testing.md) — Inline unit tests
  (implementer) vs spec compliance tests (QA). File naming, test naming,
  ownership rules.
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

> **⚠️ MANDATORY:** Read
> [`docs/conventions/design-document-metadata.md`](docs/conventions/design-document-metadata.md)
> before creating or editing any spec document.

### Cross-Document References

> **⚠️ MANDATORY:** Read
> [`docs/conventions/cross-document-references.md`](docs/conventions/cross-document-references.md)
> before adding cross-document links.

## CRITICAL: Never Overwrite Working Tree with Git Checkout

**NEVER use `git checkout <ref> -- <path>` to compare or restore files in a
dirty working tree.** This overwrites uncommitted changes and can destroy agent
work in progress. Use non-destructive alternatives:

- `git show <ref>:<path>` — view a file at a specific commit
- `git diff <ref>` — compare current state against a commit
- `git stash` — only if you intend to restore immediately

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

## Issue Triage

> **⚠️ MANDATORY:** Read
> [`docs/work-styles/06-issue-triage.md`](docs/work-styles/06-issue-triage.md)
> before triaging any issues.

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
- [**Implementation Workflow**](docs/work-styles/05-implementation-workflow.md)
  — How to transform stable design specs into production code.
