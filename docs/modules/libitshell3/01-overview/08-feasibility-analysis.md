# Feasibility Analysis

## Executive Summary

Building it-shell3 as a terminal multiplexer on top of libghostty is **feasible** with moderate-to-high engineering effort. The key enabler is the existence of cmux, which proves that libghostty can be successfully embedded in a native macOS application with custom window/pane management. However, significant challenges exist around decoupling PTY management from libghostty's integrated approach, and the CJK preedit synchronization is novel territory.

---

## Feasibility Assessment by Component

### 1. libghostty Embedding — PROVEN FEASIBLE

**Confidence: HIGH (9/10)**

**Evidence**:
- cmux successfully embeds libghostty in a Swift/AppKit macOS application
- The C API (`ghostty.h`) is comprehensive with 1170 lines of declarations
- Working examples exist in the ghostty repo (`example/`)
- GhosttyKit.xcframework build target exists for Xcode integration

**Risks**:
- libghostty API is explicitly "not yet stable for general-purpose use" (per source comments)
- API breaking changes are likely as ghostty evolves
- No official documentation beyond the header file

**Mitigation**:
- Pin to a specific ghostty commit (like cmux does via git submodule)
- Create a thin abstraction layer over the C API
- Follow cmux's patterns for API usage

### 2. Daemon Process (Session Server) — PROVEN FEASIBLE

**Confidence: HIGH (9/10)**

**Evidence**:
- tmux (C, decades of production use)
- zellij (Rust, modern, well-architected)
- Both use the same fundamental pattern: fork to background, listen on Unix socket

**Approach Options**:

| Language | Pros | Cons |
|----------|------|------|
| **Swift** | Same language as client, Apple ecosystem | No Linux (if needed), less terminal tooling |
| **Rust** | zellij proves it works, strong ecosystem | FFI with Zig (libghostty) adds complexity |
| **Zig** | Same language as ghostty, natural FFI | Smaller ecosystem, less library support |
| **C** | Same as tmux, simplest FFI | Manual memory management, less productive |

**Recommendation**: Swift for macOS-only, Rust for cross-platform.

### 3. Server-Client Protocol — PROVEN FEASIBLE

**Confidence: HIGH (9/10)**

**Evidence**:
- tmux protocol is well-documented (3 analysis documents in references)
- zellij uses protobuf over local sockets
- cmux has a Unix socket control interface

**Key Decision**: Design a new protocol inspired by tmux (proven) with protobuf serialization (extensible) and CJK extensions (novel).

### 4. PTY Management (Decoupled from libghostty) — FEASIBLE WITH EFFORT

**Confidence: MEDIUM-HIGH (7/10)**

**Evidence**:
- ghostty's PTY code is in `pty.zig` — well-structured and understandable
- Standard POSIX PTY APIs are well-documented
- tmux and zellij both manage PTYs independently

**Challenge**:
- libghostty's `Exec` backend tightly couples PTY management with the terminal surface
- it-shell3 needs the daemon to own PTYs, but the client to render via libghostty surfaces
- Must feed PTY output data into libghostty surfaces without using ghostty's built-in PTY handling

**Solution Path**:
1. The daemon manages PTYs directly (like tmux)
2. The daemon reads from PTY master FDs and sends terminal output to clients
3. The client creates libghostty surfaces in "headless" mode (no PTY)
4. The client feeds received terminal data into ghostty surfaces via text/escape sequence input
5. Or: Use libghostty-vt for parsing on the daemon side, and the full libghostty for rendering on the client side

**Open Question**: Can a ghostty surface be created without an associated PTY? Looking at the embedded apprt, the surface creation flow expects a subprocess. A "virtual PTY" or pipe-based approach may be needed.

### 5. CJK Preedit Synchronization — NOVEL, FEASIBLE IN THEORY

**Confidence: MEDIUM (6/10)**

**Evidence**:
- Detailed design document exists (`design-cjk-protocol-extensions.md`, 810 lines)
- libghostty has full preedit API (`ghostty_surface_preedit()`, `ghostty_surface_ime_point()`)
- No existing implementation to validate the design

**Challenges**:
1. **Korean Jamo decomposition**: Server must understand Hangul composition rules to correctly track preedit state for secondary clients
2. **Latency**: Preedit updates are character-by-character; network latency would make cross-device preedit sync feel laggy
3. **Concurrent composition**: What happens if two clients compose CJK text in the same pane?
4. **IME state is client-local**: The OS IME runs on the client; the server can only receive and forward the state

**Mitigation**:
- Start with single-client preedit (no sync)
- Add multi-client sync in Phase 2
- For cross-device, accept some latency (display delay is OK for secondary viewers)
- Disallow concurrent composition in the same pane (last-writer-wins)

### 6. AI Agent Input Area Detection — FEASIBLE WITH HEURISTICS

**Confidence: MEDIUM (5/10)**

