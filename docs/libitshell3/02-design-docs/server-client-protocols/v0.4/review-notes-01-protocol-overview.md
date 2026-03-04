# Review Notes: 01-protocol-overview.md (v0.4)

**Reviewer**: heejoon.kang
**Date**: 2026-03-04

---

## Issue 1: Multi-tab scenario requires multi-connection model, but spec does not document it

**Severity**: High (architectural gap — affects multi-tab UX)

### Problem

Section 5.2 states:

> **Single-session-per-connection rule:** A client connection is attached to at most
> one session at a time. To switch sessions, the client must first detach
> (`DetachSessionRequest`) then attach to the new session.

This rule is correct at the protocol level, but the spec **never documents how a
client with multiple tabs maintains simultaneous access to multiple sessions.**

it-shell3 is a native macOS/iOS terminal app with multiple tabs. Each tab maps to
a Session (doc 03 confirms this: "mapping each libitshell3 Session to one host tab").
The user expects:

- All tabs rendering simultaneously (not just the foreground tab)
- Input to any tab without detach/attach ceremony
- FrameUpdate delivery for all visible sessions, not just the attached one

With single-session-per-connection, the only viable model is **one Unix socket
connection per session (tab)**:

```
Client app
├── Connection 1 → Unix socket → daemon → Session A (tab 1)
├── Connection 2 → Unix socket → daemon → Session B (tab 2)
└── Connection 3 → Unix socket → daemon → Session C (tab 3)
```

This is architecturally sound — each connection has independent state, independent
FrameUpdate streams, and no detach/attach overhead when switching tabs. But the
spec says nothing about it.

### Additional concern: SSH tunneling with multiple connections

For Phase 6 (iOS-to-macOS over SSH), the client needs multiple Unix socket
connections over a single SSH tunnel. This is supported — SSH natively multiplexes
channels:

```
SSH TCP connection (1 connection)
├── Channel 1 → forwarded Unix socket → Session A
├── Channel 2 → forwarded Unix socket → Session B
└── Channel 3 → forwarded Unix socket → Session C
```

Each SSH channel acts as an independent socket connection from the daemon's
perspective. No protocol changes needed — SSH handles mux/demux transparently.

However, this interaction between multi-connection and SSH tunneling is not
documented anywhere.

### What is missing from the spec

1. **Multi-connection model**: Explicit statement that a client SHOULD open one
   connection per session for multi-tab scenarios. The single-session-per-connection
   rule implicitly requires this, but it should be stated as the canonical pattern.

2. **Connection lifecycle for tabs**: When the user opens a new tab, the client
   opens a new connection, performs handshake, and creates/attaches a session.
   When a tab is closed, the client destroys the session and closes the connection.
   This workflow is not documented.

3. **Max connections per client**: No limit is specified. Should the daemon enforce
   a maximum number of simultaneous connections? (e.g., 256 connections = 256 tabs).

4. **SSH tunnel interaction**: Document that multiple connections over a single SSH
   tunnel works via SSH channel multiplexing. No special protocol support needed.

5. **Handshake overhead**: Each connection requires a full ClientHello/ServerHello
   exchange. For a user rapidly opening 10 tabs, that's 10 handshakes. Is this
   acceptable, or should the spec consider a lightweight "additional connection"
   handshake for already-authenticated clients?

### Recommendation

Add a new subsection (e.g., Section 5.5 "Multi-Session Client Model") documenting:

1. One connection per session as the canonical multi-tab pattern
2. Connection lifecycle aligned with tab lifecycle
3. SSH tunnel multiplexing for remote clients
4. Maximum connection limit policy (or explicit "no limit, daemon discretion")
5. Whether handshake optimization for additional connections is needed or deferred

Reference investigation needed: check how tmux handles the multi-window/multi-pane
case — does `tmux` use multiple server connections, or a single connection with
multiplexed window switching? This would inform whether our multi-connection model
is aligned with or divergent from established patterns.

---

## Issue 2: Remove `ERR_DECOMPRESSION_FAILED` — dead error code for non-existent feature

**Severity**: Minor (spec hygiene)

### Problem

The error code table includes:

