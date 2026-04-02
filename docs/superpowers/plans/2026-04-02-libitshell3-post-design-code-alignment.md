# Post-Design Code Alignment Implementation Plan

**Goal:** Align libitshell3 and libitshell3-protocol code with post-Plan 15 spec
revisions. Four work items address gaps between code (built against r8/r12/r10
specs) and current specs (r9/r13/r11).

**Architecture:** Cross-module changes spanning protocol framing, session
management, layout tree representation, resize semantics, and IME modifier
handling. Each work item is self-contained and addresses a single ADR or design
resolution.

**Tech Stack:** Zig (build.zig modules: itshell3\_core, itshell3\_server,
itshell3\_input, itshell3\_protocol)

**Spec references:**

- server-client-protocols v1.0-r13: `01-protocol-overview.md` §3.1 (20-byte
  header, version 2, u64 sequence), `03-session-pane-management.md` §1.5-1.6
  (unified AttachSession), §2.3 (SplitPane ratio as u32 x10^4), §2.12-2.13
  (ResizePane orientation + delta\_ratio), §2.14 (EqualizeSplits ratio=5000),
  §3.2 (layout tree ratio as integer)
- IME interface-contract v1.0-r11: `02-types.md` (Modifiers with caps\_lock,
  num\_lock)
- ADR 00015 — u64 Sequence Numbers
- ADR 00003 — Merge AttachSession and AttachOrCreate
- ADR 00062 — Fixed-Point Signed Ratio Delta for ResizePaneRequest
- ADR 00059 — CapsLock and NumLock Modifiers in IME KeyEvent

---

## Scope

**In scope:**

1. Protocol header: 16→20 bytes, VERSION 1→2, sequence u32→u64 (ADR 00015)
2. Fixed-point ratio: f32→u32 x10^4 for split tree and resize (ADR 00062)
3. AttachOrCreate merge: delete 0x010C/0x010D, absorb into AttachSession 0x0104
   (ADR 00003)
4. CapsLock/NumLock modifiers: add to libitshell3 KeyEvent.Modifiers, preserve
   in wire decomposition (ADR 00059)

**Out of scope:**

- libitshell3-ime engine-level CapsLock/NumLock behavioral logic (case
  resolution, numpad classification) — Plan 8 will wire the IME engine behavior
- New message type handlers (Plans 8, 9)
- Shell/cwd arguments for session creation (Plan 9+)
- detach\_others/readonly logic for AttachSession (Plan 9+; fields parsed but
  behavior deferred)

## File Structure

### WI-1: u64 Sequence / 20-byte Header (ADR 00015)

| File                                              | Module      | Action | Responsibility                                                                |
| ------------------------------------------------- | ----------- | ------ | ----------------------------------------------------------------------------- |
| `src/header.zig`                                  | protocol    | Modify | HEADER\_SIZE 16→20, VERSION 1→2, sequence u32→u64, encode/decode byte offsets |
| `src/error.zig`                                   | protocol    | Modify | ErrorResponse.ref\_sequence u32→u64                                           |
| `src/message_reader.zig`                          | protocol    | Modify | Sequence tracking fields u32→u64                                              |
| `src/writer.zig`                                  | protocol    | Modify | Sequence parameter u32→u64                                                    |
| `src/server/connection/connection_state.zig`      | libitshell3 | Modify | send\_sequence/recv\_sequence\_last u32→u64                                   |
| `src/server/handlers/protocol_envelope.zig`       | libitshell3 | Modify | sequence param u32→u64, doc comment 16→20                                     |
| `src/server/handlers/session_handler.zig`         | libitshell3 | Modify | sequence param u32→u64                                                        |
| `src/server/handlers/pane_handler.zig`            | libitshell3 | Modify | sequence param u32→u64                                                        |
| `src/server/handlers/notification_builder.zig`    | libitshell3 | Modify | sequence param u32→u64                                                        |
| `src/server/handlers/session_pane_dispatcher.zig` | libitshell3 | Modify | sequence extraction from header u32→u64                                       |
| `src/server/handlers/lifecycle_dispatcher.zig`    | libitshell3 | Modify | sequence extraction u32→u64                                                   |
| `src/server/handlers/message_dispatcher.zig`      | libitshell3 | Modify | CategoryDispatchParams header type                                            |
| `src/server/delivery/frame_serializer.zig`        | libitshell3 | Modify | Remove u32 narrowing cast on sequence                                         |
| Test files (see Tasks)                            | both        | Modify | Update HEADER\_SIZE refs, byte offsets, sequence types                        |

