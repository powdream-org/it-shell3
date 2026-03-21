# 00025. Input Method Identifier Design

- Date: 2026-03-18
- Status: Accepted

## Context

The protocol must identify which input method (composition engine) is active for
a given session so the server's IME engine applies the correct
keycode-to-character mapping. Two identifier schemes were considered: numeric
IDs (compact, opaque) or string identifiers (self-documenting, extensible).

Numeric IDs require a shared mapping table between client and server and any
third-party tooling. Adding a new input method requires reserving a numeric
range and updating the table everywhere. String identifiers are used in every
input message, including KeyEvent, because all input messages are JSON-encoded —
no special encoding path is needed. The ~13-byte overhead per KeyEvent is
irrelevant at typing speeds (~15/s) over a >1 GB/s Unix socket.

The protocol also needed a clear boundary for where the string identifier is
decomposed into engine-specific types — without this, multiple code sites would
need to understand input method internals.

## Decision

String identifiers are used for input methods throughout the protocol. No
numeric IDs exist for input methods. The identifier format is
`"{language}_{variant}"` or `"direct"` (e.g., `"direct"`, `"korean_2set"`,
`"korean_3set_390"`).

The `input_method` string is the canonical identifier. It flows unchanged from
client to server to IME engine constructor. Inside the engine constructor, the
string is decomposed into engine-specific types (e.g., libhangul keyboard IDs).
No code outside the engine constructor performs this decomposition.

The canonical registry of valid `input_method` strings is defined in IME
Interface Contract Section 3.7 and is the single source of truth for all
consumers.

Input methods are negotiated at handshake: the server advertises
`supported_input_methods` in ServerHello; the client selects from them in
ClientHello's `preferred_input_methods`. The selected string then appears in
every KeyEvent for the duration of the session.

The `keyboard_layout` axis (physical key mapping, e.g., `"qwerty"`, `"dvorak"`)
is a separate, orthogonal per-session property and is not encoded in the
`input_method` string. It is established at handshake and omitted from KeyEvent.
Keeping the two axes independent means swapping keyboard layout (e.g., from
QWERTY to Dvorak) does not affect which composition engine is active, and vice
versa.

The keyboard layout field uses different cardinality in ClientHello vs
ServerHello: `layout` (singular, optional) in client preferences vs `layouts`
(plural, array) in server capabilities. This asymmetry is intentional — a client
preference expresses one layout choice per input method; a server capability
advertises all available options.

Both `input_method` and `keyboard_layout` are stored at session level, not per
pane. All panes in a session share the same engine state; no per-pane IME fields
are stored in session snapshots. The client tracks one `active_input_method` per
session.

## Consequences

- Identifiers are self-documenting on the wire — a packet capture is readable
  without consulting a numeric table.
- Adding a new input method requires only a new string value in the registry; no
  schema migration, no reserved numeric range allocation, no bit exhaustion.
- The decomposition boundary is explicit: only the engine constructor knows how
  to map `"korean_2set"` to a libhangul keyboard constant. All other layers
  treat the string as opaque.
- The IME Interface Contract Section 3.7 is the authoritative registry; clients,
  server, and tooling all defer to it. No local mapping tables.
