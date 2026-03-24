# Design Resolutions: Daemon v1.0-r8 Restructuring

- **Date**: 2026-03-24
- **Team**: daemon-architect, ghostty-integration-engineer,
  ime-system-sw-engineer, principal-architect, protocol-architect,
  system-sw-engineer (6 members)
- **Scope**: Split daemon/ topic into daemon-architecture/ and daemon-behavior/
  topics; define QA-focused behavior doc format; code structure proposal;
  implementation gap analysis; ghostty API gap analysis
- **Source**: `daemon/draft/v1.0-r7/handover/handover-to-r8.md`,
  `daemon/draft/v1.0-r6/handover/handover-to-r7.md` (preliminary section
  mapping), `docs/insights/ghostty-api-extensions.md`,
  `docs/insights/design-principles.md`

---

## Table of Contents

1. [Resolution 1: Owner Directive — Behavior Docs Are QA Test Specifications](#resolution-1-owner-directive--behavior-docs-are-qa-test-specifications)
2. [Resolution 2: Section-to-Topic Mapping](#resolution-2-section-to-topic-mapping)
3. [Resolution 3: Document Structure (3 + 3)](#resolution-3-document-structure-3--3)
4. [Resolution 4: Behavior Doc Format — Ordering Constraint Tables](#resolution-4-behavior-doc-format--ordering-constraint-tables)
5. [Resolution 5: Drop Design Decisions Log (doc04 §12)](#resolution-5-drop-design-decisions-log-doc04-12)
6. [Resolution 6: FlatCell = CellData Terminology Binding](#resolution-6-flatcell--celldata-terminology-binding)
7. [Resolution 7: Ring Buffer Placement — server/, Not core/](#resolution-7-ring-buffer-placement--server-not-core)
8. [Resolution 8: Code Structure — 4-Module Layout](#resolution-8-code-structure--4-module-layout)
9. [Resolution 9: Implementation Gaps](#resolution-9-implementation-gaps)
10. [Resolution 10: Carry-Forward Fixes from r7 Round 4](#resolution-10-carry-forward-fixes-from-r7-round-4)
11. [Resolution 11: ghostty API Gap Analysis](#resolution-11-ghostty-api-gap-analysis)
12. [Resolution 12: Response-Before-Notification Cross-Cutting Invariant](#resolution-12-response-before-notification-cross-cutting-invariant)

---

## Resolution 1: Owner Directive — Behavior Docs Are QA Test Specifications

**Consensus**: 6/6 unanimous

The owner directive shapes all subsequent resolutions. Behavior docs contain:

- Ordering constraint tables, state machine diagrams, observable effects with
  message ordering
- Invariants (MUST/MUST NOT), policy tables with concrete values, trigger
  conditions, edge case specifications

Behavior docs do NOT contain: step-by-step pseudocode, variable assignments,
if/else branching, function call sequences. These are replaced by code.

Architecture docs absorb: design rationale ("why this ordering"), resource
lifecycle explanations, module boundary justifications.

### Three-Pass Extraction Process

For each pseudocode section:

1. **Pass 1 — Extract ordering constraints → behavior doc**: Read each step pair
   (N, N+1) and ask "Is there an ordering dependency between these?" If yes, add
   a row to the ordering constraint table. Also check non-adjacent dependencies
   (e.g., step 4 depends on step 6's PTY fd still being open). If the ordering
   is only for implementation convenience (not correctness), skip it.
2. **Pass 2 — Extract design rationale → architecture doc**: Read each comment,
   "why" paragraph, and rationale block. If it explains a structural decision
   (why this module, why this type, why this dependency direction): move to
   architecture. If it explains a behavioral rule (why this ordering, why this
   timeout value): leave a rationale ref in the constraint table.
3. **Pass 3 — Strip pseudocode**: Remove the code blocks. Verify: every ordering
   constraint from Pass 1 appears in the constraint table. Verify: every design
   rationale from Pass 2 has a home in architecture docs. Verify: no _permanent_
   information was lost (steps are acceptable loss; ordering and rationale are
   not).

**Verification criterion**: After stripping, a QA engineer can write a test for
every wire-visible constraint using ONLY the behavior doc. An implementor can
understand WHY a constraint exists using the architecture doc reference. If
either fails, information was lost.

---

## Resolution 2: Section-to-Topic Mapping

**Consensus**: 6/6 unanimous

Complete section classification based on r7 doc structure.

### Architecture

| Section                                    | Classification                     | Notes                                                                                                                                                                                                                                                   |
| ------------------------------------------ | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| doc01 §1 Module Decomposition              | Architecture                       | Pure structural design                                                                                                                                                                                                                                  |
| doc01 §2 Event Loop Model                  | **SPLIT**                          | §2.1-§2.4, §2.6 (event loop decision, event sources, single-thread rationale, prior art, flow diagram) → architecture. §2.5 Input Processing Priority: decision that priority ordering exists → architecture; concrete 5-tier priority table → behavior |
| doc01 §3 State Tree                        | Architecture                       | Type definitions, Zig structs. §3.4 PTY Lifecycle stays as context (points to behavior doc03 as authoritative)                                                                                                                                          |
| doc01 §3.11 Pane Navigation                | Architecture (full algorithm spec) | Algorithm body stays until code exists, then becomes code reference                                                                                                                                                                                     |
| doc01 §4 ghostty Terminal Mgmt             | Architecture                       | API surface, headless decision                                                                                                                                                                                                                          |
| doc01 §5 End-to-End Data Flow              | Architecture                       | Data flow diagrams are structural                                                                                                                                                                                                                       |
| doc01 §6 Preedit/RenderState Validity      | Architecture                       | Design rationale                                                                                                                                                                                                                                        |
| doc01 §7 Ring Buffer Architecture          | Architecture                       | Structural design of the ring                                                                                                                                                                                                                           |
| doc02 §1-3 Protocol/Transport/Shared Model | Architecture                       | Integration boundary design                                                                                                                                                                                                                             |
| doc02 §4 IME Integration                   | **SPLIT**                          | Types/vtable/dependency diagram → architecture. Lifecycle table and "deactivate() then deinit()" contract → behavior                                                                                                                                    |
| doc02 §5 C API Surface                     | Architecture                       | API design                                                                                                                                                                                                                                              |
| doc02 §6 Deferred Items                    | Architecture                       | Future planning                                                                                                                                                                                                                                         |
| doc03 §4 Client Connection Lifecycle       | **SPLIT**                          | State machine diagram, ClientState struct, type definitions → architecture. State transition table (§4.2), timeout table (§4.7), negotiation algorithms (§4.8) → behavior                                                                               |
| doc03 §5 Ring Buffer Delivery Model        | Architecture                       | Delivery mechanism design                                                                                                                                                                                                                               |
| doc03 §7.1 Remote Version Conflict         | Architecture                       | Protocol boundary design for version negotiation                                                                                                                                                                                                        |
| doc03 §7.2+ SSH Fork+Exec                  | Architecture                       | Deferred to Phase 5                                                                                                                                                                                                                                     |
| doc03 §8 Transport-Agnostic Design         | Architecture                       | Design principle                                                                                                                                                                                                                                        |
| doc04 §12 Design Decisions Log             | **DROP** (see Resolution 5)        | Inline each entry where it constrains, then delete                                                                                                                                                                                                      |

### Behavior

| Section                             | Classification | Notes                                                              |
| ----------------------------------- | -------------- | ------------------------------------------------------------------ |
| doc03 §1 Daemon Startup             | Behavior       | 7-step sequence with ordering constraints                          |
| doc03 §2 Daemon Shutdown            | Behavior       | Ordered teardown                                                   |
| doc03 §3 Runtime Event Handling     | Behavior       | Pane exit cascade, SIGCHLD two-phase, client connection/disconnect |
| doc03 §6 LaunchAgent Integration    | Behavior       | Startup/shutdown procedures                                        |
| doc04 §1 Connection Limits          | Behavior       | Testable policy constraints                                        |
| doc04 §2 Multi-Client Resize        | Behavior       | Resize orchestration, debouncing, stale re-inclusion               |
| doc04 §3 Health Escalation          | Behavior       | State machine, timeouts                                            |
| doc04 §4 Flow Control               | Behavior       | Backpressure policies                                              |
| doc04 §5 Adaptive Coalescing        | Behavior       | Tier transitions, timing                                           |
| doc04 §6 Preedit Ownership          | Behavior       | Ownership rules, contention resolution                             |
| doc04 §7 Preedit Lifecycle          | Behavior       | State change lifecycle policies                                    |
| doc04 §8 Server Behavior Procedures | Behavior       | Pseudocode → constraint tables + observable effects                |
| doc04 §9 Notification Defaults      | Behavior       | Subscription model                                                 |
| doc04 §10 Heartbeat Policy          | Behavior       | Timeouts, escalation                                               |
| doc04 §11 Silence Detection Timer   | Behavior       | Timer lifecycle, cleanup triggers                                  |

---

## Resolution 3: Document Structure (3 + 3)

**Consensus**: 6/6 unanimous

`[ADR-CANDIDATE]` Two-topic split with 3 docs per topic.

### Architecture Topic — 3 Docs

1. **`01-module-structure.md`** — Module decomposition, event loop, dependency
   graph, prior art
2. **`02-state-and-types.md`** — State tree, type definitions (Session,
   SessionEntry, Pane, SplitNodeData, PreeditState), pane navigation algorithm,
   ring buffer architecture, data flow, preedit cache
3. **`03-integration-boundaries.md`** — Protocol library boundary (4-layer
   model), transport, IME integration (structural: vtable, dependency diagram,
   module placement), ghostty API surface (headless decision, API table, helper
   function rationale), C API surface, client state types (ClientState struct,
   state machine diagram), deferred items

### Behavior Topic — 3 Docs

1. **`01-daemon-lifecycle.md`** — Startup sequence, shutdown sequence,
   LaunchAgent integration
2. **`02-event-handling.md`** — SIGCHLD two-phase model, pane exit cascade,
   session destroy cascade, client connect/disconnect, runtime event handling.
   Includes cross-cutting invariants (see Resolution 12)
3. **`03-policies-and-procedures.md`** — Connection limits, resize policy,
   health escalation, flow control, adaptive coalescing, preedit ownership +
   lifecycle + procedures (transformed from pseudocode), notification defaults,
   heartbeat policy, silence detection timer, client state transitions,
   handshake timeouts, negotiation algorithms

---

## Resolution 4: Behavior Doc Format — Ordering Constraint Tables

**Consensus**: 6/6 unanimous

`[ADR-CANDIDATE]` QA-focused behavior doc format with 5-column constraint
tables.

Each behavior section uses this format:

1. **Trigger condition** — what initiates this behavior
2. **Preconditions** — required state
3. **Ordering constraint table** — 3 columns (wire-observable only):

| Column       | Description                                  |
| ------------ | -------------------------------------------- |
| #            | Sequential number within section (1, 2, ...) |
| Constraint   | "X MUST happen before Y"                     |
| Verification | Testable assertion for this constraint       |

**Wire-observable only**: Behavior docs contain ONLY constraints that a QA
engineer can verify by observing protocol messages on the wire. Internal
daemon-only ordering constraints (resource lifecycle, assertion-level ordering)
go to `impl-constraints/*.md` files (see below).

**No Visibility column**: Since all constraints in behavior docs are
wire-observable, the column is unnecessary.

**No Rationale ref column**: Creates cross-doc coupling that breaks on every
revision. Design rationale lives in architecture docs.

### Internal Constraints — Temporary `impl-constraints/` Directory

Internal ordering constraints (not wire-observable) are extracted to temporary
files during restructuring:

```
daemon-behavior/draft/v1.0-r8/impl-constraints/
  pane-exit-cascade.md
  session-destroy-cascade.md
  ime-procedures.md
  ...
```

These files:

- Are extracted from r7 pseudocode during the three-pass process (Pass 1)
- Serve as the implementer's reference for debug assertions (`std.debug.assert`)
- Are **deleted** when the implementation has the assertions in code
- Are NOT permanent documentation — they are transient artifacts

4. **State machine** (if applicable) — states, transitions, guards
5. **Observable effects** — wire messages in order, using "common prefix +
   conditional suffix" format for branches
6. **Invariants** — MUST/MUST NOT rules
7. **Policy values** — concrete numbers in a table

### Concrete Example: executePaneDestroyCascade

**Trigger**: Both `PANE_EXITED` and `PTY_EOF` flags are set on a pane
(order-independent).

**Preconditions**: Pane slot is valid, PTY fd is open, Terminal state exists.

**Ordering constraints** (wire-observable only):

| # | Constraint                                        | Verification                                                    |
| - | ------------------------------------------------- | --------------------------------------------------------------- |
| 1 | Pending frames flushed BEFORE PaneMetadataChanged | No PaneMetadataChanged in send queue while pane has dirty state |
| 2 | PreeditEnd BEFORE LayoutChanged                   | No LayoutChanged in send queue while preedit is active          |
| 3 | PaneMetadataChanged BEFORE LayoutChanged          | Exit status visible before pane disappears from layout          |
| 4 | LayoutChanged carries correct focus               | LayoutChanged.focused_pane_id != exited pane                    |

Internal ordering constraints (IME cleanup before PTY close, Terminal.deinit()
ordering, slot atomicity, EVFILT_SIGNAL priority) are extracted to
`impl-constraints/pane-exit-cascade.md` — see Resolution 4 above.

**Observable effects** (wire messages to attached clients, in order):

Common prefix:

1. FrameUpdate (final frame for dying pane) [if dirty]
2. PaneMetadataChanged(is_running=false, exit_status=N)
3. ProcessExited(exit_status=N) [if subscribed]
4. PreeditEnd(reason="pane_closed") [if focused pane with active composition]

Conditional suffix — non-last pane:

5a. LayoutChanged(new_focus=X, tree=updated)

Conditional suffix — last pane (session auto-destroy):

5b. SessionListChanged(event="destroyed", session_id=N)

**Invariants:**

- MUST NOT send LayoutChanged with stale focus
- MUST NOT leave pane slot in non-null state after cascade completes
- Preedit session_id MUST increment after PreeditEnd (except session-destruction
  paths)

**Conditional branches:**

- Non-focused pane: IME cleanup is skipped entirely
- Last pane in session: IME engine is _deactivated_ (not just reset), committed
  text written to PTY before close, then session auto-destroys

---

## Resolution 5: Drop Design Decisions Log (doc04 §12)

**Consensus**: 6/6 unanimous

doc04 §12 (Design Decisions Log) is a standalone section that restates rationale
already present in individual sections. Per design principle L9
("Summary/aggregation sections are divergence vectors"), it should be
decomposed: inline each entry at its constraining location in architecture docs,
then delete the standalone log. No information loss — each decision's rationale
moves to where it's used.

---

## Resolution 6: FlatCell = CellData Terminology Binding

**Consensus**: 6/6 unanimous

`[ADR-CANDIDATE]` CellData is the canonical wire-format name; FlatCell is
ghostty-internal only.

The architecture docs MUST use `CellData` (the protocol wire name) as the
canonical term. `FlatCell` (the ghostty-internal name) is used only in
`ghostty/` module code and comments. The convergence point: `bulkExport()`
produces FlatCell internally; the export boundary maps FlatCell → CellData for
wire serialization. Both are `extern struct` with identical layout on v1 targets
(all little-endian).

The LE constraint MUST be explicitly noted at the convergence point for future
portability awareness. The protocol spec defines CellData as little-endian
explicit; FlatCell is `extern struct` (C ABI). On v1 targets (all LE), these are
identical.

---

## Resolution 7: Ring Buffer Placement — server/, Not core/

**Consensus**: 6/6 unanimous

`[ADR-CANDIDATE]` Ring buffer lives in `server/`, not `core/`.

Three arguments:

1. Ring buffer depends on serialized wire-format frames (libitshell3-protocol
   types) — `core/` has no protocol dependency
2. Ring buffer manages per-client cursors (server-side delivery concern) —
   `core/` has no client concept
3. doc01 §1.4 already establishes this: "The ring buffer is a server-side
   application-level delivery optimization"

### Ring Buffer Wire Format

The ring buffer stores pre-serialized wire-format frames (FrameEntry = header +
payload bytes). Frame serialization happens once at write time; delivery to
multiple clients is a memcpy from ring slot to send buffer. This avoids
per-client serialization overhead.

---

## Resolution 8: Code Structure — Binary/Library/Module Separation

**Consensus**: 6/6 unanimous + owner refinement (ADR 00048)

`[ADR-CANDIDATE]` → **ADR 00048** (Daemon Binary vs Library Responsibility
Separation). Three-layer separation: daemon binary orchestrates, libitshell3
owns domain logic, libitshell3-protocol owns transport.

### Responsibility Separation

| Responsibility                      | Owner                                                 |
| ----------------------------------- | ----------------------------------------------------- |
| CLI args, signal setup, LaunchAgent | `daemon/main.zig` (binary)                            |
| Socket create/bind/listen/accept    | `libitshell3-protocol` Layer 4 (`transport.Listener`) |
| kqueue event loop + domain handlers | `modules/libitshell3/src/server/` (library)           |
| Session/pane state, types           | `modules/libitshell3/src/core/` + `server/` (library) |
| ghostty API helpers                 | `modules/libitshell3/src/ghostty/` (library)          |
| Key routing (Phase 0+1)             | `modules/libitshell3/src/input/` (library)            |
| Graceful shutdown logic             | Library provides; binary triggers                     |

The daemon binary is thin (~100-200 lines): parse args → call
`transport.Listener.init()` → call library init → enter event loop → on
shutdown, call library shutdown → exit. No domain logic in the binary.

### libitshell3 Module Layout (4 modules)

```
modules/libitshell3/src/
  core/              → Pure state types (zero OS dependencies)
    session.zig        Session, PreeditState, PreeditCache
    split_node.zig     SplitNodeData, binary split tree ops
    pane_types.zig     PaneId, PaneSlot, MAX_PANES
    navigation.zig     findPaneInDirection (pure geometric)
    constants.zig      Shared constants

  ghostty/           → Thin helper functions (NO state, pure functions only)
    terminal.zig       Terminal init/deinit, vtStream
    export.zig         bulkExport, overlayPreedit wrappers
    key_encode.zig     key_encode.encode wrapper

  input/             → Phase 0+1 key routing (depends on core/ only)
    handler.zig        handleKeyEvent, focus change, IME switch

  server/            → Event-driven runtime (domain logic)
    event_loop.zig     kqueue dispatch, timer management
    session_entry.zig  SessionEntry (pane_slots, dirty_mask)
    pane.zig           Pane (owns Terminal + RenderState + pty_fd)
    client_state.zig   ClientState struct + state machine
    ring_buffer.zig    Ring buffer + per-client cursors
    handlers/          Per-event handlers (flat namespace)
      sigchld.zig        Two-phase SIGCHLD + pane destroy cascade
      client.zig         Client message dispatch
      resize.zig         Resize orchestration
      preedit.zig        Preedit procedures
    coalescing.zig     Adaptive coalescing tiers
    health.zig         Health escalation state machine
    silence.zig        Silence detection timer
```

**No `main.zig` in `server/`** — that name is reserved for `daemon/main.zig`.

**Dispatch model**: Two-level dispatch — event loop dispatches by kqueue filter
type (EVFILT_SIGNAL, EVFILT_READ, EVFILT_TIMER), then by message domain. Exact
file-level handler organization is an implementation decision.

Architecture docs describe `core/`, `ghostty/`, `input/` types and boundaries.
Behavior docs describe what `server/handlers/` must do.

---

## Resolution 9: Implementation Gaps

**Consensus**: 6/6 unanimous

8 gaps requiring resolution before or during implementation:

1. **Ring buffer concrete values** — slot count, entry max size, eviction policy
2. **Default session parameters** — terminal dimensions, shell selection for
   Step 6 startup
3. **Health escalation timer anchor** — does stale timer start from last
   heartbeat response or last application-level message?
4. **Coalescing/keyframe timer interaction** — how coalescing timer and I-frame
   keyframe timer coordinate
5. **ExportResult buffer reuse strategy** — current `bulkExport()` allocates and
   returns; need `bulkExportInto()` variant that writes into pre-existing buffer
   (specific API change in `render_export.zig`)
6. **Alternate screen detection** — how daemon detects primary/alternate screen
   switches for I-frame generation
7. **Pane navigation geometry caching** — confirm no-cache decision holds under
   16-pane worst case
8. **FlatCell/CellData LE constraint** — document explicitly at the export
   boundary

---

## Resolution 10: Carry-Forward Fixes from r7 Round 4

**Consensus**: 6/6 unanimous

Two secondary findings from r7 Round 4, unfixed:

1. **doc01 §5.2 Mermaid diagram — missing session_id increment**: Fix in
   architecture doc during restructuring. The focus-change note should include
   `session_id` increment for consistency with all other preedit-ending paths.

2. **doc04 §8.4 commit_current=true — missing owner clear + session_id
   increment**: Fix in behavior doc. The `InputMethodSwitch` with
   `commit_current=true` path must clear `preedit.owner` and increment
   `session_id` like all other commit paths.

Both are minor and should be addressed during the restructuring writing phase.

---

## Resolution 11: ghostty API Gap Analysis

**Consensus**: 6/6 unanimous

### APIs Referenced by Daemon Design Docs

1. `Terminal.init(alloc, .{.cols, .rows})` — headless terminal creation
2. `terminal.vtStream(bytes)` — VT parsing
3. `RenderState.update(alloc, &terminal)` — capture state
4. `bulkExport(alloc, &render_state, &terminal)` — FlatCell export (PoC 06-07)
5. `importFlatCells(render_state, flat_cells)` — client-side import (PoC 08)
6. `key_encode.encode(writer, event, opts)` — key encoding
7. `Options.fromTerminal(&terminal)` — DEC mode query
8. `overlayPreedit(export_result, preedit, cursor)` — preedit cell injection
   (**does NOT exist yet** — must be written from scratch)
9. `Terminal.deinit()` — cleanup
10. Mouse input: **No Terminal mouse APIs exist** (`mouseButton()`,
    `mouseScroll()`, `mousePos()` are Surface-level, not available on headless
    Terminal). The daemon writes mouse escape sequences directly using
    `mouse_encode.encode()` + `terminal.flags.mouse_format`.
11. HID-to-Key mapping: comptime translation table from HID keycodes to ghostty
    `input.Key` values (needed for key_encode pipeline)

### Known Gaps

- `bulkExport` and `importFlatCells` exist as patches in the PoC vendor copy
  only, not in the main `vendors/ghostty/` submodule
- `overlayPreedit` does NOT exist anywhere — must be written from scratch (~20
  lines, injects preedit cells into ExportResult post-export)
- `render_export.zig` (new file from PoC) is in the PoC vendor copy only, not in
  the main `vendors/ghostty/` submodule
- HID-to-Key comptime mapping table does not exist — must be authored
- Mouse APIs (`mouseButton()`, `mouseScroll()`, `mousePos()`) referenced in r7
  docs are **incorrect** — these are Surface-level APIs not available on
  headless Terminal

### Pre-Implementation Investigation Tasks

1. **render_export.zig port** — Port PoC patches (bulkExport, importFlatCells)
   from the PoC vendor copy into the main `vendors/ghostty/` submodule. Add
   `bulkExportInto()` buffer-reuse variant (writes into pre-existing
   ExportResult). Check for upstream breakage since PoC.

2. **overlayPreedit() implementation** — Write the preedit cell injection
   function from scratch. Design: takes ExportResult + preedit text + cursor
   position, overwrites cells at cursor row with preedit content. ~20 lines.

3. **Terminal.deinit() ordering verification** — Confirm `Terminal.deinit()`
   does not access PTY fd or Surface/renderer state. Validates safe ordering:
   `close(pty_fd)` → `Terminal.deinit()` → cleanup. This is a correctness
   prerequisite for constraint #5 in the pane destroy cascade.

4. **Mouse input correction** — Update daemon docs to replace `mouseButton()`,
   `mouseScroll()`, `mousePos()` references with the correct approach:
   `mouse_encode.encode()` + `terminal.flags.mouse_format` for writing mouse
   escape sequences directly. The daemon does not use Surface-level mouse APIs.

5. **HID-to-Key mapping** — Author a comptime translation table from HID
   keycodes to ghostty `input.Key` values for the key_encode pipeline.

6. **Vendor pin strategy** — Pin to specific ghostty commit for v1 stability.
   Document which commit and what patches are applied.

---

## Resolution 12: Response-Before-Notification Cross-Cutting Invariant

**Consensus**: 6/6 unanimous (added during verification — flagged by
protocol-architect, endorsed by system-sw-engineer)

The r7 handover established "response-before-notification is universal" as a
design philosophy. The r7 docs reference this rule in 4+ places but never
formally define it. During restructuring, this MUST be formalized as a top-level
cross-cutting invariant in behavior `02-event-handling.md`:

> **Cross-cutting invariant**: For any request that produces both a response to
> the requester and notifications to other clients, the response MUST be sent
> before the notifications.

Known instances: `NavigatePaneResponse` before `LayoutChanged`,
`WindowResizeAck` before `LayoutChanged`, `ClosePaneResponse` before
`LayoutChanged`. The invariant applies to any future request/notification pair.

---

## Normative Authority Statement

**Consensus**: 6/6 unanimous (implicit in Resolution 1, made explicit here)

- The **protocol spec** (libitshell3-protocol) is the sole normative source for
  wire semantics (message types, field values, encoding, ordering visible to
  clients)
- The **behavior docs** (daemon-behavior/) are normative for internal daemon
  constraints only (ordering not visible on the wire, internal state machine
  transitions, resource lifecycle)
- The **architecture docs** (daemon-architecture/) are normative for structural
  decisions (module boundaries, type definitions, dependency directions) and
  design rationale

---

## Verification Notes

All 5 teammates verified the resolution document:

- **protocol-architect**: Approved. Flagged response-before-notification
  formalization (→ Resolution 12). Noted §7.1 preference for behavior but
  accepted architecture placement.
- **ghostty-integration**: Approved. Suggested Terminal.deinit() verification
  and bulkExportInto() (both incorporated).
- **system-sw-engineer**: Approved. No corrections.
- **daemon-architect**: Approved. Confirmed §7.1 in architecture, flagged doc02
  naming (corrected to `02-state-and-types.md`), noted bulkExportInto() gap.
- **ime-system-sw**: Approved. Noted LE constraint should be explicit at
  convergence point, clarified §3.11 "contract only" means full algorithm spec
  stays until code exists.
