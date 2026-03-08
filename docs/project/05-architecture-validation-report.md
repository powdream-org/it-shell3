# Architecture Validation Report

**Date**: 2026-03-04 (original), updated 2026-03-08
**Reviewer**: Principal Software Architect (AI-assisted)
**Scope**: All documents in `docs/` (00–13) + all reference codebases in `~/dev/git/references/`

---

## Executive Summary

The libitshell3 project objectives are sound, the basic design direction is feasible, and the architecture supports gradual, incremental development. The three core problems (CJK preedit in multiplexers, AI agent input handling, cross-device session continuity) are real and unsolved by existing tools. The proposed architecture — a portable Zig library wrapping libghostty with a daemon/client model — is well-grounded in proven patterns from five reference implementations (tmux, zellij, cmux, iTerm2, ghostty).

One major architectural change was made after initial review: **implement IME natively within libitshell3-ime (wrapping libhangul) rather than relying on macOS's NSTextInputContext**. This eliminates the project's single largest risk, removes the GUI process requirement from the daemon, and makes the library truly portable and headless-capable.

**Overall confidence: 9/10** (up from 8/10 after PoC 06–08 validated the full RenderState → GPU rendering pipeline without Terminal on the client).

---

## 1. Objective Validation

### 1.1 Problem Statement Assessment

| Problem | Valid? | Evidence |
|---------|--------|---------|
| CJK preedit broken in multiplexers | **YES** | No existing multiplexer has IME composition awareness. Korean Jamo decomposition breaks when composed through a multiplexer that treats input as raw bytes. |
| AI agent input areas need special handling | **YES** | Claude Code, Codex CLI, and Cursor use Shift+Enter for line breaks, Cmd+C for copy. No existing multiplexer handles these distinctions. |
| Cross-device session continuity | **YES (secondary)** | Useful for macOS→iOS workflows. Best positioned as a stretch goal. |

### 1.2 Why Not Patch Existing Tools?

| Alternative | Why Not |
|-------------|---------|
| Patch tmux | C architecture and imsg protocol have no extension mechanism. Preedit sync would require invasive changes. |
| Patch zellij | Server-side rendering model means CJK preedit would require adding client-side rendering, breaking the core assumption. |
| Build on tmux (iTerm2 model) | Inherits tmux's CJK limitations. `send-keys` path cannot support preedit synchronization. |
| Fork ghostty | Ghostty is a terminal emulator, not a multiplexer. Adding multiplexing would be massive scope change. |

**Conclusion**: A new library leveraging libghostty for rendering while implementing its own multiplexer layer is the correct approach.

---

## 2. Architecture Feasibility

### 2.1 Core Architecture: Daemon + Client over Unix Socket

**Verdict: SOUND (9/10)** — Canonical pattern proven by tmux (decades), zellij (modern), iTerm2 FileDescriptorServer.

### 2.2 Zig as Implementation Language

**Verdict: CORRECT CHOICE (9/10)** — Natural FFI with ghostty, mature stdlib (JSON, TLS, crypto, POSIX sockets), C export for Swift.

### 2.3 Decoupled PTY (Daemon) + Rendering Surface (Client)

**Verdict: VALIDATED (9/10)** — PoC 06–08 proven. Client renders from RenderState without Terminal. `importFlatCells()` → `rebuildCells()` → Metal GPU confirmed.

### 2.4 Native IME Architecture

**Verdict: CORRECT DECISION (9/10)**

IME is implemented natively in libitshell3-ime, starting with English (QWERTY) and Korean (2-set). The Korean composition engine wraps libhangul (C library, LGPL-2.1). IME operates per-session, not per-pane.

**Why native IME over OS IME**: True headless daemon (no GUI), zero OS dependency, deterministic behavior, one code path everywhere, iOS compatibility.

> For detailed IME architecture, see `docs/modules/libitshell3-ime/01-overview/`.

### 2.5 RenderState Protocol

**Verdict: VALIDATED (9/10)** — PoC 06–08 proven.

- **Server**: PTY → Terminal → `RenderState.update()` → `bulkExport()` → FlatCell[] (16-byte fixed-size cells)
- **Client**: FlatCell[] → `importFlatCells()` → RenderState → `rebuildCells()` → Metal GPU
- **Performance**: Export 22 µs + import 12 µs = 34 µs for 80×24 (0.2% of frame budget)

Client reuses ghostty's entire renderer pipeline — no manual GPU buffer construction needed.