**Evidence**:
- No existing terminal multiplexer handles this
- Process detection is straightforward (`ps`, `/proc`)
- Terminal mode detection (raw vs. cooked) is available via termios

**Challenges**:
1. **No standard signaling**: AI agents don't advertise their input mode to the terminal
2. **Heuristic-based**: Must guess based on process name, terminal mode, escape sequences
3. **Agent diversity**: Each agent handles input differently
4. **Future-proofing**: New agents may appear with different patterns

**Approach**:
1. Maintain a registry of known agent processes and their input behaviors
2. Allow user-configurable per-pane input profiles
3. Propose OSC extensions for agent input area signaling (long-term)

### 7. iOS Client — FEASIBLE WITH CONSTRAINTS

**Confidence: MEDIUM (6/10)**

**Evidence**:
- ghostty has `NullPty` for iOS (PTY not available)
- ghostty supports Metal rendering (native to iOS)
- The embedded apprt should work on iOS (same as macOS)

**Constraints**:
- iOS cannot fork processes → must be client-only
- Requires network transport (not just Unix sockets) for remote daemon
- Background execution limits on iOS may affect connection persistence
- App Store guidelines for terminal apps

**Network Transport Options**:
| Transport | Pros | Cons |
|-----------|------|------|
| SSH tunnel | Proven, secure, uses existing infra | Adds latency, requires SSH server |
| Custom TCP/TLS | Lower overhead, custom protocol | Must implement TLS, security concerns |
| WebSocket | Works through firewalls, proxy-friendly | Additional framing overhead |
| Tailscale/WireGuard | Zero-config VPN, secure | Requires VPN setup |

---

## Risk Matrix

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| libghostty API instability | HIGH | HIGH | Pin commit, abstraction layer |
| PTY decoupling complexity | HIGH | MEDIUM | Prototype early, validate approach |
| CJK preedit sync correctness | HIGH | MEDIUM | Extensive testing with all 3 CJK languages |
| AI agent detection accuracy | MEDIUM | HIGH | Configurable profiles, fallback to manual |
| iOS background limits | MEDIUM | HIGH | Accept disconnects, fast reconnect |
| Performance (latency) | HIGH | LOW | Unix sockets are fast, optimize later |
| ghostty surface without PTY | HIGH | MEDIUM | Need to validate this is possible |

---

## Critical Path Validation

Before committing to full development, these questions must be answered:

### Question 1: Can a ghostty surface work without a PTY?

**Why it matters**: The daemon owns PTYs, but the client renders via ghostty. The client needs to feed terminal data into a ghostty surface.

**Experiment**:
1. Create a ghostty surface in embedded mode
2. Instead of spawning a subprocess, feed data via `ghostty_surface_text()`
3. Verify rendering works correctly

**Alternative**: Use the `NullPty` backend (designed for iOS) on the client side, and inject data through a pipe or direct API calls.

### Question 2: Can terminal escape sequences be fed into ghostty externally?

**Why it matters**: The daemon reads raw terminal output from PTY and sends to client. The client must process these escape sequences for rendering.

**Experiment**:
1. Capture raw PTY output (e.g., `script -r` or `cat /dev/ptmx`)
2. Feed it byte-by-byte into a ghostty surface
3. Verify VT parsing and rendering work correctly

### Question 3: Does ghostty support the Kitty keyboard protocol for Shift+Enter?

**Why it matters**: Shift+Enter distinction requires enhanced keyboard encoding.

**Verification**: Check ghostty's key encoder for CSI u / Kitty keyboard protocol support. (Based on research: YES, ghostty supports this via `src/input/key.zig` and the key encoder API.)

---

## Effort Estimation

### Phase 1: Proof of Concept (Core Architecture)
- Daemon with PTY management
- Single-session, single-pane
- Unix socket protocol (minimal)
- Client with libghostty rendering
- Verify PTY data → ghostty surface pipeline

### Phase 2: Multiplexing
- Multi-pane with split layout
- Tab support
- Session management
- Attach/detach

### Phase 3: CJK
- IME preedit in client
- Preedit protocol messages
- Multi-client preedit sync

### Phase 4: AI Agent Support
- Process detection
- Custom key profiles
- Shift+Enter / Cmd+C/V handling

### Phase 5: iOS Client
- Network transport
- iOS app with libghostty
- Cross-device session access

### Phase 6: Polish
- Session persistence to disk
- Scrollback preservation
- Configuration system
- Theming (leverage ghostty themes)

---

## Conclusion

**The project is feasible.** The highest-risk item is the PTY decoupling from libghostty (Question 1 above), which should be validated with a quick prototype before committing to the full architecture. The CJK preedit synchronization is novel but well-designed in the reference document. The AI agent support is the most speculative component but can be implemented incrementally.

The existence of cmux as a working libghostty-based terminal app significantly de-risks the client-side rendering, and the tmux/zellij references provide proven patterns for the server-side architecture.