### WI-2: Fixed-Point Resize Ratio (ADR 00062)

| File                                              | Module      | Action | Responsibility                                                                                                               |
| ------------------------------------------------- | ----------- | ------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `src/core/types.zig`                              | libitshell3 | Modify | Add RATIO\_SCALE, MIN\_RATIO, EQUAL\_RATIO constants                                                                         |
| `src/core/split_tree.zig`                         | libitshell3 | Modify | SplitNodeData.ratio f32→u32, equalizeRatios 0.5→5000, clamp/arithmetic                                                       |
| `src/pane.zig`                                    | protocol    | Modify | SplitPaneRequest.ratio f32→u32, ResizePaneRequest direction→orientation + delta→delta\_ratio i32, LayoutNode.ratio ?f32→?u32 |
| `src/server/handlers/pane_handler.zig`            | libitshell3 | Modify | handleSplitPane ratio param f32→u32, handleResizePane direction→orientation + delta→delta\_ratio                             |
| `src/server/handlers/session_pane_dispatcher.zig` | libitshell3 | Modify | Wire parsing: resize fields orientation+delta\_ratio, split ratio u32                                                        |
| `src/server/handlers/notification_builder.zig`    | libitshell3 | Modify | Layout tree JSON ratio format: float→integer                                                                                 |

### WI-3: AttachOrCreate Merge (ADR 00003)

| File                                              | Module      | Action | Responsibility                                                                                                                 |
| ------------------------------------------------- | ----------- | ------ | ------------------------------------------------------------------------------------------------------------------------------ |
| `src/message_type.zig`                            | protocol    | Modify | Delete attach\_or\_create\_request/response enum values                                                                        |
| `src/session.zig`                                 | protocol    | Modify | Delete AttachOrCreateRequest/Response, add optional fields to AttachSessionRequest, add action\_taken to AttachSessionResponse |
| `src/server/handlers/session_handler.zig`         | libitshell3 | Modify | Merge handleAttachOrCreate logic into handleAttachSession, delete old handler                                                  |
| `src/server/handlers/session_pane_dispatcher.zig` | libitshell3 | Modify | Remove .attach\_or\_create\_request dispatch arm, update .attach\_session\_request parsing                                     |

### WI-4: CapsLock/NumLock in KeyEvent (ADR 00059)

| File                           | Module          | Action | Responsibility                                      |
| ------------------------------ | --------------- | ------ | --------------------------------------------------- |
| `src/core/ime_engine.zig`      | libitshell3     | Modify | Modifiers: add caps\_lock, num\_lock, padding u5→u3 |
| `src/input/wire_decompose.zig` | libitshell3     | Modify | Extract wire bits 4-5 into caps\_lock/num\_lock     |
| `src/types.zig`                | libitshell3-ime | Modify | Modifiers: add caps\_lock, num\_lock, padding u5→u3 |

## Tasks

### Task 1: Protocol header — u64 sequence and 20-byte layout

**Files:** `modules/libitshell3-protocol/src/header.zig` (modify)

**Spec:** protocol `01-protocol-overview.md` §3.1 (20-byte header layout,
version 2, u64 sequence at offset 12). ADR 00015.

**Depends on:** None

**Verification:**

- HEADER\_SIZE constant is 20
- VERSION constant is 2
- Header struct has `sequence: u64`
- `encode()` writes u64 at bytes 12..20
- `decode()` reads u64 from bytes 12..20
- All inline tests updated: size test checks 20, round-trip tests use u64
  sequence values (including values > u32 max), version test uses VERSION=2

---

### Task 2: Protocol error and reader — u64 sequence propagation

**Files:** `modules/libitshell3-protocol/src/error.zig` (modify),
`modules/libitshell3-protocol/src/message_reader.zig` (modify),
`modules/libitshell3-protocol/src/writer.zig` (modify)

**Spec:** protocol `01-protocol-overview.md` §6 (ErrorResponse ref\_sequence is
u64 per §3.1 sequence field). ADR 00015.

**Depends on:** Task 1

**Verification:**

- ErrorResponse.ref\_sequence is u64
- MessageReader internal sequence tracking uses u64
- Writer sequence parameter is u64
- All inline tests compile and pass with u64 values
- Protocol module compiles:
  `(cd modules/libitshell3-protocol && zig build test --summary all)`

---

### Task 3: libitshell3 connection state — u64 sequence

**Files:** `modules/libitshell3/src/server/connection/connection_state.zig`
(modify)

**Spec:** protocol §3.1 (u64 sequence). daemon-architecture
`02-state-and-types.md` (ConnectionState fields).

