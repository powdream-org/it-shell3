# Move Server Negotiation Algorithms to Daemon Handshake Docs

- **Date**: 2026-03-21
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), Doc 02 §7.1–§7.3 was
identified as containing server-internal implementation algorithms:

- §7.1: Version selection algorithm —
  `min(server_max_version, client.protocol_version_max)` pseudocode
- §7.2: Capability set intersection algorithm
- §7.3: Render capability intersection and `ERR_CAPABILITY_REQUIRED` validation
  logic

These are implementation algorithms that describe how the server processes
negotiation, not wire-observable facts. A protocol-only implementor (someone
writing a compatible client without access to our server source) does not need
to know how the server selects the negotiated version internally — only that
`Error(ERR_VERSION_MISMATCH)` is sent when the versions are incompatible, and
that `Error(ERR_CAPABILITY_REQUIRED)` is sent when no common rendering mode
exists.

The wire-observable outcomes (which error codes are sent under which conditions)
remain stated in the protocol spec. The server-side decision algorithms —
`min()` selection, set intersection, validation gating — belong in daemon
handshake documentation.

## Required Changes

1. **Version selection algorithm**: Add the `min()` negotiation logic to daemon
   handshake docs, including the two `ERR_VERSION_MISMATCH` guard conditions
   (negotiated version below client minimum and below server minimum).
2. **Capability intersection algorithm**: Add the general capability set
   intersection algorithm to daemon handshake docs, including the
   forward-compatibility rule (unknown capability names are ignored).
3. **Render capability intersection and validation**: Add the render capability
   intersection algorithm and the `ERR_CAPABILITY_REQUIRED` validation gate
   (disconnect if neither `cell_data` nor `vt_fallback` is in the negotiated
   render capability set) to daemon handshake docs.

## Summary Table

| Target Doc            | Section             | Change Type | Source Resolution             |
| --------------------- | ------------------- | ----------- | ----------------------------- |
| Daemon handshake docs | Version negotiation | Add         | Protocol v1.0-r12 Doc 02 §7.1 |
| Daemon handshake docs | Capability matching | Add         | Protocol v1.0-r12 Doc 02 §7.2 |
| Daemon handshake docs | Render cap matching | Add         | Protocol v1.0-r12 Doc 02 §7.3 |

## Reference: Original Protocol Text (removed from Doc 02 §7)

The following is the original text as it appeared in the protocol spec before
removal. Provided as reference for the daemon team — adapt as needed.

### From §7.1 — Protocol Version

The server selects the negotiated protocol version as:

```
negotiated_version = min(server_max_version, client.protocol_version_max)

if negotiated_version < client.protocol_version_min:
    -> send Error(ERR_VERSION_MISMATCH), disconnect
if negotiated_version < server_min_version:
    -> send Error(ERR_VERSION_MISMATCH), disconnect
```

In v1, both `protocol_version_min` and `protocol_version_max` are `1`. This
field exists for future version negotiation.

### From §7.2 — General Capabilities

```
negotiated_caps = intersection(client.capabilities, server.capabilities)
```

Each capability is independently negotiated as the intersection of client and
server flag sets. A capability is active only if both sides support it. Unknown
capability names are ignored (forward compatibility).

### From §7.3 — Render Capabilities

```
negotiated_render_caps = intersection(client.render_capabilities, server.render_capabilities)
```

The server validates that at least one rendering mode is supported:

```
if "cell_data" not in negotiated_render_caps and "vt_fallback" not in negotiated_render_caps:
    -> send Error(ERR_CAPABILITY_REQUIRED, detail="No common rendering mode"), disconnect
```
