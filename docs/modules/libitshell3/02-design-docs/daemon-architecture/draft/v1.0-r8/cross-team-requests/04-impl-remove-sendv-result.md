# Remove SendvResult — identical to SendResult

- **Date**: 2026-03-29
- **Source team**: impl (transport-v2 prototyping)
- **Source version**: daemon-architecture draft/v1.0-r8
- **Source resolution**: transport-v2 implementation found SendvResult and
  SendResult are structurally identical
- **Target docs**: daemon-architecture `03-integration-boundaries.md`
- **Status**: open

---

## Context

The spec defines `SendvResult` separately from `SendResult` for the `sendv()`
method. Both `posix.write()` and `posix.writev()` return the same error type
(`posix.WriteError`), so the two result unions are identical:

```zig
// SendResult
bytes_written: usize, would_block: void, peer_closed: void, err: posix.WriteError

// SendvResult — same fields, same types
bytes_written: usize, would_block: void, peer_closed: void, err: posix.WriteError
```

A separate type adds no type safety and creates unnecessary duplication.
`sendv()` should return `SendResult`.

## Required Changes

### Change 1: §1.5.3 Connection — remove SendvResult

**Current**:

> The `SendvResult` follows the same pattern as `SendResult` but wraps
> `posix.writev`.

**Should be**: Remove the `SendvResult` mention. `sendv()` returns `SendResult`.

### Change 2: §1.5.3 Connection — sendv signature

**Current**:

```zig
pub fn sendv(self: Connection, iovecs: []posix.iovec_const) SendvResult { ... }
```

**Should be**:

```zig
pub fn sendv(self: Connection, iovecs: []posix.iovec_const) SendResult { ... }
```

## Summary Table

| Target Doc                  | Section/Component  | Change Type | Source            |
| --------------------------- | ------------------ | ----------- | ----------------- |
| `03-integration-boundaries` | §1.5.3 SendvResult | Remove      | transport-v2 impl |
| `03-integration-boundaries` | §1.5.3 sendv sig   | Update      | transport-v2 impl |