**Depends on:** Task 1

**Verification:**

- `send_sequence` is u64, initial value 1
- `recv_sequence_last` is u64
- `advanceSendSequence()` returns u64
- Wrap comment updated (no practical wrap concern with u64)
- Inline tests pass

---

### Task 4: Protocol envelope and notification builder — u64 sequence

**Files:** `modules/libitshell3/src/server/handlers/protocol_envelope.zig`
(modify), `modules/libitshell3/src/server/handlers/notification_builder.zig`
(modify)

**Spec:** protocol §3.1 (u64 sequence in header). ADR 00015.

**Depends on:** Task 1

**Verification:**

- `wrap()`, `wrapResponse()`, `wrapNotification()` accept `sequence: u64`
- Doc comment updated from 16-byte to 20-byte
- All notification builder functions accept `sequence: u64`
- Inline tests pass

---

### Task 5: Handler and dispatcher files — u64 sequence

**Files:** `modules/libitshell3/src/server/handlers/session_handler.zig`
(modify), `modules/libitshell3/src/server/handlers/pane_handler.zig` (modify),
`modules/libitshell3/src/server/handlers/session_pane_dispatcher.zig` (modify),
`modules/libitshell3/src/server/handlers/lifecycle_dispatcher.zig` (modify),
`modules/libitshell3/src/server/handlers/message_dispatcher.zig` (modify),
`modules/libitshell3/src/server/delivery/frame_serializer.zig` (modify)

**Spec:** protocol §3.1 (u64 sequence). ADR 00015.

**Depends on:** Tasks 3, 4

**Verification:**

- All handler functions accept `sequence: u64` parameter
- All dispatchers extract sequence as u64 from header
- `frame_serializer.zig` removes the `@intCast(next_sequence.* & 0xFFFFFFFF)`
  narrowing cast — passes u64 directly to Header
- CategoryDispatchParams carries u64 sequence via the Header struct
- No u32 sequence references remain in `src/server/`

---

### Task 6: WI-1 spec test updates — u64 header

**Files:** All test files under `modules/libitshell3/src/testing/spec/` and
`modules/libitshell3-protocol/src/testing/spec/` that reference HEADER\_SIZE,
byte offset 12..16, or u32 sequence types

**Spec:** protocol §3.1, ADR 00015.

**Depends on:** Task 5

**Verification:**

- All spec test helpers construct 20-byte headers with VERSION=2
- Byte offset assertions updated (sequence at 12..20, not 12..16)
- Sequence values in test fixtures use u64
- Full test suite passes: both `libitshell3-protocol` and `libitshell3`

---

### Task 7: Split tree and protocol ratio types — f32 to u32 fixed-point

**Files:** `modules/libitshell3/src/core/types.zig` (modify),
`modules/libitshell3/src/core/split_tree.zig` (modify),
`modules/libitshell3-protocol/src/pane.zig` (modify)

**Spec:** protocol `03-session-pane-management.md` §2.3 (ratio as u32 x10^4),
§2.14 (equalize to 5000), §3.2 (layout tree ratio integer). ADR 00062.

**Depends on:** None

**Verification:**

- `types.zig` defines `RATIO_SCALE: u32 = 10_000`, `MIN_RATIO: u32 = 500`,
  `EQUAL_RATIO: u32 = 5000`
- `SplitNodeData.split.ratio` is u32
- `splitLeaf()` accepts ratio as u32
- `equalizeRatios()` sets ratio to `EQUAL_RATIO` (5000)
- `findAdjacentSplit()` works unchanged (does not inspect ratio)
- Layout dimension calculation uses integer arithmetic:
  `left_width = width * ratio / RATIO_SCALE`
- Protocol `pane.zig`: `SplitPaneRequest.ratio` is u32, `ResizePaneRequest` uses
  `orientation: u8` + `delta_ratio: i32`, `LayoutNode.ratio` is `?u32`
- All split\_tree inline tests updated for integer ratios
- Both modules compile:
  `(cd modules/libitshell3-protocol && zig build test --summary all)` and
  `(cd modules/libitshell3 && zig build test --summary all)` pass

---

### Task 8: Resize handler — orientation + delta\_ratio

**Files:** `modules/libitshell3/src/server/handlers/pane_handler.zig` (modify),
`modules/libitshell3/src/server/handlers/session_pane_dispatcher.zig` (modify)

**Spec:** protocol `03-session-pane-management.md` §2.12 (ResizePaneRequest:
orientation u8 + delta\_ratio i32), §2.13 (response status 2 = no split in that
orientation). ADR 00062.

