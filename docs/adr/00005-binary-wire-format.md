# 00005. Binary Wire Format

- Date: 2026-03-16
- Status: Accepted

## Context

The protocol needs a fixed framing format for all messages between daemon and
client over Unix sockets (and SSH tunnels for remote access).

## Decision

16-byte fixed header: magic `0x4954` (2B) + version (1B) + flags (1B) + msg_type
(2B) + reserved (2B) + payload_len (4B) + sequence (4B). All multi-byte fields
are little-endian. The version byte identifies header layout (not protocol
features — capability negotiation handles that). u32 IDs for sessions and panes
(not UUIDs — 4 bytes vs 16 on the wire; UUIDs used only in persistence snapshots
for cross-restart identity).

## Consequences

- O(1) message dispatch from fixed-offset msg_type field.
- 2-byte reserved field provides natural 4-byte alignment and future
  extensibility.
- Little-endian matches all target platforms (Apple Silicon, x86). Big-endian
  platforms would need explicit conversion.
- u32 IDs wrap after ~4 billion — sufficient for session/pane lifetime; never
  reused during daemon lifetime.
