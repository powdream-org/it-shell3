# Handover: Daemon Architecture + Behavior v1.0-r8 to v1.0-r9

- **Date**: 2026-03-31
- **Author**: team lead

---

## Insights and New Perspectives

**Implementation as the definitive design validator**: Plans 1-7.5 implemented
the full daemon foundation (93 source files, 861 tests, 95.54% kcov coverage)
directly from the v1.0-r8 specs. This implementation cycle served as the most
thorough owner review possible — every spec claim was tested against real code.
The result: 17 ADRs (00048-00064) recording design decisions that emerged from
implementation, and 9 CTRs requesting spec updates where implementation revealed
gaps or better approaches.

**Static allocation transforms the type system**: ADR 00052 (static
SessionManager) and ADR 00058 (fixed-size inline buffers) had cascading effects
far beyond memory strategy. Session fields changed from `[]const u8` slices to
`[N]u8` + `_length` pairs. SessionManager changed from HashMap to fixed array.
This eliminated allocator dependencies from all core types, enabled file-scope
`.bss` allocation (4.5 MB), and simplified test isolation (reset instead of
deinit). The spec's original slice-based types were a pre-implementation guess
that did not survive contact with Zig's memory model.

**Protocol/transport separation was inevitable**: ADR 00060 split
libitshell3-protocol into two modules: libitshell3-protocol (codec, framing,
wire format) and libitshell3-transport (SocketConnection, Listener, connect).
The connection state machine and sequence tracking moved to the daemon library.
This eliminated the polymorphic vtable and clarified that transport is an OS
concern while protocol is a serialization concern. The v1.0-r8 spec's "transport
layer" sections in integration-boundaries need restructuring.

**Fixed-point arithmetic eliminates floating-point drift**: ADR 00062
(fixed-point resize ratio) and ADR 00063 (text zoom as WindowResize) resolved a
class of problems around pane resize. The wire format uses signed fixed-point
percentage (x10^4), and the internal split tree ratio changed from `f32` to
`u32`. This makes resize operations deterministic across client/daemon and
eliminates accumulating floating-point errors in deeply nested split trees.

**Message dispatcher decomposition scales with message types**: ADR 00064
(category-based dispatcher) restructured the monolithic switch into two-level
dispatch by protocol message type ranges (0x00xx-0x05xx). This emerged from Plan
7 adding 17 session/pane handlers — a single file became unmaintainable. The
pattern is extensible: Plans 8-9 add input/render/IME handlers into pre-created
stub dispatchers.

**ghostty API gaps are concrete, not theoretical**: Resolution 11 identified 6
API gaps; implementation confirmed and addressed them. `overlayPreedit()` was
written from scratch (~20 lines). `render_export.zig` was ported from PoC.
HID-to-Key comptime mapping table (256 entries) was built. Mouse encoding
remains daemon-authored (review note: `mouse-encode-api-gap.md`). The vendor pin
to v1.3.1-patch with `-Dversion-string` bypass is stable but fragile.

**MessageReader tiered buffer solves the 16 MiB problem**: ADR 00061 introduced
a two-tier strategy — 64 KB fixed internal buffer for common messages, plus a
daemon-global LargeChunkPool for the rare messages exceeding 64 KB. The first 16
MiB chunk lives in `.bss` (zero allocation for single large messages).
Concurrent large messages allocate dynamic chunks. This was not anticipated in
the v1.0-r8 spec's MessageReader description.

## Design Philosophy

**Code is the implementation authority; spec is the constraint authority**: The
v1.0-r8 specs define invariants, ordering constraints, and behavioral contracts.
Implementation details (exact data structures, buffer strategies, dispatch
patterns) live in code. ADRs bridge the gap — they record WHY a particular
implementation choice was made when the spec was ambiguous or when the spec's
original suggestion was impractical. The v1.0-r9 specs should absorb ADR
decisions as normative constraints where they affect observable behavior, and
leave implementation-only decisions in ADRs.

**Daemon binary is thin; libraries own domain logic**: ADR 00048 established the
three-layer model: daemon binary (~100 lines, CLI + signal + LaunchAgent),
libitshell3 (domain logic + event loop), libitshell3-protocol/transport (wire
format + socket). No C API on the daemon side (ADR 00050). This is a strong
constraint — the daemon binary must not accumulate domain logic.

**Per-instance directory enables future workspace support**: ADR 00054 changed
socket layout from flat files to per-instance subdirectories
(`<server_id>/daemon.sock` + `debug.sock` + `daemon.pid`). This is forward-
looking but the immediate motivation was the debug subsystem (ADR 00053) needing
a second socket alongside the protocol socket.

## Owner Priorities

- **Spec-code consistency is the primary goal of v1.0-r9**: 9 CTRs and 17 ADRs
  accumulated during implementation. The specs lag behind the code. v1.0-r9's
  purpose is to bring specs up to date with implemented reality, not to design
  new features.
- **v1.0-r9 is part of a unified 4-topic cycle**: daemon-architecture,
  daemon-behavior, server-client-protocols (v1.0-r13), and IME
  interface-contract (v1.0-r11) are being revised simultaneously in Plan 15.
  Cross-module consistency between all 4 topics is critical — ADRs like 00059
  (CapsLock/NumLock) and 00054 (socket directory) span multiple topics.
