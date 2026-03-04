# Architecture Validation Report

**Date**: 2026-03-04
**Reviewer**: Principal Software Architect (AI-assisted)
**Scope**: All documents in `docs/` (00–13) + all reference codebases in `~/dev/git/references/`

---

## Executive Summary

The libitshell3 project objectives are sound, the basic design direction is feasible, and the architecture supports gradual, incremental development. The three core problems (CJK preedit in multiplexers, AI agent input handling, cross-device session continuity) are real and unsolved by existing tools. The proposed architecture — a portable Zig library wrapping libghostty with a daemon/client model — is well-grounded in proven patterns from five reference implementations (tmux, zellij, cmux, iTerm2, ghostty).

One major architectural change is recommended: **implement IME natively within libitshell3 rather than relying on macOS's NSTextInputContext**. This eliminates the project's single largest risk, removes the GUI process requirement from the daemon, and makes the library truly portable and headless-capable.

**Overall confidence: 8/10** (up from 7.5 after the native IME decision removes the NSEvent construction risk).

---

## 1. Objective Validation

### 1.1 Problem Statement Assessment

| Problem | Valid? | Evidence |
|---------|--------|---------|
| CJK preedit broken in multiplexers | **YES** | tmux and zellij have zero awareness of IME composition state. Korean Jamo decomposition, Japanese Kana-to-Kanji, and Chinese Pinyin all break when composed through a multiplexer that treats input as raw bytes. No existing multiplexer attempts to solve this. |
| AI agent input areas need special handling | **YES** | Claude Code, Codex CLI, and Cursor terminal use Shift+Enter for line breaks (not submission), Cmd+C for copy (not SIGINT), and Cmd+V for paste (not bracketed paste). No existing multiplexer handles these distinctions. The pain is growing as AI coding tools proliferate. |
| Cross-device session continuity | **YES (secondary)** | Useful for macOS→iOS workflows, but the market is narrower than the first two problems. Best positioned as a stretch goal rather than core differentiator. |

### 1.2 Why Not Patch Existing Tools?

| Alternative | Why Not |
|-------------|---------|
| Patch tmux for CJK preedit | tmux's single-threaded C architecture and imsg-based protocol have no extension mechanism. Preedit sync would require invasive changes to the server, client, and wire protocol. The tmux maintainer community is conservative about such changes. |
| Patch zellij for CJK | More feasible architecturally (Rust, protobuf), but zellij's server-side rendering model (sends pre-rendered ANSI strings) means CJK preedit would require adding client-side rendering, breaking the architecture's core assumption. |
| Build on top of tmux (iTerm2 model) | iTerm2's tmux -CC integration works for simple cases but inherits tmux's CJK limitations. The `send-keys` input path is inefficient and fundamentally cannot support preedit synchronization. |
| Fork ghostty | Ghostty is a terminal emulator, not a multiplexer. Adding multiplexing would be a massive scope change outside the project's mission. |

**Conclusion**: A new library that leverages libghostty for rendering while implementing its own multiplexer layer is the correct approach.

---

## 2. Architecture Feasibility

### 2.1 Core Architecture: Daemon + Client over Unix Socket

**Verdict: SOUND (Confidence 9/10)**

This is the canonical pattern for terminal multiplexing, proven by:
- tmux: Decades of production use, single-threaded C, libevent
- zellij: Modern multi-threaded Rust, protobuf serialization
- iTerm2's FileDescriptorServer: Crash-surviving daemon with FD passing

The docs correctly adopt this pattern with Unix domain sockets (`AF_UNIX`, `SOCK_STREAM`).

### 2.2 Zig as Implementation Language

**Verdict: CORRECT CHOICE (Confidence 9/10)**

