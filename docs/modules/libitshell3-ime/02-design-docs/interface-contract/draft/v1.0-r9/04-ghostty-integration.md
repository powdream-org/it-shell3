# IME Interface Contract — ghostty Integration (Reference)

## 1. ghostty Integration

ghostty integration — how `ImeResult` is consumed by the daemon to drive the key input and preedit pipeline (`key_encode.encode()`, `write(pty_fd)`, `overlayPreedit()`) — is defined in [daemon design doc 01 §4](../../../../../libitshell3/02-design-docs/daemon/draft/v1.0-r3/01-internal-architecture.md) and [daemon design doc 02 §4](../../../../../libitshell3/02-design-docs/daemon/draft/v1.0-r3/02-integration-boundaries.md#4-ime-integration-libitshell3-ime).

The IME engine has no direct interaction with ghostty. It produces `ImeResult` structs; the daemon consumes them.

## 2. Memory Ownership

`ImeResult` slices (`committed_text`, `preedit_text`) point to internal engine buffers, valid until the next mutating call (`processKey()`, `flush()`, `reset()`, `deactivate()`, `setActiveInputMethod()`). Zero heap allocation per keystroke.

For buffer layout, sizing rationale, and libhangul memory model details, see [behavior/draft/v1.0-r1/10-hangul-engine-internals.md](../../../behavior/draft/v1.0-r1/10-hangul-engine-internals.md) Section 3.

**Caller responsibility**: If the caller needs to retain the text across multiple `processKey()` calls, it must copy the data. See [daemon design doc 02 §4.6](../../../../../libitshell3/02-design-docs/daemon/draft/v1.0-r3/02-integration-boundaries.md#46-critical-runtime-invariant) for the daemon's consumption invariant.

### Shared Engine Invariant

When multiple panes share a single engine instance (per-session ownership), the caller MUST consume the `ImeResult` (process `committed_text`, update preedit) before making any subsequent call to the same engine instance. This is required because the next call overwrites the engine's internal buffers.

In practice, this is satisfied naturally: the server processes one key event at a time on the main thread, and `ImeResult` consumption is synchronous within the key handling path.
