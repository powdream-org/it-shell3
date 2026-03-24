# 00050. No Daemon-Side C API

- Date: 2026-03-24
- Status: Accepted

## Context

The project has three libraries: libitshell3 (daemon core), libitshell3-protocol
(wire protocol), and libitshell3-ime (IME engine). The question is whether
libitshell3 and libitshell3-ime should export C API headers.

libitshell3-protocol already exports a C API for its codec and framing layers —
the Swift client app uses these for wire message handling. This is a clear
cross-language boundary with an external consumer.

libitshell3 and libitshell3-ime have no external consumers. The daemon binary
(`daemon/main.zig`) is written in Zig and imports these libraries directly via
Zig's module system. The client communicates with the daemon exclusively via the
wire protocol — it never calls daemon library functions. libitshell3-ime is an
internal dependency of libitshell3, statically linked into the daemon binary.
Its types (`KeyEvent`, `ImeResult`, `ImeEngine`) are internal — clients send raw
HID keycodes over the wire and receive preedit via FrameUpdate cell data.

## Decision

**No C API for libitshell3 or libitshell3-ime.** These libraries are consumed
only by the Zig daemon binary via direct Zig imports. No C header generation, no
ABI stability guarantees.

Only libitshell3-protocol exports a C API (for Swift client interop). This is a
protocol library concern, separate from the daemon and IME libraries.

## Consequences

- No header generation or ABI stability burden for libitshell3 and
  libitshell3-ime. Internal APIs can change freely between versions.
- The daemon binary is the sole consumer of both libraries. Testing uses Zig's
  built-in test framework, not C API integration tests.
- Third-party embedding of the daemon core (e.g., "use libitshell3 in my own
  terminal app") is not supported. If this use case appears, a C API can be
  added then — the internal Zig API would become the implementation behind the C
  header.
- Client-side ghostty operations (`importFlatCells`, `rebuildCells`) DO need C
  API export — but these are ghostty APIs exported via libghostty, not
  libitshell3 APIs. This is a separate concern (see the ghostty API gap analysis
  in the daemon design docs).