| Requirement | Zig Capability |
|-------------|---------------|
| Natural FFI with libghostty | First-class — same language, zero marshalling |
| C ABI export for Swift apps | `@export` with C calling convention, generates `.h` headers |
| JSON parse/serialize | Built-in `std.json` — production-proven by ghostty itself |
| TLS client (for iOS→macOS) | Built-in `std.crypto.tls` — TLS 1.2 + 1.3, added in Zig 0.14 |
| Crypto primitives | Built-in `std.crypto` — SHA, HMAC, AEAD, key exchange, secure RNG |
| Unix domain sockets | Built-in `std.posix` — standard POSIX socket APIs |
| Cross-platform | macOS, Linux, iOS targets supported |
| C library interop | `@cImport` — seamless import of any C library |

Zig 1.0 is targeting 2026-2027. The standard library is already mature in every area libitshell3 requires. Ghostty itself (a full GPU-accelerated terminal emulator with Metal rendering, HarfBuzz font shaping, and crash reporting) proves Zig handles complex systems software.

### 2.3 Decoupled PTY (Daemon) + Rendering Surface (Client)

**Verdict: FEASIBLE (Confidence 8/10)**

Validated by ghostty reference code analysis:
- `ghostty_surface_new()` accepts `command=NULL` — surfaces work without a PTY
- `NullPty` (44 lines in `src/pty.zig`) is an intentional no-op PTY for iOS
- `ghostty_surface_preedit()` operates independently of the PTY/IO layer
- The embedded runtime (`src/apprt/embedded.zig`) is purpose-built for host app integration

**Important caveat**: `ghostty_surface_text()` goes through the clipboard paste path (with bracketed paste wrapping). This is NOT the right entry point for forwarding raw PTY output to a client surface. The RenderState protocol (Doc 13) is the correct approach — it avoids the VT parse→serialize→re-parse round-trip entirely. See Section 2.5.

### 2.4 Native IME Architecture (Revised from Doc 12)

**Verdict: CORRECT DECISION (Confidence 9/10)**

**Decision**: Implement IME natively within libitshell3, starting with English (QWERTY) and Korean. Never use OS native IME, even on macOS. Hook raw hardware key events directly.

**Why this is superior to the Doc 12 proposal (server-side macOS IME)**:

| Aspect | Doc 12: macOS NSTextInputContext | Revised: Native IME |
|--------|----------------------------------|---------------------|
| Daemon portability | Must be GUI-capable (LSUIElement) | True headless daemon (LaunchDaemon, SSH, Linux) |
| Platform dependency | Requires macOS window server | Zero OS dependency |
| NSEvent construction risk | HIGH — untested, object identity issues | **Eliminated** |
| Korean composition | Depends on macOS IME behavior | Deterministic Unicode algorithm |
| iOS support | Custom keyboard + remote IME | Custom keyboard + same native IME |
| Code path consistency | One code path (macOS), but complex | One code path everywhere, simple |
| Japanese/Chinese | Works via macOS IME but candidate window problem | Deferred; add librime/libkkc later |

**Why Korean is the perfect starting point**:

Korean Hangul composition is purely algorithmic — no candidate selection, no dictionary lookup, no ambiguity. The Unicode standard defines the composition formula precisely:

```
Syllable = SBase + (LeadingJamo × VCount + VowelJamo) × TCount + TrailingJamo

SBase = 0xAC00, LBase = 0x1100, VBase = 0x1161, TBase = 0x11A7
LCount = 19, VCount = 21, TCount = 28
```

The entire composition + decomposition engine is ~300-400 lines of pure Zig. No external library needed.

**Implementation structure**:

```
Raw HID keycode + modifiers + active layout ID
        │
        ▼
┌─────────────────────────────────┐
│    libitshell3 Input Engine      │
│                                  │
│  1. Layout Mapper                │
│     HID 0x04 + layout=US → 'a' │
│     HID 0x04 + layout=KR → ㅁ  │
│                                  │
│  2. Composition Engine           │
│     (per-pane state machine)     │
│     ㅎ → 하 → 한                │
│     backspace: 한 → 하 → ㅎ → ∅ │
│                                  │
│  3. Output                       │
│     preedit events → protocol   │
│     committed text → PTY write  │
└─────────────────────────────────┘
```

