# Review Notes #02: Encoding Format & FPS Target

**Date**: 2026-03-04
**Status**: RESOLVED — all open questions addressed in Rounds 4-5

---

## Discussion Summary

Three rounds of team debate (5 agents: protocol-architect, systems-engineer, rendering-cjk-specialist, ghostty-researcher, iterm2-researcher) on binary vs text-based encoding and the 60fps design target.

## Round 1: Unanimous Binary

Team argued "10K cells x 60fps requires binary for bandwidth." All three specialists chose uniform binary.

## Round 2: Owner Challenges "60fps" and Debuggability

**Owner's challenge**: "This is a terminal — do we really need 60fps?"

**Findings**:
- 60fps was a strawman. Real terminal workloads are 0-30fps, burst-coalesced.
- At realistic data rates (<480 KB/s worst case), JSON parsing is unmeasurable (<0.01% CPU).
- Binary justified on engineering grounds (zero-copy Zig structs, O(1) dispatch), not throughput.

**Owner's follow-up**: "Also weigh debuggability, traceability, and maintainability."

**Findings**:
- Binary requires custom `itshell3-dump` tool (second deserializer to maintain).
- JSON gives `socat | jq` debugging for free.
- Cross-language clients (Swift): JSON = `JSONDecoder`; binary = manual byte parsing.
- Positions shifted: margin between binary and JSON became "thin."

## Round 3: Reference Data + Full Debate

### Reference findings

**ghostty** (source: vendors/ghostty/):
- Event-driven rendering, NO fixed fps. xev.Async coalescing.
- CVDisplayLink on macOS (vsync). Commented-out 10ms coalescing timer.
- GPU struct (`CellText`, 32B) is 70%+ client-local data (font shaping, atlas coords).
- **Zero-copy wire-to-GPU is impossible** — daemon sends semantic data, client does font shaping.
- Debugging: built entire ImGui inspector tool. Opaque data requires tooling investment.

**iTerm2** (source: ~/dev/git/references/iTerm2/):
- Adaptive cadence: 60fps interactive → 30fps Metal / 15fps legacy during heavy throughput → 1fps idle.
- 120fps on ProMotion ARM Macs.
- tmux-CC (TEXT protocol) for multiplexer integration — works but brittle.
- **Brittleness is protocol design, not text encoding**: no length framing, regex parsing, octal escapes, version workarounds back to 2013.
- Keystroke latency optimization: immediate draw when throughput < 1KB/s + recent keystroke.

### Final consensus: Hybrid

**Binary Framing + Binary CellData + JSON Everything Else**

```
[16-byte binary header] → dispatch on type + encoding flag
    │
    ├── FrameUpdate: [binary frame header][binary DirtyRows/CellData][JSON metadata blob]
    │
    └── Everything else: [JSON payload]
```

| Component | Encoding | Rationale |
|-----------|----------|-----------|
| Message header | Binary (16B) | O(1) dispatch, unambiguous framing |
| DirtyRows + CellData | Binary | 70-95% of payload, 3x smaller, RLE-compatible |
| Cursor, Preedit, Colors, Dimensions | JSON blob | Debuggable; preedit shows `"한"` not hex |
| Control messages (key, resize, focus) | JSON | Low frequency, schema evolution, cross-language |
| Handshake/negotiation | JSON | Self-describing, version discovery |
| Errors | JSON | Human-readable |

### What killed uniform binary

| Old argument | Evidence against | Source |
|-------------|-----------------|--------|
| Zero-copy wire-to-GPU | GPU struct 70% client-local (font shaping, atlas) | ghostty source |
| Uniform = one code path | We'd embed JSON inside binary anyway (config, errors, layouts) | systems-engineer |
| Text = brittleness | tmux-CC brittle from ad-hoc design, not text encoding | iTerm2 source |
| 60fps requires binary | Real workloads 0-30fps, JSON at 480KB/s is <0.01% CPU | all debaters |

### What justifies binary CellData (reframed)

- **Volume**: 38KB binary vs 120KB+ JSON per full 80x24 frame
- **RLE**: Fixed-size cells work naturally with run-length encoding
- **Deterministic sizing**: Client pre-allocates exactly
- **Mobile/iPad**: Avoids JSON tokenization of 2000+ cells/frame

### Additional recommendations

1. **Adaptive cadence** (iTerm2 model): 60fps interactive → 30fps heavy → 1fps idle
2. **Keystroke bypass**: Priority flag in header for immediate draw
3. **Cursor blink**: Client-side (server sends state, client runs timer)
4. **CellData is SEMANTIC, not GPU-aligned**: codepoint + style + fg/bg + wide flag

