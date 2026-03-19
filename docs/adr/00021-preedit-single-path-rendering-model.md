# 00021. Preedit Single-Path Rendering Model

- Date: 2026-03-18
- Status: Accepted

## Context

Preedit (IME in-composition) text must be displayed on the client terminal
surface. Two rendering paths were possible: inject preedit content into the
normal cell data stream (I/P-frames), or add a dedicated preedit section to the
FrameUpdate JSON metadata alongside the cell data.

A dedicated preedit section in the metadata would require every rendering client
to implement preedit-aware rendering logic — merging the preedit section with
regular cell data before drawing. This creates two classes of clients: those
that support the preedit rendering extension and those that do not.

The protocol also has a `"preedit"` capability flag for the 0x0400-range
lifecycle messages (PreeditStart/Update/End/Sync), which provide composition
state metadata for multi-client coordination and observer UIs. It was important
to clarify whether this capability gate also controlled rendering.

## Decision

Preedit rendering goes through cell data in I/P-frames only. The server injects
preedit cells into frame cell data at serialization time. There is no separate
preedit section in FrameUpdate JSON metadata.

The `"preedit"` capability controls only the dedicated preedit lifecycle
messages in the 0x0400 range (PreeditStart, PreeditUpdate, PreeditEnd,
PreeditSync). It does not gate rendering. Preedit content is always present in
cell data regardless of capability negotiation — any client that can render
cells automatically renders preedit content. A client that only needs to render
can ignore all 0x04xx messages entirely.

## Consequences

- All rendering clients get preedit display for free — no preedit-specific
  rendering code required at the client layer.
- The 0x04xx lifecycle messages are optional metadata for clients that need
  composition state awareness (multi-client coordination, observer UIs, conflict
  resolution); rendering-only clients can ignore them without visual
  degradation.
- The server bears the responsibility of injecting preedit cells into the frame
  at serialization time, keeping that concern in one place.
- Capability negotiation is cleaner: `"preedit"` capability is about lifecycle
  protocol participation, not about whether preedit text appears on screen.