**Korean composition state machine**:

```
States: empty | leading_jamo | syllable_no_tail | syllable_with_tail

Transitions:
  empty + consonant → leading_jamo(ㅎ)
  leading_jamo(ㅎ) + vowel → syllable_no_tail(하)
  syllable_no_tail(하) + consonant → syllable_with_tail(한)
  syllable_with_tail(한) + vowel → commit(하) + syllable_no_tail(나)  [jamo reassignment]
  any + backspace → decompose (reverse the last composition step)
  any + non-jamo → commit current + pass through
```

**Scoping for future CJK**:

| Phase | Language | Approach |
|-------|----------|----------|
| v1 | English (QWERTY) | Static keycode→character table (~50 entries) |
| v1 | Korean (2-set) | Native composition engine in Zig (~300-400 lines) |
| v2 | Korean (3-set) | Extended composition rules (same engine) |
| Future | Japanese | libkkc or libmozc via `@cImport` + candidate UI |
| Future | Chinese | librime via `@cImport` + candidate UI |
| Future | European dead keys | Compose table (é, ñ, ü) |

### 2.5 Render State Protocol (Doc 13)

**Verdict: WELL-DESIGNED (Confidence 8/10)**

The analysis of libghostty-vt's `RenderState` is thorough and accurate:

- **Server**: PTY → libghostty-vt Terminal (VT parse, grid, scrollback) → `RenderState.update()` → structured cell data
- **Client**: Receives cell data → libghostty font subsystem (SharedGrid, Atlas, HarfBuzz) → Metal GPU renderer
- **Built-in dirty tracking**: Per-row dirty flags enable efficient delta updates
- **Bandwidth**: ~8 KB typical full frame, ~600 B partial update, ~50 B cursor-only move

This is superior to:
- Zellij's approach (pre-rendered ANSI strings — no client-side optimization possible)
- VT re-serialization (redundant parse→serialize→re-parse cycle)

The font subsystem components (SharedGrid, CodepointResolver, Collection, Atlas) have **zero terminal dependency** — verified in the ghostty source. Metal shaders consume simple flat structs (CellText, CellBg) with no terminal coupling.

### 2.6 Session Hierarchy and Layout

**Verdict: APPROPRIATE (Confidence 9/10)**

Session > Tab > Pane with binary split tree:
- Matches ghostty's split API (`GHOSTTY_SPLIT_DIRECTION_{RIGHT,DOWN,LEFT,UP}`)
- Matches cmux's proven production pattern (Bonsplit library)
- Simple to serialize (JSON), simple to restore
- No floating panes in v1 — correct scoping decision

### 2.7 Server-Client Protocol

**Verdict: WELL-DESIGNED (Confidence 7/10)**

The protocol design draws from the right sources:
- tmux: Unix socket transport, proven reliability, FD passing
- zellij: Protobuf-style extensibility, capability negotiation
- iTerm2: Control mode notifications, command queue with begin/end framing, flow control

