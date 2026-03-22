# Remove Compression Capability Example from Client State

- **Date**: 2026-03-20
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup) — ADR 00027
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

ADR 00027 (YAGNI — Remove Compression Header Flag and Capability) removes the
`"compression"` capability string from the protocol capability registry
entirely. It was previously reserved in ADR 00014 but never active.

The daemon `03-lifecycle-and-connections.md` describes the per-client state
fields, where the `capabilities` field description uses `"compression support"`
as an example. This reference must be removed.

## Required Changes

1. **capabilities field description in per-client state table**: Remove
   `"compression support"` from the example list. The capabilities field
   description should reference protocol extensions generically without naming
   compression as an example.

## Summary Table

| Target Doc                        | Section/Field                                | Change Type | Source Resolution |
| --------------------------------- | -------------------------------------------- | ----------- | ----------------- |
| `03-lifecycle-and-connections.md` | Per-client state table, `capabilities` field | Edit        | ADR 00027         |

## Reference: Original Protocol Text (from daemon 03 per-client state table)

```
| `capabilities`     | Negotiated capabilities from handshake (e.g., compression support, protocol extensions) |
```

**Suggested replacement**:

```
| `capabilities`     | Negotiated capabilities from handshake (e.g., clipboard_sync, mouse, preedit) |
```
