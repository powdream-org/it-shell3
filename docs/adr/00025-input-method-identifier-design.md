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
range and updating the table everywhere. On a Unix socket at typing speeds (~15
keystrokes/s), the ~13-byte overhead of a string identifier per KeyEvent is
negligible (not a performance constraint).

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

## Consequences

- Identifiers are self-documenting on the wire — a packet capture is readable
  without consulting a numeric table.
- Adding a new input method requires only a new string value in the registry; no
  schema migration, no reserved numeric range allocation.
- The decomposition boundary is explicit: only the engine constructor knows how
  to map `"korean_2set"` to a libhangul keyboard constant. All other layers
  treat the string as opaque.
- The IME Interface Contract Section 3.7 is the authoritative registry; clients,
  server, and tooling all defer to it. No local mapping tables.
- ~13 bytes per KeyEvent overhead is irrelevant at typing speeds over a local
  Unix socket.