**Improvements over tmux** correctly identified in the docs:
- Explicit capability negotiation (vs. tmux's fragile version guessing)
- Dedicated input channel for low-latency key forwarding (vs. tmux's `send-keys` command overhead)
- Hybrid text/binary protocol (debuggable + performant)
- Bidirectional clipboard sync

Lower confidence due to CJK protocol extensions needing more specification (see Section 3.2).

### 2.8 Testing Strategy (Doc 11)

**Verdict: EXCELLENT (Confidence 9/10)**

The tiered testing approach is well-designed:
- Tier 1 (55%): Pure unit tests — no OS resources, run anywhere
- Tier 2 (30%): OS integration tests — real PTYs, sockets, processes
- Tier 3 (10%): E2E tests — full daemon/client binary scenarios
- Tier 4 (5%): Manual/GUI tests — belongs to app layer, not library

The ~95% automated coverage estimate is achievable because libitshell3's boundary is clean: bytes in, bytes out, no GUI. The Zig test examples are concrete and practical.

---

## 3. Gaps and Concerns

### 3.1 Data Injection Path Clarification

The docs should explicitly state that `ghostty_surface_text()` is NOT the correct path for forwarding raw PTY output to a client surface. This API triggers bracketed paste behavior, which caused the Korean doubling bug documented in Doc 12.

The RenderState protocol (Doc 13) correctly bypasses this by having the server extract structured cell data from `RenderState.update()` and sending it to the client for direct GPU rendering. The docs should make this the explicit and only recommended path.

### 3.2 CJK Protocol Extensions Need Technical Specification

The `design-cjk-protocol-extensions.md` reference document is a good **design** document but insufficient as an **implementation specification**. Gaps identified:

- Binary message payload encoding: byte count vs. character count for string lengths
- Error handling: what happens when a preedit message is rejected or malformed
- Message ordering guarantees under concurrent multi-client access
- Cursor position calculation with combining characters and emoji modifiers
- Race conditions: pane closed between MSG_PREEDIT_START and MSG_PREEDIT_UPDATE
- Message type ID allocation verification against actual tmux codebase

**Recommendation**: Before implementing CJK protocol messages, create a companion Technical Specification with:
1. Example hex dumps of every message type
2. Exact string encoding and escaping rules
3. Error codes and recovery mechanisms
4. Formal state machine diagram with all transitions
5. Timeout and retry behavior

### 3.3 Missing: Security Model

No document addresses security:

| Area | Gap |
|------|-----|
| Unix socket permissions | Who can connect to the daemon? What access control model? |
| Network transport auth | iOS→macOS connection needs authentication and encryption |
| macOS sandboxing | App Sandbox and Hardened Runtime implications for PTY creation and socket binding |
| iOS App Store | Terminal apps have been rejected before; guidelines should be reviewed |

cmux's socket control interface provides a reference model with multiple access tiers (process ancestry checking, UID verification, password authentication). libitshell3 should design its security model before implementing network transport.

### 3.4 Missing: Configuration System

Configuration is mentioned in passing but never specified:
- Does it-shell3 use ghostty's config format? Its own? Both?
- How does per-pane configuration work (CJK settings, key profiles, agent detection)?
- How are configurations synchronized between client and daemon?
- Hot-reload semantics?

Not a blocker for Phase 1 but should be designed before Phase 2.

### 3.5 libghostty API Instability

libghostty is explicitly "not yet stable for general-purpose use." This is HIGH impact / HIGH probability.

**Mitigations** (docs partially address):
1. Pin to a specific ghostty commit via git submodule (cmux does this)
2. Create a thin Zig abstraction layer over the C API
3. Establish communication with the ghostty maintainer early
4. Consider contributing upstream to stabilize critical APIs
5. Have a contingency plan for breaking changes in rendering/surface APIs

### 3.6 iOS Background Execution

The docs rate this as MEDIUM impact. I'd rate it **HIGH impact** for the cross-device use case. iOS aggressively suspends background apps (typically within 30 seconds of backgrounding). A terminal client that disconnects every time the user switches apps is a significantly degraded experience.

**Mitigations to explore**:
- BGTaskScheduler for periodic keepalive
- Audio session background mode (used by Blink Shell — controversial but effective)
- Accept the limitation and optimize for fast reconnect + state replay from RenderState
- Focus on foreground-only use initially

### 3.7 OS IME Suppression on macOS

With the native IME decision, libitshell3 must ensure the OS IME is suppressed when the terminal is active. On macOS, this means consuming key events BEFORE `interpretKeyEvents:` is called.

cmux/ghostty already implements this pattern:
```swift
override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if ghostty_surface_key_is_binding(surface, keyEvent) {
        ghostty_surface_key(surface, keyEvent)
        return true  // consumed — OS IME never sees it
    }
    return super.performKeyEquivalent(with: event)
}
```

The it-shell3 macOS app must intercept ALL key events (not just bindings) and route them to libitshell3's native IME engine instead of the OS text input system. This is feasible but requires careful handling of edge cases (function keys, media keys, accessibility shortcuts).

---

## 4. Incremental Development Path

### Revised Phasing

| Phase | Description | Confidence | Key Deliverable |
|-------|-------------|------------|-----------------|
| **1** | Daemon + single pane + Unix socket + client with RenderState rendering | High (8/10) | Proof of architecture: data flows from PTY through daemon to client GPU |
| **1.5** | Native IME engine: English QWERTY layout mapper + Korean 2-set composition | High (9/10) | Proof of native IME: Korean ㅎ→하→한 composition and backspace decomposition |
| **2** | Multi-pane with split layout, tabs, sessions, attach/detach | High (9/10) | Usable multiplexer with session persistence |
| **2.5** | Session persistence to disk (JSON snapshots, scrollback) | High (9/10) | Crash-survivable sessions |
| **3** | CJK preedit protocol: capability negotiation, preedit sync messages, multi-client sync | Medium-High (7/10) | Multiple clients see consistent IME state |
| **4** | AI agent detection: process detection, custom key profiles (Shift+Enter, Cmd+C/V) | Medium (6/10) | Better experience in Claude Code, Codex, Cursor |
| **5** | iOS client: network transport (TLS over TCP), custom keyboard, cross-device sessions | Medium (6/10) | Terminal multiplexer accessible from iPad |
| **6** | Polish: configuration system, theming (leverage ghostty themes), Korean 3-set, additional layouts | High (8/10) | Production-ready quality |

### Critical Path

```
Phase 1 (daemon + client + RenderState)
    │
    ├── Phase 1.5 (native IME) ── can develop in parallel
    │
    ▼
Phase 2 (multiplexing)
    │
    ▼
Phase 2.5 (persistence) ── can develop in parallel with Phase 3
    │
    ▼
Phase 3 (CJK protocol sync)
    │
    ├── Phase 4 (AI agent) ── can develop in parallel
    │
    ▼
Phase 5 (iOS)
    │
    ▼
Phase 6 (polish)
```

Phases 1 and 1.5 can be developed in parallel. Phase 2.5 and Phase 3 can overlap. Phase 4 is independent and can be developed any time after Phase 2.

---

## 5. Risk Matrix (Updated)

| Risk | Impact | Probability | Mitigation | Status |
|------|--------|-------------|------------|--------|
| ~~NSEvent construction fidelity~~ | ~~HIGH~~ | ~~HIGH~~ | ~~PoC validation~~ | **ELIMINATED** by native IME decision |
| libghostty API instability | HIGH | HIGH | Pin commit, abstraction layer, upstream engagement | Open |
| ghostty_surface_text() bracketed paste contamination | HIGH | HIGH | Use RenderState protocol instead (Doc 13) | Addressed in design |
| PTY decoupling from libghostty | HIGH | MEDIUM | Prototype in Phase 1 | Open |
| CJK preedit sync correctness | HIGH | MEDIUM | Formal spec, extensive testing with Korean | Open |
| Korean Jamo decomposition bugs | MEDIUM | LOW | Unicode algorithm is well-defined; test against libhangul | Low risk |
| AI agent detection accuracy | MEDIUM | HIGH | Configurable profiles, manual fallback | Acceptable |
| iOS background execution limits | HIGH | HIGH | Fast reconnect, accept limitation initially | Open |
| OS IME suppression on macOS | MEDIUM | LOW | cmux/ghostty pattern already proven | Low risk |
| Performance (rendering latency) | MEDIUM | LOW | Unix sockets are fast; RenderState has dirty tracking | Low risk |
| Security model gaps | HIGH | MEDIUM | Design before network transport (Phase 5) | Open |

---

## 6. Reference Codebase Validation Summary

Each reference codebase was analyzed in depth. Key takeaways:

### ghostty (Zig, terminal engine)
- Confirms surface creation works without PTY (`command=NULL`, `NullPty`)
- `RenderState` explicitly designed for external renderer use (source comment confirms)
- Font subsystem (SharedGrid, Atlas, HarfBuzz) fully independent of terminal state
- Metal shaders consume flat structs — reusable by client without terminal dependency
- Preedit stored in `renderer_state.preedit`, separate from PTY/IO, mutex-protected

### cmux (Swift, libghostty-based macOS terminal)
- Proves libghostty embedding in Swift/AppKit works in production
- Session persistence via JSON snapshots with 8-second auto-save
- ANSI-safe scrollback truncation (never splits mid-escape-sequence)
- Binary split tree via Bonsplit library — clean, proven
- Key input: intercepts before OS text input system, exactly the pattern needed
- Socket control interface with sophisticated access control (ancestry checking, UID verification)

### tmux (C, canonical multiplexer)
- Daemon-as-persistence model: simple, proven, decades of reliability
- imsg-based binary framing with protocol version in every message
- Control mode (`%`-prefixed notifications) is human-readable and debuggable
- Per-client pane output tracking with offset management
- Backpressure via pause/continue (essential for flow control)
- **Weakness**: No CJK preedit awareness, no extension mechanism, fragile strict message ordering

### zellij (Rust, modern multiplexer)
- Multi-threaded architecture with typed message bus (crossbeam channels)
- Protobuf serialization — extensible, schema-evolvable
- Server-side rendering: clients receive pre-rendered ANSI strings
- Instruction enums for typed, compile-time-checked message passing
- NotificationEnd pattern for async operation completion signaling
- **Weakness**: Server-side rendering model cannot support client-specific CJK preedit overlay

### iTerm2 (ObjC/Swift, macOS terminal with tmux integration)
- TmuxGateway/TmuxController separation: protocol parsing vs. application state
- Command queue with `%begin`/`%end` framing for reliable request-response
- FileDescriptorServer: daemon survives app crashes via Mach namespace trick
- Layout parsing from tmux layout strings → native NSSplitView hierarchy
- Input forwarding: code point conversion, run-length encoding, batching
- **Weakness**: Inherits all of tmux's CJK limitations

---

## 7. Conclusion

### Strengths of the Design

1. **Problem identification is precise** — CJK preedit and AI agent input are real, unsolved problems with growing urgency
2. **Native IME eliminates the largest risk** — no OS dependency, no NSEvent construction gamble, truly portable
3. **RenderState protocol is well-researched** — leverages libghostty-vt's built-in dirty tracking for efficient client rendering
4. **Reference code analysis is thorough** — every major decision grounded in real implementations
5. **Phased development is realistic** — each phase delivers standalone, usable value
6. **Zig choice is validated** — natural FFI with ghostty, mature stdlib for all project needs, C export for Swift

### Items Requiring Attention Before Phase 1

1. ~~Validate NSEvent construction for Korean IME~~ → **Eliminated** by native IME decision
2. Prototype the PTY→daemon→RenderState→client GPU pipeline (Phase 1 deliverable)
3. Verify that ghostty surfaces with `command=NULL` render correctly when fed structured cell data

### Items Requiring Attention Before Phase 3

1. Write CJK protocol Technical Specification (formal message formats, error codes, state machines)
2. Design security model for Unix socket access control

### Items Requiring Attention Before Phase 5

1. Design security model for network transport (TLS, authentication)
2. Investigate iOS background execution constraints and mitigations
3. Review iOS App Store guidelines for terminal apps

### Final Verdict

**The project is feasible. The design direction is sound. The architecture supports gradual development with each phase delivering independent value.** The native IME decision strengthens the architecture significantly by eliminating OS dependencies and making the daemon truly portable.

The recommended next step is Phase 1: build the daemon→client pipeline with RenderState rendering, proving the core architectural hypothesis with minimal scope.