---

## Round 4: Protobuf + Coalescing + Go vs Zig

### Protobuf — NO for v1

**Unanimous.** Rendering specialist initially favored full protobuf, then conceded after debate.

| Argument for protobuf | Why it lost |
|----------------------|-------------|
| Schema evolution | Capability negotiation + reserved ranges already solve this |
| Smaller for default-styled cells | RLE is an order of magnitude better (blank 80-col row: 22B RLE vs 400B protobuf) |
| Cross-language codegen | JSON for control msgs gives Swift JSONDecoder for free |
| One format for everything | Zig protobuf ecosystem is immature, adds `protoc` build dep |

**Decision**: Keep hybrid. Add `CELLDATA_ENCODING` capability flag so v2 can negotiate alternatives.

### Coalescing — 4-tier adaptive model with preedit bypass

**Unanimous.** Informed by iTerm2's adaptive cadence and ghostty's event-driven model.

| Tier | Condition | Frame interval |
|------|-----------|----------------|
| **Preedit** | Active composition + keystroke | Immediate (0ms) |
| **Interactive** | PTY output <1KB/s + recent keystroke | Immediate (0ms) |
| **Active** | PTY 1-100 KB/s | 16ms (display Hz) |
| **Bulk** | PTY >100KB/s sustained 500ms | 33ms |
| **Idle** | No output 500ms | No frames sent |

Key design decisions:
- **Per-(client, pane) cadence** — one pane at Bulk while another at Preedit
- **Preedit bypasses everything** — coalescing, PausePane, power throttling (90B/frame = negligible cost)
- **"Immediate first, batch rest"** — first frame after idle sends immediately, then coalesces
- **Smooth degradation** before PausePane: queue filling → auto-downgrade tier → PausePane as last resort
- **Client hints** via `ClientDisplayInfo`: `display_refresh_hz`, `power_state`, `preferred_max_fps`
- **iOS power**: auto-reduce fps when client reports battery (cap Active@20fps, Bulk@10fps)
- **Preedit latency**: <33ms end-to-end over Unix socket (MUST)

Transition thresholds:

| Transition | Threshold | Hysteresis |
|-----------|-----------|------------|
| Idle → Interactive | KeyEvent + PTY output within 5ms | None |
| Idle → Active | PTY output without recent keystroke | None |
| Active → Bulk | >100KB/s for 500ms | Drop back at <50KB/s for 1s |
| Active → Idle | No output for 500ms | None |
| Any → Preedit | Preedit state changed | 200ms timeout back to previous |

Reference data:
- **iTerm2**: 2-tier (fast 60fps / slow 15-30fps), 10KB/s threshold, exponential throughput estimator (5 buckets × 33ms = 166ms window, 2x decay)
- **ghostty**: No adaptive fps, xev.Async coalescing, immediate first frame, removed 10ms coalescing timer

### Go vs Zig — Stay with Zig

**Unanimous (5/5).** Dealbreaker: libghostty-vt is Zig, cgo boundary on the hot path negates Go's advantages.

| Go advantage | Why it doesn't help us |
|-------------|----------------------|
| Goroutines | cgo pins goroutines to OS threads during VT parsing |
| Protobuf ecosystem | We decided no protobuf for v1 |
| Mature ecosystem | Irrelevant to our domain (VT parsing, IME, GPU) |
| Cross-compilation | cgo requires Zig toolchain anyway |

| Go disadvantage | Impact |
|----------------|--------|
| cgo on hot path | Thread pinning, scheduler starvation with many panes |
| GC pauses | p99 10-50ms without tuning, our budget is 16ms |
| iOS c-shared | Code signing issues, 5-10MB runtime, double-runtime |
| Two build systems | `go build` + `zig build` + cgo > just `zig build` |

**If Go wanted**: use for CLI client tool only (no cgo, pure socket protocol).

---

## Consolidated Decisions (all rounds)

| Decision | Outcome | Round |
|----------|---------|-------|
| Pane tree | Binary split tree | Pre-existing |
| Encoding format | Hybrid: binary CellData + JSON control | Round 3 |
| 60fps target | Reframe: event-driven + 16ms coalescing ceiling | Round 2 |
| Zero-copy wire-to-GPU | Debunked. CellData is semantic. | Round 3 |
| Protobuf | No for v1. Monitor FlatBuffers for v2. | Round 4 |
| Coalescing | 4-tier adaptive + preedit bypass | Round 4 |
| Language | Stay with Zig | Round 4 |
| Cursor blink | Client-side | Round 2 |
| CellData encoding cap | Add `CELLDATA_ENCODING` capability flag for v2 | Round 4 |
