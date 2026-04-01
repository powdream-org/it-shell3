# Design Resolution 01: Plan 15 Unified Revision Cycle

- **Version**: daemon-architecture v1.0-r9, daemon-behavior v1.0-r9,
  server-client-protocols v1.0-r13, IME interface-contract v1.0-r11
- **Date**: 2026-03-31
- **Status**: Resolved (9/9 unanimous consensus on all items)
- **Participants**: daemon-architect, ghostty-integration-engineer,
  protocol-architect, protocol-system-sw-engineer, cjk-specialist, ime-expert,
  ime-sw-architect, ime-system-sw-engineer, principal-architect
- **Sources**: 16 CTRs (daemon-arch 6, daemon-behavior 3, protocol 6, IME 1), 4
  deferred review notes (RN-01, RN-02, RN-03, RN-05), handovers (daemon r8→r9,
  protocol r12→r13, IME r10→r11), ADRs 00003, 00004, 00015, 00020, 00035, 00043,
  00048-00064
- **Scope**: daemon-architecture (3 docs), daemon-behavior (3 docs),
  server-client-protocols (7 docs), IME interface-contract (6 docs)

---

## Table of Contents

1. [Daemon-Architecture CTR Resolutions (6)](#1-daemon-architecture-ctr-resolutions)
2. [Daemon-Behavior CTR Resolutions (3)](#2-daemon-behavior-ctr-resolutions)
3. [Protocol CTR Resolutions (6)](#3-protocol-ctr-resolutions)
4. [IME CTR Resolution (1)](#4-ime-ctr-resolution)
5. [Deferred Review Note Resolutions (4)](#5-deferred-review-note-resolutions)
6. [Non-CTR Spec Corrections (5)](#6-non-ctr-spec-corrections)
7. [Owner Decisions](#7-owner-decisions)
8. [Wire Protocol Changes Summary](#8-wire-protocol-changes-summary)
9. [Cross-Module Consistency Matrix](#9-cross-module-consistency-matrix)
10. [Spec Documents Requiring Changes](#10-spec-documents-requiring-changes)

---

## 1. Daemon-Architecture CTR Resolutions

### Resolution 1: Per-Instance Socket Directory (CTR-01, ADR 00053 + 00054)

**Consensus**: 9/9 **Source**: daemon-arch CTR-01

**Decision**: Restructure socket layout from flat files to per-instance
directories. Path changes from `<server-id>.sock` to `<server-id>/daemon.sock`.

### Rationale

ADR 00053 (debug subsystem) requires a second socket per instance. ADR 00054
establishes the per-instance directory pattern to accommodate multiple
per-instance resources without ad-hoc naming conventions.

### Affected locations

1. **daemon-arch `03-integration-boundaries.md` Section 1.5.1** — Socket path
   format: update 4-step fallback algorithm to resolve to
   `<server-id>/daemon.sock`.
2. **daemon-arch `03-integration-boundaries.md` Section 1.5.2** — Listener
   lifecycle: `Listener.init()` creates per-instance directory before binding.
   `Listener.deinit()` cleans up `daemon.sock`, `debug.sock`, `daemon.pid`, and
   removes directory if empty.
3. **daemon-arch `03-integration-boundaries.md` Section 1.5.5** — Stale
   detection: probe `<server-id>/daemon.sock` + verify PID in `daemon.pid`.
4. **daemon-arch `01-module-structure.md` Section 2.2** — Event loop sources:
   add debug socket listener (EVFILT_READ, udata=99).
5. **daemon-arch `02-state-and-types.md`** — Update socket path references to
   per-instance format.
6. **protocol `01-protocol-overview.md` Section 2.1** — Socket path format,
   Mermaid flowchart, `$ITSHELL3_SOCKET` clarification (points to `daemon.sock`
   file, not instance directory). Informational note about `debug.sock` and
   `daemon.pid` in same directory.

**Caveat**: Document 104-byte `sockaddr_un.sun_path` macOS limit as a
constraint.

---

### Resolution 2: Fixed-Size Session Fields (CTR-02, ADR 00052 + 00058)

**Consensus**: 9/9 **Source**: daemon-arch CTR-02

**Decision**: Convert Session string fields from `[]const u8` slices to `[N]u8`

- `_length` inline buffers. Convert SessionManager from HashMap to fixed-size
  array. Fold `impl-constraints/state-and-types.md` normative content into
  `02-state-and-types.md` Section 1.3 and delete the transient artifact.

### Rationale

ADR 00052 (static SessionManager allocation) determines WHERE structs live
(.bss). ADR 00058 (fixed-size inline buffers) determines HOW string fields are
stored within them (inline, not heap-pointed). Together they eliminate allocator
dependency, lifetime management, and allocation failure from all core types.

### Affected locations

1. **daemon-arch `02-state-and-types.md` Section 1.2** — Session struct: all
   string fields become `[N]u8` + `_length` pairs. Field naming fixes:
   `keyboard_layout` -> `active_keyboard_layout`, default `"us"` -> `"qwerty"`.
2. **daemon-arch `02-state-and-types.md` Section 1.3** — Absorb MAX_SIZE
   constants table from impl-constraints:

   | Constant                   | Value | Rationale                              |
   | -------------------------- | ----- | -------------------------------------- |
   | `MAX_SESSION_NAME`         | 64    | Session name for display               |
   | `MAX_INPUT_METHOD_NAME`    | 32    | Identifier (`"korean_2set"`)           |
   | `MAX_KEYBOARD_LAYOUT_NAME` | 32    | Identifier (`"qwerty"`)                |
   | `MAX_PREEDIT_BUF`          | 64    | UTF-8 preedit overlay                  |
   | `MAX_PANE_TITLE`           | 256   | Terminal title (OSC 0/2)               |
   | `MAX_SESSIONS`             | 64    | Static array capacity (ADR 00052)      |
   | `MAX_PANE_CWD`             | 4096  | Current working directory (`PATH_MAX`) |

3. **daemon-arch `01-module-structure.md` Section 1.5** — SessionManager:
   HashMap -> `[MAX_SESSIONS]?SessionEntry` fixed-size array. Linear scan for
   lookup.
4. **daemon-behavior `03-policies-and-procedures.md`** — New overflow policy
   section: REJECT with `ERR_FIELD_TOO_LONG` for client-originated fields
   (session name); TRUNCATE at UTF-8 boundary for OSC-originated fields (pane
   title, cwd). Daemon-internal constants (input_method, keyboard_layout,
   preedit_buf) cannot overflow at runtime from predetermined identifiers.
5. **`impl-constraints/state-and-types.md`** — DELETE. Normative content folded
   into `02-state-and-types.md`. Transient artifact lifecycle clause satisfied
   (types now exist in code). The v1.0-r9 directory will have no
   `impl-constraints/` subdirectory.

---

### Resolution 3: Transport Connection Rename (CTR-03, ADR 00060)

**Consensus**: 9/9 **Source**: daemon-arch CTR-03

**Decision**: Rename `transport.Connection` to `transport.SocketConnection`
throughout the spec. Update ClientState to show layered ownership model.

### Rationale

ADR 00060 split libitshell3-protocol into protocol (codec/framing) and
libitshell3-transport (socket lifecycle). The rename clarifies that
`SocketConnection` is a concrete Unix socket implementation, not a polymorphic
abstraction.

### Affected locations

1. **daemon-arch `03-integration-boundaries.md` Section 1.5.3** — Type name:
   `Connection` -> `SocketConnection`.
2. **daemon-arch `03-integration-boundaries.md` Section 1.9** — Naming
   convention text: update type reference.
3. **daemon-arch `03-integration-boundaries.md` Section 6.2** — ClientState:
   replace `conn: transport.Connection` with
   `connection_state: server.ConnectionState`. Add brief ownership chain
   description: ClientState -> ConnectionState -> SocketConnection.
4. **daemon-arch `03-integration-boundaries.md` Section 8** — Text and Mermaid
   diagram: rename all `transport.Connection` references.

---

### Resolution 4: Remove SendvResult (CTR-04)

**Consensus**: 9/9 **Source**: daemon-arch CTR-04

**Decision**: Eliminate `SendvResult` type. `sendv()` returns `SendResult`.

### Rationale

`SendvResult` and `SendResult` are structurally identical (both wrap
`posix.WriteError`). A separate type adds no type safety and creates unnecessary
duplication.

### Affected locations

1. **daemon-arch `03-integration-boundaries.md` Section 1.5.3** — Remove
   `SendvResult` mention. Update `sendv()` signature to return `SendResult`.

---

### Resolution 5: MessageReader Tiered Buffer (CTR-05, ADR 00061)

**Consensus**: 9/9 **Source**: daemon-arch CTR-05

**Decision**: Update MessageReader description to document tiered buffer
strategy. Add LargeChunkPool as a daemon resource in a new memory resources
subsection.

### Rationale

ADR 00061 redesigned MessageReader from a 4 KB fixed buffer to a tiered
strategy: 64 KB internal fixed buffer for common messages, with overflow to a
daemon-global LargeChunkPool for rare large payloads.

### Affected locations

1. **daemon-arch `03-integration-boundaries.md` Section 1.3** — Update
   MessageReader description: 64 KB internal buffer + LargeChunkPool overflow
   for messages exceeding 64 KB.
2. **daemon-arch `03-integration-boundaries.md` Section 6.2** — ClientState: add
   note that MessageReader requires LargeChunkPool reference.
3. **daemon-arch `03-integration-boundaries.md`** — New daemon memory resources
   subsection (NOT in Section 4 Ring Buffer): LargeChunkPool description —
   daemon-global pool of 16 MiB chunks, first chunk in .bss, single-threaded.

---

### Resolution 6: Fixed-Point Split Ratio (CTR-06, ADR 00062 + 00063)

**Consensus**: 9/9 **Source**: daemon-arch CTR-06

**Decision**: Change `SplitNodeData.ratio` from `f32` to `u32` fixed-point
(x10^4, range 0-10000, where 5000 = 50.00%). Add cell grid model normative note.
JSON layout tree representation uses integer (`"ratio": 5000`), not float
(`"ratio": 0.5`).

### Rationale

ADR 00062 eliminates floating-point drift in deeply nested split trees. Integer
arithmetic (`width * ratio / 10000`) is deterministic across client/daemon. ADR
00063 establishes the cell grid model (border = 0 cells). Integer JSON
representation avoids IEEE 754 ambiguity at the serialization boundary.

### Affected locations

1. **daemon-arch `02-state-and-types.md`** — SplitNodeData `ratio`: `f32` ->
   `u32` fixed-point (x10^4). Update `computeLeafRects()` pseudocode to integer
   arithmetic. Add cell grid model normative note per ADR 00063.
2. **daemon-arch `02-state-and-types.md` (impl-constraints section, before
   deletion)** — Same ratio type change.
3. **protocol `03-session-pane-management.md` Section 3.2** — Layout tree wire
   format: split ratio uses fixed-point u32 (x10^4). JSON examples use integer
   representation.
4. **Resize clamping**: MIN_RATIO = 500 (5%) prevents zero-size panes.

---

## 2. Daemon-Behavior CTR Resolutions

### Resolution 7: Static Allocation Connection Limit (Behavior CTR-01, ADR 00052)

**Consensus**: 9/9 **Source**: daemon-behavior CTR-01

**Decision**: Remove "MUST NOT impose protocol-level connection limit"
invariant. Replace with compile-time capacity model using `MAX_CLIENTS` fixed
array. MAX_CLIENTS = 64 (owner decision). Keep RLIMIT_NOFILE guidance as SHOULD.

### Rationale

ADR 00052 established static allocation. A fixed-size array IS a protocol-level
connection limit. The old invariant is incompatible with the implemented memory
model. MAX_CLIENTS = 64 costs ~4 MB in .bss; raising to 256 would cost ~16 MB,
excessive for a terminal multiplexer.

### Affected locations

1. **daemon-behavior `03-policies-and-procedures.md` Section 1** — Replace
   invariant. State MAX_CLIENTS = 64 as the compile-time capacity.
2. **daemon-behavior `03-policies-and-procedures.md` Section 1** — Rejection
   behavior: accept(), send `ERR_RESOURCE_EXHAUSTED`, then close.
3. **daemon-behavior `03-policies-and-procedures.md` Section 1** — Resource
   budget note: `MAX_SESSIONS` and `MAX_CLIENTS` constrain deployment ceiling
   independently of fd availability.

---

### Resolution 8: Remove OPERATING->OPERATING Transition (Behavior CTR-02, ADR 00020)

**Consensus**: 9/9 **Source**: daemon-behavior CTR-02

**Decision**: Remove the contradicting OPERATING -> OPERATING transition row
from the client state transitions table. AttachSessionRequest while already
attached returns `ERR_SESSION_ALREADY_ATTACHED`. Client must explicitly
DetachSessionRequest first.

### Rationale

ADR 00020 establishes the explicit detach/attach round-trip model. The
contradicting row implied implicit detach-then-attach, which was explicitly
rejected.

### Affected locations

1. **daemon-behavior `03-policies-and-procedures.md`** — Remove or replace the
   contradicting row in client state transitions table. Show error response
   instead.
2. **daemon-arch `03-integration-boundaries.md` Section 6.1** — Mermaid state
   diagram: remove the
   `OPERATING --> OPERATING : AttachSessionRequest (different session)` arrow
   entirely. An error response with no state change is not a state transition
   and should not appear as a diagram arrow. Document the error behavior
   (`ERR_SESSION_ALREADY_ATTACHED`) in a note below the diagram.

---

### Resolution 9: Fixed-Point Resize Handling (Behavior CTR-03, ADR 00062)

**Consensus**: 9/9 **Source**: daemon-behavior CTR-03

**Decision**: Update resize handling procedure to use signed fixed-point ratio
delta with integer arithmetic.

### Rationale

ADR 00062 changes ResizePaneRequest from cell deltas to signed fixed-point ratio
deltas. The daemon no longer needs window dimensions to process resize requests.

### Affected locations

1. **daemon-behavior `03-policies-and-procedures.md`** — Resize procedure:
   1. Receive ResizePaneRequest with `orientation` + `delta_ratio` (i32, x10^4)
   2. Find nearest ancestor split node matching `orientation`
   3. Compute `new_ratio = old_ratio + delta_ratio`
   4. Clamp to `[MIN_RATIO, 10000 - MIN_RATIO]` where MIN_RATIO = 500 (5%)
   5. Store `new_ratio` in SplitNodeData
   6. Recompute affected pane rectangles with integer arithmetic
   7. Issue TIOCSWINSZ to affected PTYs (debounced per existing policy)

---

## 3. Protocol CTR Resolutions

### Resolution 10: Per-Instance Socket Directory (Protocol CTR-01, ADR 00054)

**Consensus**: 9/9 **Source**: protocol CTR-01

**Decision**: Update protocol spec socket path format to match daemon-arch
Resolution 1.

### Affected locations

1. **protocol `01-protocol-overview.md` Section 2.1** — Path format: table row,
   Mermaid flowchart, all examples update from `<server-id>.sock` to
   `<server-id>/daemon.sock`.
2. **protocol `01-protocol-overview.md`** — `$ITSHELL3_SOCKET` override: points
   to `daemon.sock` file specifically, not instance directory.
3. **protocol `01-protocol-overview.md`** — Informational note: `debug.sock` and
   `daemon.pid` exist in same directory (not part of client protocol).

---

### Resolution 11: Wire-Level Field Length Validation (Protocol CTR-02, ADR 00058)

**Consensus**: 9/9 **Source**: protocol CTR-02

**Decision**: Add byte-length constraints to protocol message definitions.
REJECT client-originated fields exceeding limits with `ERR_FIELD_TOO_LONG`.
TRUNCATE OSC-originated fields at UTF-8 boundary.

### Rationale

ADR 00058 introduces fixed-size buffers. The protocol must document limits so
client implementors know what the daemon will accept. Validate at system
boundary (client -> daemon); internal boundaries (PTY -> daemon state) use
truncation because the daemon cannot reject shell output.

### Affected locations

1. **protocol `03-session-pane-management.md`** — Add byte-length constraints:
   - CreateSessionRequest (0x0100) `name`: max 64 bytes UTF-8
   - RenameSessionRequest (0x010A) `name`: max 64 bytes UTF-8
   - AttachSessionRequest (0x0104) `session_name`: max 64 bytes UTF-8 (after
     RN-01 merge)
   - PaneMetadataChanged (0x0181) `title`: max 256 bytes, `cwd`: max 4096 bytes
2. **protocol `03-session-pane-management.md`** — Overflow behavior: REJECT with
   `ERR_FIELD_TOO_LONG` for client-originated; TRUNCATE at UTF-8 boundary for
   OSC-originated.
3. **protocol `03-session-pane-management.md` Section 6** — Add
   `ERR_FIELD_TOO_LONG` error code.

---

### Resolution 12: MAX_TREE_DEPTH Correction (Protocol CTR-03)

**Consensus**: 9/9 **Source**: protocol CTR-03

**Decision**: Fix MAX_TREE_DEPTH from 16 to 4.

### Rationale

A complete binary tree with 16 leaves (MAX_PANES = 16) has depth 4. The value 16
in the original text confused pane count with tree depth.

### Affected locations

1. **protocol `03-session-pane-management.md` Section 3.4** — Replace "maximum
   tree depth of 16 levels" with "maximum tree depth of 4 levels
   (`MAX_TREE_DEPTH = 4`), derived from the 16-pane limit (`MAX_PANES = 16`) in
   a binary split tree."

---

### Resolution 13: Preedit session_id Scope (Protocol CTR-04)

**Consensus**: 9/9 **Source**: protocol CTR-04

**Decision**: Correct preedit_session_id scope from "per pane" to "per session."

### Rationale

PreeditState is stored on the Session struct, not on Pane. The preedit
exclusivity invariant (at most one active composition per session) makes
per-pane counters redundant.

### Affected locations

1. **protocol `05-cjk-preedit-protocol.md` Section 2.1** — Replace "a
   monotonically increasing counter per pane" with "a monotonically increasing
   counter per session. It disambiguates sequential composition sessions across
   all panes within the session. The preedit exclusivity invariant (Section 1.1)
   guarantees at most one active composition per session, so a single
   session-level counter suffices."

---

### Resolution 14: CapsLock/NumLock Wire Preservation (Protocol CTR-05, ADR 00059)

**Consensus**: 9/9 **Source**: protocol CTR-05

**Decision**: Add normative note to protocol spec framed as wire semantic
importance: "CapsLock (bit 4) and NumLock (bit 5) carry semantic information
required by native IME engines for character case resolution and numpad key
classification. These bits MUST NOT be treated as optional or ignorable by
receivers."

### Rationale

ADR 00059 establishes that the native IME engine needs CapsLock/NumLock from the
wire modifier byte. The note is framed as wire semantics (what the bits mean),
not implementation routing guidance (how the daemon handles them). This is the
correct scope for a protocol spec.

### Affected locations

1. **protocol `04-input-and-renderstate.md`** — Add normative note after
   modifier byte table (around line 74).

---

### Resolution 15: Fixed-Point Resize Ratio (Protocol CTR-06, ADR 00062)

**Consensus**: 9/9 **Source**: protocol CTR-06

**Decision**: Replace ResizePaneRequest wire format. Direction (4-enum) + delta
(cells) becomes orientation (u8: 0=horizontal, 1=vertical) + delta_ratio (i32:
signed fixed-point x10^4). Layout tree split ratio also moves to fixed-point u32
for consistency.

### Rationale

ADR 00062 eliminates the circular dependency on window dimensions for resize
processing. The client computes the ratio delta directly; the daemon applies
integer arithmetic.

### Affected locations

1. **protocol `03-session-pane-management.md` Section 2.12** —
   ResizePaneRequest: replace `direction` + `delta` with `orientation` +
   `delta_ratio`.
2. **protocol `03-session-pane-management.md` Section 2.13** —
   ResizePaneResponse: status code 2 changes from "no split in that direction"
   to "no split in that orientation."
3. **protocol `03-session-pane-management.md` Section 3.2** — Layout tree: split
   ratio uses fixed-point u32 (x10^4). JSON examples use integer representation
   (`"ratio": 5000`).

---

## 4. IME CTR Resolution

### Resolution 16: CapsLock/NumLock in KeyEvent.Modifiers (IME CTR-01, ADR 00059)

**Consensus**: 9/9 (all IME team members + daemon-architect + principal-
architect) **Source**: IME CTR-01

**Decision**: Add `caps_lock` and `num_lock` boolean fields to
`KeyEvent.Modifiers` packed struct. Confirm `hasCompositionBreakingModifier()`
exclusion. Add design note for NumLock/numpad behavior.

### Rationale

ADR 00059 establishes that the native IME engine needs CapsLock for
direct/English mode character case resolution, and NumLock for numpad key
classification. Unlike OS IME systems where macOS resolves CapsLock into text
before delivery, it-shell3's daemon-side IME engine processes raw HID keycodes.

### Sub-decisions

**16a. Modifiers packed struct change:**

```zig
// Before
Modifiers = packed struct(u8) { ctrl, alt, super_key, _padding: u5 }

// After
Modifiers = packed struct(u8) { ctrl, alt, super_key, caps_lock, num_lock, _padding: u3 }
```

Wire-compatible: bits 3-4 were previously padding (always zero), now carry data.
Wire bits 4-5 map to Modifiers bits 3-4 after Shift stripping (wire bit 0
extracted to `KeyEvent.shift`, remaining bits 1-5 right-shifted by 1).

**16b. hasCompositionBreakingModifier() excludes CapsLock/NumLock:**

CapsLock and NumLock are "input classification" modifiers that affect key
identity (letter case, numpad function) but do NOT interrupt Hangul composition.
The method continues checking only ctrl, alt, super_key.

**16c. isPrintablePosition() stays static — NumLock routing is
engine-internal:**

`isPrintablePosition()` remains a pure physical-position HID keycode range check
with no modifier parameter. Numpad keys (HID 0x54-0x63) are outside the
printable range. The daemon sends ALL keycodes within HID_KEYCODE_MAX to
`processKey()`. The engine forwards numpad keys unconditionally via
`forward_key` — they never enter composition in any v1 input method. NumLock
state is preserved in Modifiers for wire losslessness but is not consumed by the
v1 engine.

### Affected locations (4 spec locations across 3 topics)

1. **IME `02-types.md`** — KeyEvent.Modifiers: add caps_lock, num_lock fields.
   Confirm hasCompositionBreakingModifier() exclusion. Add isPrintablePosition()
   design note for numpad keys.
2. **protocol `04-input-and-renderstate.md`** — Normative preservation note
   (Resolution 14 above).
3. **daemon-arch `03-integration-boundaries.md` Section 5.2** — Wire-to-KeyEvent
   Decomposition table: update bits 4-5 from "Not consumed by IME" to mapping to
   `KeyEvent.modifiers.caps_lock` and `.num_lock`. CapsLock serves dual purpose:
   Phase 0 language toggle detection + Phase 1 direct/English mode case
   resolution.
4. **daemon-arch `02-state-and-types.md` Section 1.3** — core/ type table:
   update KeyEvent.Modifiers to show 5 fields. Add
   `hasCompositionBreakingModifier()` invariant: "returns true for ctrl, alt,
   super_key; false for caps_lock, num_lock."

---

## 5. Deferred Review Note Resolutions

### Resolution 17: AttachOrCreate Merge (RN-01, ADR 00003)

**Consensus**: 9/9 (owner previously approved) **Source**: protocol review note
01

**Decision**: Merge `AttachOrCreateRequest` (0x010C) into `AttachSessionRequest`
(0x0104). Delete the 0x010C/0x010D message type pair.

### Rationale

Two messages with overlapping semantics create unnecessary protocol surface.
AttachOrCreate was missing `readonly` and `detach_others` fields present in
AttachSession — a field parity gap that forces multi-step workarounds.

### Affected locations

1. **protocol `03-session-pane-management.md`** — AttachSessionRequest (0x0104):
   add `session_name` (optional string), `create_if_missing` (optional bool,
   default false), `shell` (optional string), `cwd` (optional string). Add
   `action_taken` ("attached" | "created") to response. `session_name` field
   subject to max 64 byte constraint (Resolution 11).
2. **protocol `03-session-pane-management.md`** — Delete Sections 1.13-1.14
   (AttachOrCreate).
3. **protocol `01-protocol-overview.md`** — Remove 0x010C/0x010D from message
   type registry.
4. **protocol `02-handshake-and-session-lifecycle.md`** — Update handshake
   references mentioning AttachOrCreate.
5. **protocol `03-session-pane-management.md`** — Update readonly permissions
   (remove AttachOrCreate from lists).

---

### Resolution 18: Symmetric Clipboard Encoding (RN-02, ADR 00004)

**Consensus**: 9/9 (owner previously approved) **Source**: protocol review note
02

**Decision**: Add `encoding` field to `ClipboardWriteFromClient` (0x0604). Fix
OSC 52 procedure to pass through base64 without decoding.

### Rationale

ClipboardWrite (S->C) has an `encoding` field but ClipboardWriteFromClient
(C->S) does not. Binary clipboard content from the client cannot be represented.
The OSC 52 procedure incorrectly instructs the server to decode base64 before
sending, which corrupts non-UTF-8 content.

### Affected locations

1. **protocol `06-flow-control-and-auxiliary.md`** — ClipboardWriteFromClient
   (0x0604): add `encoding` field (same semantics: `"utf8"` or `"base64"`).
2. **protocol `06-flow-control-and-auxiliary.md` Section 3.3** — OSC 52
   procedure: replace "Decodes the base64 data" with "Passes through the base64
   string with `encoding: 'base64'`".

---

### Resolution 19: u64 Sequence Numbers (RN-03, ADR 00015)

**Consensus**: 9/9 (owner previously approved) **Source**: protocol review note
03

**Decision**: Change `sequence` field from u32 to u64. Header grows from 16 to
20 bytes. Version byte bumps from 1 to 2. ADR 00015 status updated from Proposed
to Accepted.

### Rationale

u32 wraps after ~49 days at 1000 messages/second. u64 eliminates the wrap
concern entirely. The 4-byte overhead per message is negligible at terminal
workloads. No existing client implementation to break.

### Header layout

```
Offset  Size  Field
------  ----  -----
 0       2    magic          0x49 0x54 ("IT")
 2       1    version        2
 3       1    flags          Frame flags
 4       2    msg_type       Little-endian u16
 6       2    reserved       Must be 0
 8       4    payload_len    Little-endian u32
12       8    sequence       Little-endian u64
```

Total: 20 bytes. Natural 8-byte alignment for sequence field. Reserved field
kept for alignment only — no semantic meaning or future-use documentation
assigned. "Must be 0" is sufficient.

### Affected locations

1. **protocol `01-protocol-overview.md` Section 3.1** — Header format: update
   field table, offset references, total size.
2. **protocol `01-protocol-overview.md` Section 3.4** — Sequence number
   semantics: u32 -> u64.
3. **protocol `01-protocol-overview.md` Section 3.1.1** — Version byte: bump to
   2 per ADR 00005.
4. **protocol `01-protocol-overview.md`** — Appendix hex dump: update example.
5. **All protocol docs** — Update all "16 bytes" header references to "20
   bytes".
6. **ADR 00015** — Update status from Proposed to Accepted.

---

### Resolution 20: Clipboard Size Limit (RN-05, ADR 00035)

**Consensus**: 9/9 (owner previously decided Option A) **Source**: protocol
review note 05

**Decision**: Hard 10 MiB limit on clipboard payload data. No chunked transfer
in v1. Reject with `payload_too_large` error.

### Rationale

10 MiB covers all practical clipboard use cases. The limit is a message-specific
constraint within the existing 16 MiB framing limit. No configurability needed
(YAGNI).

### Affected locations

1. **protocol `06-flow-control-and-auxiliary.md` Section 3** — Add normative
   note: "Clipboard payload data MUST NOT exceed 10 MiB. The receiver MUST
   reject payloads exceeding this limit with an error response
   (`payload_too_large`). This is a message-specific constraint within the 16
   MiB maximum payload size defined in the frame header."

---

## 6. Non-CTR Spec Corrections

### Correction 1: Mouse Encoding API Gap

**Source**: ghostty-integration-engineer, confirmed by daemon-architect

Daemon-architecture `03-integration-boundaries.md` incorrectly references
`mouse_encode.encode()` as a ghostty API in 5 locations (Sections 4.2, 4.4, 4.5,
mouse input correction paragraph, Mermaid diagrams). This function does NOT
exist in ghostty v1.3.1 — mouse encoding is coupled to Surface.zig and
unavailable headless.

**Resolution**: Mouse encoding is daemon-authored code placed at
`ghostty/mouse_encoder.zig`. It lives in the `ghostty/` module (not `input/`)
because it depends on `terminal.flags.mouse_format` (a ghostty-internal
`MouseFormat` enum). `input/` has a "No ghostty dependency" invariant that would
be violated. The `ghostty/` module already has precedent with `key_encoder.zig`
(daemon-authored code with ghostty type dependencies).

**Affected locations**:

1. Section 4.2 API Surface table: change to
   `ghostty/mouse_encoder.zig (daemon-authored)`.
2. Section 4.4 API Gap Status table: add row — status: "Must be written from
   scratch", reference Surface.zig:3670-3860.
3. Section 4.5 Helper Function table: label mouse row as "daemon-authored" to
   distinguish from ghostty API wrappers. Consider adding a "Type" column
   (wrapper vs daemon-authored).
4. Mouse input correction paragraph: replace `mouse_encode.encode()` with
   `ghostty/mouse_encoder.zig`.
5. Mermaid diagrams + mouse handler references: same rename.

---

### Correction 2: Wire-to-KeyEvent Decomposition Table (ADR 00059 cascade)

**Source**: ime-sw-architect + ime-system-sw-engineer (independently flagged)

Daemon-architecture `03-integration-boundaries.md` Section 5.2 wire-decompose
table says CapsLock (bit 4) and NumLock (bit 5) are "Not consumed by IME." This
contradicts ADR 00059.

**Resolution**: Update bit 4-5 rows:

| Wire Bit         | KeyEvent Field                 | Description                                                                                   |
| ---------------- | ------------------------------ | --------------------------------------------------------------------------------------------- |
| Bit 4 (CapsLock) | `KeyEvent.modifiers.caps_lock` | Dual purpose: Phase 0 language toggle detection + Phase 1 direct/English mode case resolution |
| Bit 5 (NumLock)  | `KeyEvent.modifiers.num_lock`  | Phase 1 numpad key classification: printable (NumLock on) vs navigation (NumLock off)         |

---

### Correction 3: Category-Based Message Dispatcher (ADR 00064)

**Source**: daemon-architect

ADR 00064 restructured the monolithic message dispatcher switch into two-level
dispatch by protocol message type ranges (0x00xx-0x05xx). This emerged from Plan
7 adding 17 session/pane handlers. No CTR exists but the structural change
should be documented.

**Resolution**: Add section to daemon-arch `01-module-structure.md` describing
the two-level dispatch pattern in server/. Message type range categories route
to category-specific dispatchers. Plans 8-9 add input/render/IME handlers into
pre-created stub dispatchers.

---

### Correction 4: Doc 05 Section Renumbering

**Source**: cjk-specialist

Protocol `05-cjk-preedit-protocol.md` has numbering gaps from deleted sections.

**Resolution**: Sequential renumbering:

| Current     | New         |
| ----------- | ----------- |
| Section 5.2 | Section 5.1 |
| Section 8   | Section 7   |
| Section 9   | Section 8   |
| Section 10  | Section 9   |
| Section 11  | Section 10  |
| Section 13  | Section 11  |

Internal cross-reference update: "Section 8.2" -> "Section 7.2".

---

### Correction 5: Doc 01 Section Renumbering

**Source**: protocol-architect

Protocol `01-protocol-overview.md` has numbering gaps from deleted sections.

**Resolution**: Sequential renumbering:

| Current    | New        |
| ---------- | ---------- |
| Section 9  | Section 8  |
| Section 10 | Section 9  |
| Section 12 | Section 10 |

Cross-doc reference updates:

1. Doc 02 line 879: "doc 01 Section 12.2" -> "doc 01 Section 10.2"
2. Doc 05 line 51: "doc 04, Section 2.8" -> "doc 03, Section 8" (pre-existing
   bug fix)
3. ADRs: none affected (audit complete)
4. CTRs: not updated (input artifacts with frozen references)

Two-pass approach: first pass renumbers sections, second pass greps entire docs/
tree for stale references.

---

### Additional: ADR 00060 Layer Architecture Restructuring

**Source**: protocol-system-sw-engineer, confirmed by daemon-architect

Daemon-architecture `03-integration-boundaries.md` Section 1, Section 1.1 (layer
diagram), Section 1.4 (Layer 3), and Section 3 (Shared Four-Layer Model) still
describe all four layers as part of "libitshell3-protocol." After ADR 00060, the
reality is three modules:

- **libitshell3-protocol**: Layers 1-2 (codec + framing)
- **libitshell3-transport**: Layer 4 (SocketConnection, Listener, connect)
- **libitshell3 server/connection/**: Layer 3 (ConnectionState, sequence
  tracking, capabilities)

**Resolution**: Separate edit pass from CTR-03 rename. Update Section 1 heading,
Section 1.1 layer diagram, Section 1.4 description (move to daemon Section 6 or
server/connection/), and Section 3 table to reflect three-module reality.

---

## 7. Owner Decisions

| Item              | Decision                         | Date       |
| ----------------- | -------------------------------- | ---------- |
| MAX_CLIENTS value | 64 (fixed value, not a minimum)  | 2026-03-31 |
| ADR 00015 status  | Accepted (updated from Proposed) | 2026-03-31 |

---

## 8. Wire Protocol Changes Summary

| Change                             | Impact                                                                                                                                                                             |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Socket path format                 | No wire format change. Path string changes only.                                                                                                                                   |
| Field length constraints           | No wire format change. Validation rules added.                                                                                                                                     |
| MAX_TREE_DEPTH correction          | No wire format change. Value fix in prose.                                                                                                                                         |
| preedit_session_id scope           | No wire format change. Scope description corrected.                                                                                                                                |
| CapsLock/NumLock preservation note | No wire format change. Normative note added.                                                                                                                                       |
| ResizePaneRequest fixed-point      | Wire format change: `direction` (u8 4-enum) + `delta` (i32 cells) -> `orientation` (u8 2-value) + `delta_ratio` (i32 signed fixed-point x10^4).                                    |
| Layout tree split ratio            | Wire format change: `ratio` changes from JSON float to JSON integer (u32, x10^4).                                                                                                  |
| AttachOrCreate merge               | Wire format change: 0x010C/0x010D deleted. AttachSessionRequest (0x0104) gains `session_name`, `create_if_missing`, `shell`, `cwd` optional fields. Response gains `action_taken`. |
| Clipboard encoding symmetry        | Wire format change: ClipboardWriteFromClient (0x0604) gains `encoding` field.                                                                                                      |
| u64 sequence numbers               | Wire format change: header grows from 16 to 20 bytes. `sequence` field u32 -> u64. Protocol version 1 -> 2.                                                                        |
| Clipboard size limit               | No wire format change. Validation limit added.                                                                                                                                     |
| ERR_FIELD_TOO_LONG                 | Wire format change: new error code added to Doc 03.                                                                                                                                |

---

## 9. Cross-Module Consistency Matrix

| Shared Concept               | Daemon-Arch   | Daemon-Behavior | Protocol | IME Contract |
| ---------------------------- | ------------- | --------------- | -------- | ------------ |
| Socket path format           | R1            | --              | R10      | --           |
| CapsLock/NumLock bits        | R16 (cascade) | --              | R14      | R16          |
| Fixed-point ratio (x10^4)    | R6            | R9              | R15      | --           |
| Field length limits          | R2            | R2 (overflow)   | R11      | --           |
| OPERATING->OPERATING removal | R8 (diagram)  | R8 (table)      | --       | --           |
| Static allocation limits     | R2            | R7              | --       | --           |
| AttachOrCreate merge         | --            | --              | R17      | --           |
| u64 sequence numbers         | --            | --              | R19      | --           |

All cross-module pairs are consistent. No unresolved conflicts.

---

## 10. Spec Documents Requiring Changes

| Document                                         | Resolutions                           | Change Type                                                                                                         |
| ------------------------------------------------ | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| daemon-arch `01-module-structure.md`             | R1, R2, C3                            | Event source, SessionManager, dispatcher                                                                            |
| daemon-arch `02-state-and-types.md`              | R2, R6, R16                           | Session fields, split ratio, KeyEvent.Modifiers, absorb impl-constraints                                            |
| daemon-arch `03-integration-boundaries.md`       | R1, R3, R4, R5, R8, C1, C2, ADR 00060 | Socket paths, rename, SendvResult, MessageReader, state diagram, mouse encoder, wire-decompose, layer restructuring |
| daemon-behavior `01-daemon-lifecycle.md`         | --                                    | No changes identified                                                                                               |
| daemon-behavior `02-event-handling.md`           | --                                    | No changes identified                                                                                               |
| daemon-behavior `03-policies-and-procedures.md`  | R2, R7, R8, R9                        | Overflow policy, connection limits, state transitions, resize procedure                                             |
| protocol `01-protocol-overview.md`               | R10, R17, R19, C5                     | Socket path, message registry, header format, section renumbering                                                   |
| protocol `02-handshake-and-session-lifecycle.md` | R17                                   | AttachOrCreate references                                                                                           |
| protocol `03-session-pane-management.md`         | R11, R12, R15, R17                    | Field constraints, tree depth, resize format, AttachOrCreate merge                                                  |
| protocol `04-input-and-renderstate.md`           | R14                                   | CapsLock/NumLock normative note                                                                                     |
| protocol `05-cjk-preedit-protocol.md`            | R13, C4                               | preedit_session_id scope, section renumbering                                                                       |
| protocol `06-flow-control-and-auxiliary.md`      | R18, R20                              | Clipboard encoding, size limit                                                                                      |
| IME `02-types.md`                                | R16                                   | KeyEvent.Modifiers fields, design notes                                                                             |
| `impl-constraints/state-and-types.md`            | R2                                    | DELETE (content folded into daemon-arch 02-state-and-types)                                                         |
| ADR 00015                                        | R19                                   | Status: Proposed -> Accepted                                                                                        |

## Deferred Items

None. All items resolved in this cycle.