**Depends on:** Task 7

**Verification:**

- `handleResizePane()` signature changes: `direction: Direction` →
  `orientation:
  Orientation`, `delta: i32` → `delta_ratio: i32`
- Finds nearest ancestor split matching orientation (not direction)
- Applies `new_ratio = old_ratio + delta_ratio` with integer arithmetic
- Clamps to `[MIN_RATIO, RATIO_SCALE - MIN_RATIO]`
- Removes the hardcoded `/80.0` float conversion
- `handleSplitPane()` signature: ratio param f32→u32
- Dispatcher wire parsing: resize fields are `orientation: u8` +
  `delta_ratio:
  i32`; split ratio field parsed as u32

---

### Task 9: Notification builder — integer ratio in layout JSON

**Files:** `modules/libitshell3/src/server/handlers/notification_builder.zig`
(modify)

**Spec:** protocol `03-session-pane-management.md` §3.2 (ratio as integer in
JSON layout tree).

**Depends on:** Task 7

**Verification:**

- `serializeLayoutTree()` (or equivalent) emits ratio as integer, not float
  (e.g., `"ratio":5000` not `"ratio":0.500000`)
- Layout dimension calculations use integer arithmetic matching split\_tree
- Inline tests verify integer ratio in JSON output

---

### Task 10: Delete AttachOrCreate message types

**Files:** `modules/libitshell3-protocol/src/message_type.zig` (modify),
`modules/libitshell3-protocol/src/session.zig` (modify)

**Spec:** protocol `03-session-pane-management.md` §1.5-1.6 (unified
AttachSession with session\_name, create\_if\_missing, action\_taken).
ADR 00003.

**Depends on:** None

**Verification:**

- `MessageType` enum has no `attach_or_create_request` or
  `attach_or_create_response` values
- `AttachOrCreateRequest` and `AttachOrCreateResponse` structs deleted
- `AttachSessionRequest` gains optional fields: `session_name`, `shell`, `cwd`
  (all `?[]const u8 = null`), `create_if_missing: bool = false`
- `AttachSessionResponse` gains `action_taken: []const u8 = "attached"` and
  `pane_id: u32 = 0`
- JSON round-trip tests updated for new fields
- Protocol module compiles

---

### Task 11: Merge AttachOrCreate handler into AttachSession

**Files:** `modules/libitshell3/src/server/handlers/session_handler.zig`
(modify), `modules/libitshell3/src/server/handlers/session_pane_dispatcher.zig`
(modify), `modules/libitshell3/src/server/connection/connection_state.zig`
(modify)

**Spec:** protocol `03-session-pane-management.md` §1.5-1.6 (AttachSession
unified lookup: session\_id or session\_name, create\_if\_missing). ADR 00003.

**Depends on:** Task 10

**Verification:**

- `handleAttachOrCreate()` deleted
- `handleAttachSession()` handles both paths: by session\_id (existing) and by
  session\_name with create\_if\_missing (merged from AttachOrCreate)
- Response includes `action_taken` field when create\_if\_missing was true
- Dispatcher `.attach_or_create_request` arm removed
- Dispatcher `.attach_session_request` parses the expanded field set
  (session\_id, session\_name, create\_if\_missing)
- `connection_state.zig` allowed messages list: `.attach_or_create_request`
  removed
- All response message types use 0x0105, never 0x010D

---

### Task 12: WI-3 test updates — AttachOrCreate removal

**Files:** Test files referencing AttachOrCreate:
`modules/libitshell3/src/testing/spec/session_attachment_spec_test.zig`,
`modules/libitshell3/src/testing/spec/session_crud_spec_test.zig`,
`modules/libitshell3-protocol/src/testing/spec/coverage_gaps_spec_test.zig`, and
others found by grep

**Spec:** ADR 00003. Protocol §1.5-1.6.

**Depends on:** Task 11

**Verification:**

- No test references `attach_or_create_request`, `attach_or_create_response`,
  `0x010C`, `0x010D`, `AttachOrCreateRequest`, or `AttachOrCreateResponse`
- Tests cover the unified AttachSession flow: by ID, by name, with
  create\_if\_missing true/false
- Full test suite passes

---

### Task 13: CapsLock/NumLock in KeyEvent.Modifiers (both modules)

**Files:** `modules/libitshell3/src/core/ime_engine.zig` (modify),
`modules/libitshell3/src/input/wire_decompose.zig` (modify),
`modules/libitshell3-ime/src/types.zig` (modify)

**Spec:** IME interface-contract v1.0-r11 `02-types.md` (Modifiers packed struct
with caps\_lock bit 3, num\_lock bit 4, padding u3). ADR 00059.