- **Implementation TODO markers are the deferred-work inventory**: Every
  `TODO(Plan N)` in the codebase marks a spec-described feature not yet
  implemented. Plans 8-10 are the immediate consumers. The spec should not be
  weakened to match incomplete implementation — it should remain the target.

## New Conventions and Procedures

- **ADR convention doc updated**: Anti-pattern guide added to
  `docs/conventions/artifacts/documents/10-adr.md` during protocol owner review.
  Revision-cycle ADRs are always Accepted status (SIP-05 from v1.0-r7).
- **Convention compliance is structural** (L10): Metadata conventions
  (Date/Scope only in headers) and cross-doc reference rules (no exact paths to
  independent revision cycles) are enforced as part of review, not optional
  polish.
- **SIP-01 from v1.0-r8 retrospective**: Dismissed Issues Registry should
  include "Settled Principles" section documenting the WHY behind dismissals,
  preventing topically identical re-raises across verification rounds.

## Pre-Discussion Research Tasks

### CTRs to resolve (9 total)

**daemon-architecture (6 CTRs):**

1. `01-daemon-per-instance-socket-directory.md` — Restructure socket layout to
   per-instance directories (ADR 00053, 00054). Affects 03-integration-
   boundaries startup/shutdown, 01-module-structure event sources.
2. `02-daemon-fixed-size-session-fields.md` — Convert Session fields to
   fixed-size inline buffers (ADR 00052, 00058). Major rewrite of
   impl-constraints/state-and-types and 02-state-and-types.
3. `03-impl-transport-connection-rename.md` — Rename Connection to
   SocketConnection (ADR 00060). Affects 03-integration-boundaries type names.
4. `04-impl-remove-sendv-result.md` — Eliminate duplicate SendvResult type.
   Minor edit to 03-integration-boundaries.
5. `05-impl-message-reader-tiered-buffer.md` — Add LargeChunkPool, update
   MessageReader description (ADR 00061). Affects 03-integration-boundaries and
   02-state-and-types.
6. `06-impl-fixed-point-split-ratio.md` — Change SplitNodeData ratio from f32 to
   u32 fixed-point (ADR 00062, 00063). Affects 02-state-and-types and
   impl-constraints.

**daemon-behavior (3 CTRs):**

1. `01-impl-static-allocation-connection-limit.md` — Revise connection limit
   invariant for static allocation (ADR 00052). Affects 03-policies-and-
   procedures Section 1.
2. `02-impl-operating-to-operating-transition.md` — Remove contradicting
   OPERATING to OPERATING transition row (ADR 00020). Affects
   03-policies-and-procedures state transitions table.
3. `03-impl-fixed-point-resize-handling.md` — Update resize procedure for signed
   fixed-point ratio delta (ADR 00062). Affects 03-policies-and- procedures
   resize handling.

### ADRs to absorb (beyond CTR-referenced ones)

These ADRs affect daemon specs but have no dedicated CTR. The v1.0-r9 team must
audit each and determine whether spec changes are needed:

- ADR 00048: Daemon binary vs library responsibility (affects
  01-module-structure layer boundaries)
- ADR 00049: LaunchAgent user domain (affects 01-daemon-lifecycle startup)
- ADR 00050: No daemon-side C API (affects 03-integration-boundaries)
- ADR 00051: Eager per-session IME deactivation (affects 02-event-handling,
  03-policies-and-procedures)
- ADR 00055: Ring cursor lag formula (affects 02-event-handling, 03-policies)
- ADR 00056: FrameEntry prose concept (affects 02-state-and-types,
  02-event-handling)
- ADR 00057: I-frame timer reset on any I-frame (affects 02-event-handling)
- ADR 00059: CapsLock/NumLock in KeyEvent (affects 02-state-and-types)
- ADR 00064: Category-based message dispatcher (affects 01-module-structure)

### Unresolved items carried forward

- **Mouse encoding API gap**: Daemon must author its own mouse encoder (review
  note: `mouse-encode-api-gap.md`). ghostty's mouse encoding is coupled to
  Surface, unavailable in headless mode. Spec section 4.5 (now in
  03-integration-boundaries) needs updating.
- **Resolution 9 implementation gaps**: 8 items identified during v1.0-r8
  discussion (ring buffer concrete values, default session parameters, health
  escalation anchor, coalescing/keyframe timer interaction, ExportResult buffer
  reuse, alternate screen detection, navigation geometry caching, FlatCell LE
  constraint). Most were resolved during implementation; the team should audit
  which remain relevant.
- **Verification Round 1-2 secondary findings**: Some minor issues from v1.0-r8
  verification (terminology inconsistencies, flag casing) may still be present
  if they were not in the fix scope. Audit during writing.

### Implementation state for reference

- 93 source files across 6 directories (core, ghostty, input, server, testing,
  root)
- 861 tests, 95.54% kcov coverage
- Key deferred work: Plan 8 (input pipeline, IME wire messages), Plan 9 (frame
  delivery, shell spawning), Plan 10 (cascades, shutdown)
- All deferred items marked with `TODO(Plan N)` comments in source