| `0x00000007` | `ERR_DECOMPRESSION_FAILED` | Decompression failed (COMPRESSED flag set but compression not supported in v1) |

v0.3 Issue 5 resolved to **remove application-layer compression from v1** entirely.
The COMPRESSED flag bit is reserved, and Section 3.5 states:

> "Senders MUST NOT set the COMPRESSED flag."

If no conforming implementation ever sets COMPRESSED=1, then `ERR_DECOMPRESSION_FAILED`
has no legitimate sender. A non-conforming sender that sets a reserved flag is
committing a **protocol violation**, which should be handled by the existing generic
`ERR_PROTOCOL_ERROR` — not a dedicated error code for a feature that doesn't exist.

Keeping `ERR_DECOMPRESSION_FAILED` in the spec implies compression is partially
implemented, creating confusion about the feature's actual status.

Additionally, the reader loop pseudocode (Section 11.2) still references
`ERR_DECOMPRESSION_FAILED`:

```
if header.flags.compressed:
    return Error(ERR_DECOMPRESSION_FAILED)  // v1: compression not supported
```

This should be updated to match.

Section 11.3 (Deferred Optimizations) also includes compression as a deferred item
with language implying it is planned for v2. The v0.3 resolution was "remove from
v1" — not "schedule for v2." This entry reinforces the false impression that
compression is a committed future feature.

### Recommendation

1. Remove `ERR_DECOMPRESSION_FAILED` (`0x00000007`) from the error code table
2. Section 3.5: change "Receivers that encounter COMPRESSED=1 SHOULD send
   `ERR_DECOMPRESSION_FAILED`" to "Receivers that encounter COMPRESSED=1 SHOULD
   send `ERR_PROTOCOL_ERROR`" (or simply close the connection)
3. Section 11.2 pseudocode: change `ERR_DECOMPRESSION_FAILED` to
   `ERR_PROTOCOL_ERROR`
4. Section 11.3: reword "Deferred to v2" to "Removed from v1. No commitment
   to reintroduce." or remove the entry entirely
5. Reserve error code `0x00000007` for future use (if compression is ever
   re-introduced, add the error code alongside the feature)

---

## Issue 3: Version field semantics and comparison logic undefined

**Severity**: Medium (affects protocol evolution and forward/backward compatibility)

### Problem

The reader loop pseudocode (Section 11.2) performs an exact version match:

```
if header.version != PROTOCOL_VERSION:
    return Error(ERR_UNSUPPORTED_VERSION)
```

This means **any** version change — even a compatible one — breaks all existing
implementations. The spec does not define:

1. What constitutes a "version bump" vs. a compatible extension
2. Whether the version field represents wire format version, protocol revision,
   or something else
3. How the version check should be performed (exact match, range, minimum)

Meanwhile, the protocol already has a **capability negotiation** mechanism in the
handshake (`ClientHello.capabilities` / `ServerHello.capabilities`). This creates
ambiguity: when should a change bump the version number vs. add a new capability?

### Analysis: three options

| Option | Version semantics | Comparison logic | When to bump |
|--------|------------------|-----------------|--------------|
| **A: Wire format only** | Version = binary header layout. Capability negotiation handles all message-level evolution. | Exact match (current). Acceptable because header layout almost never changes. | Only when the 16-byte header structure itself changes (essentially never after v1). |
| **B: Major.minor split** | Split the 1-byte field into 4-bit major + 4-bit minor. Major = breaking, minor = compatible additions. | `major == MAJOR && minor >= MIN_MINOR` | Major: header/encoding changes. Minor: new message types, new required fields. |
| **C: Minimum version** | Version = monotonically increasing protocol revision. | `header.version >= MIN_SUPPORTED && header.version <= CURRENT` | Any normative spec change. Receiver supports a range of versions. |

### Option A rationale (recommended for discussion)

The capability mechanism already handles compatible evolution:
- New message type → add a capability flag, negotiate at handshake
- New optional field → just add it (receivers tolerate unknown fields per JSON convention)
- New required field → add a capability flag; only send if peer declared support