**Depends on:** None

**Verification:**

- Both `libitshell3/core/ime_engine.zig` and `libitshell3-ime/src/types.zig`
  define `KeyEvent.Modifiers` with: ctrl (bit 0), alt (bit 1), super\_key (bit
  2), caps\_lock (bit 3), num\_lock (bit 4), \_padding u3
- `@sizeOf(Modifiers)` is still 1 in both modules
- `hasCompositionBreakingModifier()` does NOT check caps\_lock or num\_lock
- `decomposeWireEvent()` extracts wire bit 4 → `caps_lock`, wire bit 5 →
  `num_lock`
- Inline tests verify caps\_lock and num\_lock are populated from wire byte
- Existing tests for shift/ctrl/alt/super still pass
- `(cd modules/libitshell3 && zig build test --summary all)` passes
- `(cd modules/libitshell3-ime && zig build test --summary all)` passes

---

### Task 14: Full integration verification

**Files:** No new files — verification only

**Spec:** All four ADRs (00015, 00062, 00003, 00059).

**Depends on:** Tasks 6, 8, 9, 12, 13

**Verification:**

- `(cd modules/libitshell3-protocol && zig build test --summary all)` — zero
  failures
- `(cd modules/libitshell3 && zig build test --summary all)` — zero failures
- `mise run test:macos` — all modules pass
- No u32 sequence types remain in protocol or server code (grep verification)
- No f32 ratio types remain in split\_tree or handlers (grep verification)
- No AttachOrCreate references remain in source (grep verification)
- No `0x010C` or `0x010D` literal values remain in source (grep verification)

## Dependency Graph

```
Task 1 (header.zig: 20-byte, u64)
├── Task 2 (error, reader, writer: u64)
├── Task 3 (connection_state: u64)
├── Task 4 (envelope, notification: u64)
│   └── Task 5 (all handlers/dispatchers: u64)
│       └── Task 6 (spec test updates for u64)
│
Task 7 (split_tree + types: u32 ratio)
├── Task 8 (resize/split handlers: orientation + delta_ratio)
└── Task 9 (notification: integer ratio JSON)
│
Task 10 (protocol: delete AttachOrCreate types/structs)
└── Task 11 (handler: merge into AttachSession)
    └── Task 12 (test updates for merge)
│
Task 13 (CapsLock/NumLock modifiers — independent)
│
└── all ──→ Task 14 (integration verification)
```

Tasks 1, 7, 10, and 13 are independent roots — they can start in parallel.
Within each work item, tasks are sequential. Task 14 runs after all others
complete.

## Summary

| Task | Work Item | Files                                                                        | Spec Section                          |
| ---- | --------- | ---------------------------------------------------------------------------- | ------------------------------------- |
| 1    | WI-1      | `header.zig`                                                                 | Protocol §3.1, ADR 00015              |
| 2    | WI-1      | `error.zig`, `message_reader.zig`, `writer.zig`                              | Protocol §3.1, §6, ADR 00015          |
| 3    | WI-1      | `connection_state.zig`                                                       | Protocol §3.1, daemon-arch §2         |
| 4    | WI-1      | `protocol_envelope.zig`, `notification_builder.zig`                          | Protocol §3.1, ADR 00015              |
| 5    | WI-1      | All handlers, dispatchers, frame\_serializer                                 | Protocol §3.1, ADR 00015              |
| 6    | WI-1      | Spec test files (both modules)                                               | Protocol §3.1, ADR 00015              |
| 7    | WI-2      | `types.zig`, `split_tree.zig`, protocol `pane.zig`                           | Protocol §2.3, §2.14, §3.2, ADR 00062 |
| 8    | WI-2      | `pane_handler.zig`, `session_pane_dispatcher.zig`                            | Protocol §2.12-2.13, ADR 00062        |
| 9    | WI-2      | `notification_builder.zig`                                                   | Protocol §3.2                         |
| 10   | WI-3      | `message_type.zig`, `session.zig`                                            | Protocol §1.5-1.6, ADR 00003          |
| 11   | WI-3      | `session_handler.zig`, `session_pane_dispatcher.zig`, `connection_state.zig` | Protocol §1.5-1.6, ADR 00003          |
| 12   | WI-3      | Test files                                                                   | ADR 00003                             |
| 13   | WI-4      | `ime_engine.zig`, `wire_decompose.zig`, ime `types.zig`                      | IME contract §2, ADR 00059            |
| 14   | All       | (verification only)                                                          | All 4 ADRs                            |
