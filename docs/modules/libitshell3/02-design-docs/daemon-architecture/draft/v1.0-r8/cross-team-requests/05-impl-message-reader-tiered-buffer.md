# Add LargeChunkPool and Update MessageReader Description

- **Date**: 2026-03-29
- **Source team**: impl (Plan 6 over-engineering review)
- **Source version**: libitshell3 implementation Plan 6
- **Source resolution**: ADR 00061 (MessageReader Tiered Buffer Strategy)
- **Target docs**: daemon-architecture `03-integration-boundaries.md`
- **Status**: open

---

## Context

ADR 00061 redesigns `MessageReader` from a 4 KB fixed buffer to a tiered
strategy: 64 KB internal fixed buffer for common messages, with overflow to a
daemon-global `LargeChunkPool` for rare large payloads (e.g., PasteData). The
pool uses a static first chunk (16 MiB in .bss) and dynamically allocates
additional chunks only when multiple clients are simultaneously accumulating
large messages across non-blocking I/O cycles.

The daemon-architecture spec currently describes `MessageReader` as a simple
byte accumulator with no mention of buffer sizing, tiering, or the pool
dependency. The spec also does not mention `LargeChunkPool` as a daemon
resource.

## Required Changes

### Change 1: §1.2 Layer 2 Framing — update MessageReader description

**Current**:

> **`MessageReader`** — accumulates bytes fed by the caller, extracts complete
> frames. Handles buffer management, fragment reassembly, and incomplete message
> detection.

**Should be**:

> **`MessageReader`** — accumulates bytes fed by the caller, extracts complete
> frames. Uses a tiered buffer strategy: a 64 KB internal fixed buffer handles
> common messages (control, heartbeat, input events) with zero allocation.
> Messages exceeding 64 KB borrow a 16 MiB chunk from the daemon-global
> `LargeChunkPool`. See ADR 00061 for design rationale and concurrent large
> message handling.

### Change 2: §6.2 ClientState struct — add pool dependency note

**Current**:

```zig
message_reader: protocol.MessageReader,
```

> `message_reader` | Per-connection framing state. Accumulates partial messages
> across `recv()` calls.

**Should add note**:

> `MessageReader` requires a reference to the daemon's `LargeChunkPool` for
> overflow allocation of messages exceeding the 64 KB internal buffer.

### Change 3: Add LargeChunkPool to daemon resource inventory

The spec should mention `LargeChunkPool` as a daemon-owned resource alongside
`SessionManager` and `ClientManager`. Suggested location: a new subsection in
Section 4 (Ring Buffer Architecture) or a new section on daemon memory
resources.

**Content**:

> **`LargeChunkPool`** — daemon-global pool of 16 MiB chunks for `MessageReader`
> overflow. First chunk is statically allocated (.bss). Additional chunks are
> dynamically allocated on demand and retained for reuse. Single- threaded; no
> locking required. See ADR 00061.

## Summary Table

| Target Doc                  | Section/Component            | Change Type | Source    |
| --------------------------- | ---------------------------- | ----------- | --------- |
| `03-integration-boundaries` | §1.2 MessageReader desc      | Update      | ADR 00061 |
| `03-integration-boundaries` | §6.2 ClientState struct      | Add note    | ADR 00061 |
| `03-integration-boundaries` | New: LargeChunkPool resource | Add         | ADR 00061 |
