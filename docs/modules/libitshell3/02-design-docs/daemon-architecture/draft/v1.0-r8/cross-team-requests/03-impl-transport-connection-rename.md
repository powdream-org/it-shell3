# Rename `transport.Connection` to `transport.SocketConnection`

- **Date**: 2026-03-29
- **Source team**: impl (transport-v2 prototyping)
- **Source version**: daemon-architecture draft/v1.0-r8
- **Source resolution**: transport-v2 implementation — plain struct with direct
  syscall wrappers, no vtable
- **Target docs**: daemon-architecture `03-integration-boundaries.md`
- **Status**: open

---

## Context

The spec defines `transport.Connection` as a plain struct with `fd` +
`recv()`/`send()`/`sendv()`/`close()`. The transport-v2 implementation follows
this design exactly as `transport.SocketConnection` — a plain struct backed by a
Unix socket fd with direct syscall wrappers and result union types
(`RecvResult`/`SendResult`).

The rename from `Connection` to `SocketConnection` clarifies that this is a
concrete Unix socket implementation. Future SSH support will add
`SshChannelConnection` as a separate type (not polymorphic — each transport has
its own concrete struct).

**Note:** The protocol team's CTR
`server-client-protocols/draft/v1.0-r9/cross-team-requests/01-daemon-architecture-requirements.md`
Section 1.3 defines `transport.Connection` with the same semantic. That CTR is a
historical record; future references should use `transport.SocketConnection`.

## Required Changes

### Change 1: §1.5.3 Connection — rename type

**Current**:

```zig
pub const Connection = struct {
    fd: posix.fd_t,
```

**Should be**:

```zig
pub const SocketConnection = struct {
    fd: posix.fd_t,
```

### Change 2: §1.9 Naming Convention

**Current**:

> Types use namespace-qualified names: `transport.Listener`,
> `transport.Connection`

**Should be**:

> Types use namespace-qualified names: `transport.Listener`,
> `transport.SocketConnection`

### Change 3: §6.2 ClientState Struct

**Current**:

```zig
conn: transport.Connection,
```

**Should be**: Remove this field. `server.ClientState` wraps
`server.ConnectionState` which owns the `SocketConnection`. See the
`server.ConnectionState` design discussion for the layered ownership model.

### Change 4: §8 Transport-Agnostic Design

**Current**:

> The daemon always interacts with `transport.Connection` values.

**Should be**:

> The daemon always interacts with `transport.SocketConnection` values.

Also update the Mermaid diagram notes:

- `"Daemon sees:<br/>transport.Connection<br/>from Listener.accept()"`
- → `"Daemon sees:<br/>transport.SocketConnection<br/>from Listener.accept()"`

## Summary Table

| Target Doc                  | Section/Component          | Change Type | Source            |
| --------------------------- | -------------------------- | ----------- | ----------------- |
| `03-integration-boundaries` | §1.5.3 Type name           | Rename      | transport-v2 impl |
| `03-integration-boundaries` | §1.9 Naming Convention     | Rename      | transport-v2 impl |
| `03-integration-boundaries` | §6.2 ClientState struct    | Update      | transport-v2 impl |
| `03-integration-boundaries` | §8 Transport-Agnostic text | Rename      | transport-v2 impl |
| `03-integration-boundaries` | §8 Mermaid diagram         | Rename      | transport-v2 impl |
