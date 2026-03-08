# it-shell3: Feasibility Analysis

## Executive Summary

Building it-shell3 as a terminal multiplexer on top of libghostty is **feasible** with moderate-to-high engineering effort. The key enabler is the existence of cmux, which proves that libghostty can be successfully embedded in a native macOS application with custom window/pane management. The CJK preedit synchronization is novel territory but well-designed.

> **Note**: This analysis was written early in the project. Some decisions have since evolved — particularly the IME approach (native Zig wrapping libhangul instead of OS IME) and the rendering pipeline (RenderState protocol instead of VT re-serialization). Current design decisions are captured in the protocol specs and IME contract.

---

## Feasibility Assessment by Component

### 1. libghostty Embedding — PROVEN FEASIBLE

**Confidence: HIGH (9/10)**

cmux successfully embeds libghostty in Swift/AppKit. The C API (`ghostty.h`) is comprehensive. Working examples exist.

**Risk**: API instability (explicitly "not yet stable"). **Mitigation**: Pin to specific commit, thin abstraction layer.

### 2. Daemon Process (Session Server) — PROVEN FEASIBLE

**Confidence: HIGH (9/10)**

tmux (C, decades) and zellij (Rust, modern) prove the Unix socket daemon pattern.

**Decision**: Zig was selected for natural FFI with ghostty. See `03-recommended-architecture.md`.

### 3. Server-Client Protocol — PROVEN FEASIBLE

**Confidence: HIGH (9/10)**

New protocol inspired by tmux (proven reliability) with hybrid binary+JSON encoding and capability negotiation.

> For current protocol specification, see `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/`.

### 4. PTY Management (Decoupled from libghostty) — VALIDATED

**Confidence: HIGH (9/10)** — upgraded from 7/10 after PoC validation.

The daemon manages PTYs directly (like tmux). The client creates libghostty surfaces without PTYs and populates RenderState via `importFlatCells()`. PoC 06–08 validated the full pipeline.

### 5. CJK Preedit Synchronization — FEASIBLE

**Confidence: MEDIUM-HIGH (7/10)** — upgraded from 6/10 after native IME decision.

Native IME (libitshell3-ime wrapping libhangul) eliminates OS IME dependency. The daemon processes IME composition per-session, injecting preedit cells into the Terminal's render output. Preedit is cell data, not metadata (design principle A1).

> For IME architecture, see `docs/modules/libitshell3-ime/01-overview/`.

### 6. AI Agent Input Area Detection — FEASIBLE WITH HEURISTICS

**Confidence: MEDIUM (5/10)**

Process detection + configurable per-pane input profiles. Long-term: propose OSC extensions for agent input area signaling.

### 7. iOS Client — FEASIBLE WITH CONSTRAINTS

**Confidence: MEDIUM (6/10)**

iOS cannot fork processes → client-only. Requires network transport. Background execution limits affect connection persistence.

---

## Risk Matrix

| Risk | Impact | Probability | Status |
|------|--------|-------------|--------|
| libghostty API instability | HIGH | HIGH | Open — pin commit, abstraction layer |
| ~~PTY decoupling~~ | ~~HIGH~~ | ~~MEDIUM~~ | **VALIDATED** by PoC 08 |
| CJK preedit sync correctness | HIGH | MEDIUM | Open — extensive testing needed |
| AI agent detection accuracy | MEDIUM | HIGH | Acceptable — configurable profiles |
| iOS background limits | MEDIUM | HIGH | Accept disconnects, fast reconnect |
| ~~Performance~~ | ~~HIGH~~ | ~~LOW~~ | **VALIDATED** — 34 µs for 80×24 |

---

## Critical Path Validation

| Question | Status |
|----------|--------|
| Can ghostty surface work without PTY? | **VALIDATED** — PoC 06, NullPty backend |
| Can terminal data be fed into ghostty externally? | **VALIDATED** — PoC 08, importFlatCells() populates RenderState directly |
| Does ghostty support Kitty keyboard protocol? | **YES** — `src/input/key.zig`, CSI u encoding |

---

## Conclusion

**The project is feasible.** The highest-risk items (PTY decoupling, rendering pipeline) have been validated by PoC 06–08. The native IME decision eliminates the OS dependency risk. Each development phase delivers independent value.