> For wire format details, see `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/`.
> For API details, see `docs/insights/ghostty-api-extensions.md`.

### 2.6 Session Hierarchy and Layout

**Verdict: APPROPRIATE (9/10)** — Session > Tab > Pane with binary split tree. Matches ghostty's split API and cmux's production pattern.

### 2.7 Server-Client Protocol

**Verdict: WELL-DESIGNED (7/10)** — Draws from tmux (Unix socket, reliability), zellij (extensibility), iTerm2 (control mode). Hybrid binary+JSON encoding. Capability negotiation at handshake.

> For protocol specification, see `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/`.

### 2.8 Testing Strategy

**Verdict: EXCELLENT (9/10)** — Four-tiered approach: unit (55%), OS integration (30%), E2E (10%), manual/GUI (5%). ~95% automated coverage achievable because libitshell3's boundary is clean (bytes in, bytes out).

---

## 3. Gaps and Concerns

### 3.1 Data Injection Path

`ghostty_surface_text()` is NOT the correct path for client rendering — it triggers bracketed paste behavior. The RenderState protocol (FlatCell export/import) is the correct and validated approach.

### 3.2 Missing: Security Model

No security model designed yet. Needed before Phase 5 (network transport): socket permissions, network authentication, macOS sandboxing, iOS App Store guidelines.

### 3.3 Missing: Configuration System

Configuration not specified yet. Not a blocker for Phase 1 but should be designed before Phase 2.

### 3.4 libghostty API Instability

HIGH impact / HIGH probability. Mitigations: pin commit via git submodule, thin Zig abstraction layer, upstream engagement.

### 3.5 iOS Background Execution

HIGH impact for cross-device use. iOS aggressively suspends background apps. Mitigations: fast reconnect + state replay from RenderState, accept limitation initially.

---

## 4. Incremental Development Path

| Phase | Description | Confidence |
|-------|-------------|------------|
| **1** | Daemon + single pane + Unix socket + client RenderState rendering | 9/10 |
| **1.5** | Native IME: English QWERTY + Korean 2-set (parallel with Phase 1) | 9/10 |
| **2** | Multi-pane, tabs, sessions, attach/detach | 9/10 |
| **2.5** | Session persistence to disk (parallel with Phase 3) | 9/10 |
| **3** | CJK preedit protocol: capability negotiation, preedit sync | 7/10 |
| **4** | AI agent detection: process detection, custom key profiles | 6/10 |
| **5** | iOS client: network transport (TLS/TCP), cross-device sessions | 6/10 |
| **6** | Polish: config, theming, Korean 3-set, additional layouts | 8/10 |

---

## 5. Risk Matrix

| Risk | Impact | Probability | Status |
|------|--------|-------------|--------|
| ~~NSEvent construction~~ | ~~HIGH~~ | ~~HIGH~~ | **ELIMINATED** by native IME |
| libghostty API instability | HIGH | HIGH | Open — pin commit, abstraction layer |
| ~~PTY decoupling~~ | ~~HIGH~~ | ~~LOW~~ | **VALIDATED** by PoC 08 |
| CJK preedit sync correctness | HIGH | MEDIUM | Open |
| AI agent detection accuracy | MEDIUM | HIGH | Acceptable — configurable profiles |
| iOS background execution | HIGH | HIGH | Open |
| ~~Performance~~ | ~~MEDIUM~~ | ~~LOW~~ | **VALIDATED** — 34 µs for 80×24 |
| Security model gaps | HIGH | MEDIUM | Open |

---

## 6. Reference Codebase Validation Summary

| Codebase | Key Takeaway |
|----------|-------------|
| **ghostty** | Surface works without PTY, RenderState designed for external use, Metal shaders reusable, preedit separate from PTY/IO |
| **cmux** | Proves libghostty embedding in Swift/AppKit, JSON persistence, binary split tree, key interception pattern |
| **tmux** | Daemon-as-persistence (simple, proven), backpressure via pause/continue. No CJK awareness. |
| **zellij** | Multi-threaded with typed message bus, disk serialization. Server-side rendering incompatible with CJK preedit. |
| **iTerm2** | TmuxGateway/Controller separation, command queue framing, FileDescriptorServer crash survival. Inherits tmux CJK limitations. |

---

## 7. Conclusion

**The project is feasible. The design direction is sound.** The native IME decision strengthens the architecture by eliminating OS dependencies. The RenderState pipeline is PoC-validated end-to-end. Each development phase delivers independent value.
