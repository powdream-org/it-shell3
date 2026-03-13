# IME Interface Contract v0.8 — ghostty Integration (Reference)

> **Version**: v0.8
> **Date**: 2026-03-10
> **Part of the IME Interface Contract v0.8. See [01-overview.md](01-overview.md) for the document index.**
> **Changes from v0.7**: Entire section replaced with reference. Content moved to daemon design docs v0.3.

## 5. ghostty Integration

ghostty integration — how `ImeResult` is consumed by the daemon to drive the key input and preedit pipeline (`key_encode.encode()`, `write(pty_fd)`, `overlayPreedit()`) — is defined in [daemon design doc 01 §4](../../libitshell3/02-design-docs/daemon/draft/v1.0-r3/01-internal-architecture.md) and [daemon design doc 02 §4](../../libitshell3/02-design-docs/daemon/draft/v1.0-r3/02-integration-boundaries.md#4-ime-integration-libitshell3-ime).

The IME engine has no direct interaction with ghostty. It produces `ImeResult` structs; the daemon consumes them.

## 6. Memory Ownership

### Rule: Internal Buffers, Invalidated on Next Mutating Call

`ImeResult` fields (`committed_text`, `preedit_text`) are slices pointing into **fixed-size internal buffers** owned by the `HangulImeEngine` instance:

```
committed_buf: [256]u8  -- holds committed UTF-8 text
preedit_buf:   [64]u8   -- holds preedit UTF-8 text
```

**Lifetime**: Slices are valid until the next call to `processKey()`, `flush()`, `reset()`, `deactivate()`, or `setActiveInputMethod()` on the **same** engine instance.

**Rationale**: This mirrors libhangul's own memory model — `hangul_ic_get_preedit_string()` returns an internal pointer invalidated by the next `hangul_ic_process()` call. Zero heap allocation per keystroke.

**Buffer sizing**:
- 256 bytes for committed text: a single Korean syllable is 3 bytes UTF-8. The longest possible commit from one keystroke is a flushed syllable + a non-jamo character = ~6 bytes. 256 bytes is vastly oversized for safety.
- 64 bytes for preedit: a single composing syllable is always exactly one character (3 bytes UTF-8). 64 bytes is vastly oversized for safety.

**Caller responsibility**: If the caller needs to retain the text across multiple `processKey()` calls, it must copy the data. See [daemon design doc 02 §4.6](../../libitshell3/02-design-docs/daemon/draft/v1.0-r3/02-integration-boundaries.md#46-critical-runtime-invariant) for the daemon's consumption invariant.

### Shared Engine Invariant

When multiple panes share a single engine instance (per-session ownership), the caller MUST consume the `ImeResult` (process `committed_text`, update preedit) before making any subsequent call to the same engine instance. This is required because the next call overwrites the engine's internal buffers.

In practice, this is satisfied naturally: the server processes one key event at a time on the main thread, and `ImeResult` consumption is synchronous within the key handling path.
