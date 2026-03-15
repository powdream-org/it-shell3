# IME Interface Contract — ghostty Integration (Reference)

## 1. ghostty Integration

ghostty integration — how `ImeResult` is consumed by the daemon to drive the key input and preedit pipeline (`key_encode.encode()`, `write(pty_fd)`, `overlayPreedit()`) — is defined in the `libitshell3` daemon design docs.

The IME engine has no direct interaction with ghostty. It produces `ImeResult` structs; the daemon consumes them.

## 2. Memory Ownership

`ImeResult` slices (`committed_text`, `preedit_text`) point to internal engine buffers, valid until the next mutating call (`processKey()`, `flush()`, `reset()`, `deactivate()`, `setActiveInputMethod()`). Zero heap allocation per keystroke.

For buffer layout, sizing rationale, and libhangul memory model details, see `10-hangul-engine-internals.md` §3 in the behavior docs.

**Caller responsibility**: If the caller needs to retain the text across multiple `processKey()` calls, it must copy the data. See the `libitshell3` daemon design docs for the daemon's consumption invariant.

### Shared Engine Invariant

When multiple panes share a single engine instance (per-session ownership), the caller MUST consume the `ImeResult` (process `committed_text`, update preedit) before making any subsequent call to the same engine instance. This is required because the next call overwrites the engine's internal buffers.

In practice, this is satisfied naturally: the server processes one key event at a time on the main thread, and `ImeResult` consumption is synchronous within the key handling path.
