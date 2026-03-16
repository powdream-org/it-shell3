# 00024. Capability Negotiation Mechanics

- Date: 2026-03-16
- Status: Accepted

## Context

A terminal multiplexer protocol must handle feature differences between client
and server versions. tmux uses implicit version-guessing: clients infer server
capabilities from the reported version string, and servers assume client
capabilities similarly. This pattern is fragile — it breaks when features are
backported, when patch versions diverge across distributions, and when
third-party clients (e.g., iTerm2 tmux -CC mode) must hard-code version
thresholds for each optional behavior.

libitshell3 is designed for long-term evolution. The protocol must support
optional features (CJK preedit sync, future extensions) that not all clients or
servers will implement at the same time.

## Decision

Use **explicit capability negotiation** with string arrays and set intersection
instead of version-based feature guessing.

During the handshake phase, both client and server declare the capabilities they
support as string arrays. The effective capability set for the connection is the
intersection of the two arrays. Features outside the intersection are not used
for that connection, regardless of what either side's version number might
suggest.

Post-handshake, an extension negotiation mechanism (`ExtensionList` /
`ExtensionListAck`) allows declaring and accepting optional protocol extensions
with per-extension versioning and configuration, independent of the base
protocol version.

## Consequences

- No version-guessing — a v1.2 client connecting to a v1.0 server discovers the
  exact feature set at handshake time, not by consulting a compatibility table.
- Third-party clients need only implement the negotiation handshake, not
  maintain a mapping of version numbers to feature sets.
- New optional features can be introduced without bumping the base protocol
  version; they are simply new capability strings or extensions.
- Slight increase in handshake payload size (string arrays instead of a single
  version integer), negligible over Unix socket.