If capabilities handle all compatible changes, the version byte only needs to
change for truly breaking wire format changes (e.g., header size change, endianness
change). These are so rare that exact match is fine — it's essentially a magic
number extension.

This avoids duplicating evolution logic between version comparison and capability
negotiation. One mechanism, one place.

### Option B rationale

If the team wants version-based evolution without capabilities for simpler changes,
major.minor gives fine-grained control. However, 4 bits = 16 values per axis, which
may be limiting. Also creates "which mechanism do I use?" confusion alongside
capabilities.

### Option C rationale

Simple and common in network protocols. But requires the receiver to maintain a
`MIN_SUPPORTED_VERSION` which accumulates technical debt — at what point do you
drop support for old versions?

### Recommendation

The protocol designer should:

1. **Define what the version byte means**: wire format version (Option A),
   protocol revision (Option C), or hybrid (Option B)
2. **Define the relationship between version and capabilities**: which changes
   go through which mechanism
3. **Update Section 11.2 pseudocode** to reflect the chosen comparison logic
4. **Document the evolution policy**: how future changes should be introduced
   (version bump vs. capability flag vs. optional field)

---

## Issue 4: Input method / keyboard layout field naming inconsistent across documents

**Severity**: Medium (cross-document inconsistency — affects implementer clarity)

### Problem

The v0.3 Issue 6 resolution introduced a two-axis model (`input_method` +
`keyboard_layout`) with string identifiers. However, the field names are
inconsistent across the six documents:

| Message (Direction) | Field names | Pattern |
|---|---|---|
| KeyEvent (C→S) | `input_method` | no prefix |
| InputMethodSwitch (C→S) | `input_method`, `keyboard_layout` | no prefix |
| InputMethodAck (S→C) | `active_input_method`, `active_keyboard_layout` | `active_` prefix |
| PreeditStart (S→C) | `active_input_method` | `active_` prefix |
| PreeditSync (S→C) | `active_input_method` | `active_` prefix |
| LayoutChanged leaf (S→C) | `active_input_method`, `active_keyboard_layout` | `active_` prefix |
| pane_input_methods (S→C) | `active_input_method`, `active_keyboard_layout` | `active_` prefix |
| ClientHello | `preferred_input_methods[].method` | abbreviated |
| ServerHello | `supported_input_methods[].method`, `.layouts` | abbreviated, **plural** |
| Default for new panes | `input_method`, `keyboard_layout` | no prefix |

Three inconsistencies:

### 4a. `active_` prefix convention is implicit

C→S messages use `input_method`; S→C messages use `active_input_method`. This
looks like an intentional pattern (request vs. state) but it is **never stated
as a convention** in any document. An implementer seeing `input_method` in
KeyEvent and `active_input_method` in PreeditStart has no way to know this is
deliberate, not a typo.

### 4b. Handshake objects use abbreviated field names

Inside `preferred_input_methods` and `supported_input_methods` arrays, the field
is just `method` — not `input_method`. Similarly `layout` / `layouts` — not
`keyboard_layout`. This creates a third naming variant for the same concept.

### 4c. `layout` (singular optional) vs `layouts` (plural array)

- ClientHello: `{"method": "korean_2set"}` — `layout` is optional, singular
- ServerHello: `{"method": "korean_2set", "layouts": ["qwerty"]}` — `layouts`
  is a plural array

The asymmetry is semantically justified (client declares one preference, server
advertises multiple options), but the singular/plural inconsistency between the
same nested object structure is confusing.

### Recommendation

1. **Document the `active_` prefix convention** in Section 7 (Encoding
   Conventions) or in a new "Field Naming Conventions" subsection:
   > C→S messages use bare field names (`input_method`, `keyboard_layout`) to
   > indicate a requested or declared value. S→C messages use the `active_`
   > prefix (`active_input_method`, `active_keyboard_layout`) to indicate
   > current authoritative state.

2. **Decide on handshake object field names**: either expand to full names
   (`input_method`, `keyboard_layout`) for consistency, or document why the
   abbreviated forms are used (brevity inside arrays).

3. **Align singular/plural**: either both use `layout`/`layouts` with clear
   documentation of when each form appears, or normalize to one form.
