# libitshell3 Spec Alignment Audit — Implementation Plan

**Goal:** Align the libitshell3 implementation with its design specs by fixing
code bugs, resolving structural divergences, and correcting convention
violations identified during the Plan 5.5 audit.

**Architecture:** The changes span all libitshell3 named modules (core, server,
input, ghostty, testing). Structural refactoring moves types to their
spec-designated modules and redesigns the split tree to use heap-index
arithmetic. Convention fixes are mechanical and parallelizable.

**Tech Stack:** Zig 0.15+, libitshell3 build system (`build.zig`)

**Spec references:**

- daemon-architecture/draft/v1.0-r8 (module structure, state and types,
  integration boundaries)
- daemon-behavior/draft/v1.0-r8 (daemon lifecycle, event handling)
- server-client-protocols/draft/v1.0-r12 (protocol overview, session/pane
  management, input and renderstate)
- libitshell3-ime interface-contract/draft/v1.0-r10
- libitshell3-ime behavior/draft/v1.0-r2
- ADR 00043 (binary split tree as sole pane layout model)
- ADR 00058 (fixed-size inline buffers)
- docs/conventions/zig-coding.md
- docs/conventions/zig-naming.md
- docs/conventions/zig-documentation.md
- docs/conventions/zig-testing.md

---

## Scope

**In scope:**

1. Code bugs: SIGHUP handler, Direction enum integer mapping, Action enum
   explicit tags
2. Owner-decided code fixes: Pane/SessionEntry move to server/, SplitNodeData
   heap-index redesign, navigation algorithm fix, KeyEvent.hid_keycode widening
3. Convention violations: module-level docs, spec section number removal, test
   directory restructure, test naming, compiler-verified test removal,
   `_len`/`_length` rename, `aim` abbreviation, inline test prefix format,
   arbitrary-width integer replacement (u3/u5 → u8 per zig-coding.md)
4. TODO additions: signal_handler, event_loop, client_accept
5. Structural refactoring: ClientEntry extraction, input/ module function moves

**Out of scope:**

- New feature implementation (Plans 6-16+)
- Protocol library changes (libitshell3-protocol is a separate library)
- libitshell3-ime implementation changes (separate module, own spec)
- Test coverage additions beyond what is required to verify the fixes

## File Structure

| File                                              | Action | Responsibility                                                                           |
| ------------------------------------------------- | ------ | ---------------------------------------------------------------------------------------- |
| `src/core/types.zig`                              | Modify | Fix Direction enum integer mapping; remove `_len` local if applicable                    |
| `src/core/ime_engine.zig`                         | Modify | Add explicit integer tags to Action enum; widen hid_keycode to u16                       |
| `src/core/split_tree.zig`                         | Modify | Redesign SplitNodeData to use `?SplitNodeData` optional + heap-index arithmetic          |
| `src/core/navigation.zig`                         | Modify | Change selection from "greatest overlap" to "shortest edge distance"                     |
| `src/core/session.zig`                            | Modify | Remove Pane/SessionEntry to server/; rename `aim` locals; adapt tree_nodes type          |
| `src/core/pane.zig`                               | Delete | Move to `src/server/pane.zig`                                                            |
| `src/core/root.zig`                               | Modify | Add `//!` header; remove Pane/SessionEntry re-exports; update post-move                  |
| `src/core/session_manager.zig`                    | Modify | Update imports after Pane/SessionEntry move; adapt to new tree type                      |
| `src/server/pane.zig`                             | Create | Pane struct moved from core/; typed ghostty pointers                                     |
| `src/server/session_entry.zig`                    | Create | SessionEntry extracted from core/session.zig                                             |
| `src/server/client_state.zig`                     | Create | ClientEntry extracted from event_loop.zig                                                |
| `src/server/event_loop.zig`                       | Modify | Extract ClientEntry; add TODO(Plan 6) for event priority ordering                        |
| `src/server/signal_handler.zig`                   | Modify | Fix SIGHUP to trigger shutdown; add TODO(Plan 10) for graceful shutdown                  |
| `src/server/handlers/client_accept.zig`           | Modify | Add TODO(Plan 6) for UID verification and SO_SNDBUF/SO_RCVBUF                            |
| `src/server/ime_procedures.zig`                   | Modify | Update imports after Pane/SessionEntry move                                              |
| `src/server/ime_lifecycle.zig`                    | Modify | Update imports after Pane/SessionEntry move                                              |
| `src/server/ime_consumer.zig`                     | Modify | Update imports after Pane/SessionEntry move                                              |
| `src/server/root.zig`                             | Modify | Add `//!` header; add new file imports; update re-exports                                |
| `src/input/root.zig`                              | Modify | Add `//!` header                                                                         |
| `src/input/key_router.zig`                        | Modify | Remove spec section number refs if present                                               |
| `src/ghostty/root.zig`                            | Modify | Add `//!` header                                                                         |
| `src/ghostty/key_encoder.zig`                     | Modify | Remove spec section number refs                                                          |
| `src/ghostty/terminal.zig`                        | Modify | Remove spec section number refs                                                          |
| `src/ghostty/render_state.zig`                    | Modify | Remove spec section number refs                                                          |
| `src/ghostty/preedit_overlay.zig`                 | Modify | Remove spec section number refs                                                          |
| `src/ghostty/render_export.zig`                   | Modify | Remove spec section number refs                                                          |
| `src/os/root.zig`                                 | Modify | Add `//!` header                                                                         |
| `src/root.zig`                                    | Modify | Add `//!` header                                                                         |
| `src/testing/mock_os.zig`                         | Modify | Rename `write_len` field to `write_length`                                               |
| `src/testing/mock_ime_engine.zig`                 | Modify | Rename `set_aim_result`/`set_aim_count`/`last_set_aim_method` fields                     |
| `src/testing/root.zig`                            | Modify | Add `//!` header; restructure imports for mocks/ and spec/ subdirs                       |
| `src/testing/mocks/`                              | Create | New subdirectory for mock files                                                          |
| `src/testing/mocks/mock_os.zig`                   | Create | Moved from `src/testing/mock_os.zig`                                                     |
| `src/testing/mocks/mock_ime_engine.zig`           | Create | Moved from `src/testing/mock_ime_engine.zig`                                             |
| `src/testing/spec/`                               | Create | New subdirectory for spec test files                                                     |
| `src/testing/spec/*_spec_test.zig`                | Create | 8 spec test files moved from `src/testing/`                                              |
| `src/server/ring_buffer_integration_test.zig`     | Modify | Remove spec section number refs from comments and test names                             |
| `src/server/ring_buffer_spec_compliance_test.zig` | Modify | Remove spec section number refs; remove 6 compiler-verified tests; move to testing/spec/ |
| `build.zig`                                       | Modify | Update root source paths after testing/ restructure if needed                            |
| Multiple files (~10)                              | Modify | Rename ~80 spec test names to `"spec: topic -- requirement"` format                      |
| Multiple files (~10+)                             | Modify | Add `function_or_type:` prefix to ~57 inline tests                                       |

## Tasks

### Task 1: SplitNodeData Heap-Index Redesign (C2)

**Files:** `src/core/split_tree.zig` (modify), `src/core/session.zig` (modify),
`src/core/navigation.zig` (modify)

**Spec:** daemon-architecture `02-state-and-types.md` Section 1 — defines
`[31]?SplitNodeData` with heap-index arithmetic (parent = (i-1)/2, left = 2i+1,
right = 2i+2). ADR 00043 — binary split tree with implicit index arithmetic.

**Depends on:** None

**Verification:**

- SplitNodeData is a two-variant tagged union (leaf, split) with no `.empty`
  variant
- Tree array type is `[MAX_TREE_NODES]?SplitNodeData` (optional, not
  non-optional with `.empty`)
- Split variant has no explicit `left: u5`/`right: u5` child indices — children
  are computed by heap-index arithmetic
- `initSingleLeaf`, `splitLeaf`, `removeLeaf`, `findLeafBySlot`, `leafCount`,
  `depth`, `findParent` all use heap-index arithmetic instead of stored child
  pointers
- All existing split_tree tests pass with the new representation
- `Session.tree_nodes` type updated to match
- `navigation.zig` computeRectsNode and findPaneInDirection work with the new
  tree representation

### Task 2: Direction Enum Integer Mapping (PROTO-2)

**Files:** `src/core/types.zig` (modify)

**Spec:** server-client-protocols `03-session-pane-management.md` — directions
use integers: 0 = right, 1 = down, 2 = left, 3 = up (matches ghostty's
`GHOSTTY_SPLIT_DIRECTION`).

**Depends on:** None

**Verification:**

- `Direction` enum has explicit integer tags:
  `right = 0, down = 1, left = 2,
  up = 3`
- `@intFromEnum(Direction.right) == 0`, `@intFromEnum(Direction.down) == 1`,
  `@intFromEnum(Direction.left) == 2`, `@intFromEnum(Direction.up) == 3`

### Task 3: Action Enum Explicit Tags + KeyEvent.hid_keycode Widening (PROTO-5, C7)

**Files:** `src/core/ime_engine.zig` (modify)

**Spec:** server-client-protocols `04-input-and-renderstate.md` — action field
is u8 with 0=press, 1=release, 2=repeat. keycode field is u16. ADR 00058 for
HID_KEYCODE_MAX type.

**Depends on:** None

**Verification:**

- `KeyEvent.Action` has explicit integer tags:
  `press = 0, release = 1,
  repeat = 2`
- `KeyEvent.hid_keycode` type is `u16` (was `u8`)
- `KeyEvent.HID_KEYCODE_MAX` type is `u16` (was `u8`)
- All call sites that construct KeyEvent compile with the widened type

### Task 4: SIGHUP Shutdown Fix + Signal TODO (BEHAV-1, E-signal)

**Files:** `src/server/signal_handler.zig` (modify)

**Spec:** daemon-behavior `01-daemon-lifecycle.md` — SIGHUP is a shutdown
trigger alongside SIGTERM and SIGINT. daemon-behavior
`impl-constraints/daemon-lifecycle.md` — SIGHUP registered as graceful shutdown.

**Depends on:** None

**Verification:**

- SIGHUP case in handleSignalEvent sets `shutdown_requested = true` (same as
  SIGTERM/SIGINT)
- The old "ignored" comment is removed
- A `TODO(Plan 10)` comment is added for graceful shutdown procedure (client
  drain, preedit flush, child SIGHUP)

### Task 5: Pane and SessionEntry Move to server/ (C1)

**Files:** `src/core/pane.zig` (delete), `src/core/session.zig` (modify),
`src/core/root.zig` (modify), `src/core/session_manager.zig` (modify),
`src/server/pane.zig` (create), `src/server/session_entry.zig` (create),
`src/server/root.zig` (modify), plus all server/ files that import core pane or
session types

**Spec:** daemon-architecture `impl-constraints/state-and-types.md` — Pane is
annotated `<<server/pane.zig>>`, SessionEntry is annotated
`<<server/session_entry.zig>>`. Session stays in `core/session.zig`. The spec
class diagram explicitly places these in server/. SessionManager embeds
`[MAX_SESSIONS]?SessionEntry` by value, so SessionManager MUST also move to
server/ (it cannot reference a server/ type from core/). The spec's class
diagram does not annotate SessionManager with a file path, but its only field is
`sessions: HashMap<u32, *SessionEntry>` which requires SessionEntry — so it
belongs in server/.

**Spec (ghostty pointers):** Pane currently uses `?*anyopaque` for terminal,
render_state, vt_stream. The spec defines typed pointers: `*ghostty.Terminal`,
`*ghostty.RenderState`. Since Pane moves to server/ (which has ghostty as a
dependency), these should become typed pointers.

**Depends on:** Task 1 (SplitNodeData redesign changes the tree_nodes type that
Session uses, which SessionEntry wraps)

**Verification:**

- `src/core/pane.zig` no longer exists
- `src/server/pane.zig` contains the Pane struct with typed ghostty pointers
  (not `?*anyopaque`)
- `src/server/session_entry.zig` contains SessionEntry
- `src/server/session_manager.zig` exists (moved from core/) — or
  `src/core/session_manager.zig` is removed and replaced
- Session remains in `core/session.zig` but no longer contains Pane/SessionEntry
- `core/root.zig` no longer re-exports Pane, SessionEntry, or SessionManager
- `server/root.zig` re-exports Pane, SessionEntry, SessionManager
- All files that previously imported Pane/SessionEntry/SessionManager from
  `itshell3_core` now import from `itshell3_server`
- Build succeeds and all existing tests pass

### Task 6: Navigation Algorithm Fix (C3)

**Files:** `src/core/navigation.zig` (modify)

**Spec:** daemon-architecture `02-state-and-types.md` Section 2.2 — Step 4 says
"select the candidate with the shortest edge distance (distance between focused
edge and candidate's adjacent edge)". The current code selects by "greatest edge
overlap" instead of "shortest edge distance".

**Depends on:** Task 1 (navigation depends on the tree representation)

**Verification:**

- Direct neighbor selection uses shortest edge distance (not greatest overlap)
  as the primary criterion
- Tie-break is still lowest pane slot index
- Perpendicular overlap filter is still applied (only candidates with
  perpendicular overlap are considered)
- All existing navigation tests still pass (the change may require updating some
  test expectations if the algorithm produces different results for edge cases)

### Task 7: ClientEntry Extraction (ARCH-26)

**Files:** `src/server/event_loop.zig` (modify), `src/server/client_state.zig`
(create), `src/server/root.zig` (modify)

**Spec:** daemon-architecture `01-module-structure.md` — ClientEntry is a
server-side type; extraction to its own file improves module organization.

**Depends on:** None

**Verification:**

- ClientEntry struct is defined in `src/server/client_state.zig`
- `event_loop.zig` imports ClientEntry from the new file
- `server/root.zig` re-exports ClientEntry
- Build succeeds and all existing event_loop tests pass

### Task 8: Event Loop and Client Accept TODOs (E-event, E-client)

**Files:** `src/server/event_loop.zig` (modify),
`src/server/handlers/client_accept.zig` (modify)

**Spec:** daemon-behavior `02-event-handling.md` — event priority ordering.
daemon-architecture `03-integration-boundaries.md` — UID verification and socket
buffer configuration at accept time.

**Depends on:** None

**Verification:**

- `event_loop.zig` dispatch function has a `TODO(Plan 6)` comment about event
  priority ordering
- `client_accept.zig` has `TODO(Plan 6)` for UID verification
  (`getpeereid`/`SO_PEERCRED`)
- `client_accept.zig` has `TODO(Plan 6)` for `SO_SNDBUF`/`SO_RCVBUF`
  configuration

### Task 9: input/ Module Function Moves (ARCH-8)

**Files:** `src/input/root.zig` (modify), potentially new files in `src/input/`

**Spec:** daemon-architecture `01-module-structure.md` Section 1.2 — input/
module scope includes `handleIntraSessionFocusChange` and
`handleInputMethodSwitch`. These functions do not currently exist in the
codebase (they are stubs planned for future plans), but the spec assigns them to
input/. If any focus-change or input-method-switch logic currently lives in
server/, it should be moved.

**Depends on:** Task 5 (module boundary changes)

**Verification:**

- If any focus-change or input-method-switch orchestration logic exists in
  server/ files, it is moved to input/ (the IME lifecycle/procedures files in
  server/ implement the _engine-level_ operations; the _key-routing-level_
  orchestration belongs in input/ per spec)
- input/root.zig exports are updated if new files are added
- Existing tests pass

### Task 10: Test Directory Restructure (CONV-3~5)

**Files:** `src/testing/root.zig` (modify), `build.zig` (modify if needed),
create `src/testing/mocks/` and `src/testing/spec/` directories, move 2 mock
files and 8 spec test files plus ring_buffer spec compliance tests

**Spec:** docs/conventions/zig-testing.md — testing/ must have `mocks/` and
`spec/` subdirectories. Mock files go in `mocks/mock_*.zig`. Spec tests go in
`spec/*_spec_test.zig`.

**Depends on:** None (can run in parallel with code changes, but should be
sequenced after Task 5 to avoid move conflicts)

**Verification:**

- `src/testing/mocks/mock_os.zig` and `src/testing/mocks/mock_ime_engine.zig`
  exist (moved from `src/testing/`)
- `src/testing/spec/` contains all 8 `*_spec_test.zig` files (moved from
  `src/testing/`)
- `src/server/ring_buffer_spec_compliance_test.zig` is moved to
  `src/testing/spec/ring_buffer_spec_compliance_test.zig` (or remains in server/
  if the convention allows module-local spec tests — implementer decides based
  on dependency analysis)
- `src/testing/root.zig` imports from the new paths
- `build.zig` updated if module root source paths changed
- All tests still discovered and passing

### Task 11: Convention Fixes — Module-Level Docs (CONV-1)

**Files:** 7 `root.zig` files: `src/root.zig`, `src/core/root.zig`,
`src/server/root.zig`, `src/input/root.zig`, `src/ghostty/root.zig`,
`src/os/root.zig`, `src/testing/root.zig`

**Spec:** docs/conventions/zig-documentation.md Section 1 — every `root.zig`
MUST have `//!` top-level doc comments.

**Depends on:** None

**Verification:**

- All 7 root.zig files begin with `//!` module-level documentation comments
  describing the module's purpose

### Task 12: Convention Fixes — Spec Section Number Removal (CONV-2)

**Files:** `src/ghostty/key_encoder.zig`, `src/ghostty/preedit_overlay.zig`,
`src/ghostty/terminal.zig`, `src/ghostty/render_state.zig`,
`src/ghostty/render_export.zig`, `src/server/ring_buffer_integration_test.zig`,
`src/server/ring_buffer_spec_compliance_test.zig`, and any other files with `§`
or `Section N.N` references

**Spec:** docs/conventions/zig-documentation.md Section 5 — do NOT embed spec
section numbers. Reference specs by document/topic name only.

**Depends on:** None

**Verification:**

- No source file contains `§` followed by a number
- No source file contains `Section N.N` (where N is a digit) in comments
- Spec references use document/topic names instead (e.g., "per daemon-
  architecture state-and-types spec")

### Task 13: Convention Fixes — Compiler-Verified Test Removal (CONV-7)

**Files:** `src/server/ring_buffer_spec_compliance_test.zig` (modify)

**Spec:** docs/conventions/zig-testing.md — compiler-verified tests
(`@hasField`, `@hasDecl`, field count checks) should not exist because they test
the compiler, not the spec.

**Depends on:** None

**Verification:**

- The following 6 tests are removed:
  - Tests using `@hasField` to check field existence
  - Tests using `@hasDecl` to check API existence
  - Tests using `@typeInfo` to count struct fields
- No remaining tests in the codebase use `@hasField`, `@hasDecl`, or
  `@typeInfo(...).fields.len` as their sole assertion

### Task 14: Convention Fixes — Naming (CONV-8, CONV-9)

**Files:** `src/testing/mock_os.zig` (modify), `src/testing/mock_ime_engine.zig`
(modify), `src/core/session.zig` (modify), plus all files referencing renamed
fields

**Spec:** docs/conventions/zig-naming.md — no abbreviations. `_len` must be
`_length`. `aim` must be spelled out as `active_input_method` (or use the full
word in the variable name context).

**CONV-8 (`_len` to `_length`):**

- `mock_os.zig`: `write_len` field renamed to `write_length`
- `session.zig`: `name_len` local variable renamed (locals are less critical but
  should still follow convention for consistency)

**CONV-9 (`aim` abbreviation):**

- `session.zig`: `aim` local variables renamed to use full words (e.g.,
  `default_input_method` or `input_method_default`)
- `mock_ime_engine.zig`: PUBLIC fields renamed:
  - `set_aim_result` to `set_active_input_method_result`
  - `set_aim_count` to `set_active_input_method_count`
  - `last_set_aim_method` to `last_set_active_input_method`

**Depends on:** None

**Verification:**

- No struct field in the codebase uses `_len` as a suffix (except external
  library types and local variables in tight scope where the full name would be
  excessive — implementer judgment)
- No identifier uses `aim` as an abbreviation for `active_input_method`
- All references to renamed fields are updated
- Build succeeds and all tests pass

### Task 15: Convention Fixes — Test Naming (CONV-6, CONV-10)

**Files:** ~10 files containing spec tests, ~10+ files containing inline tests

**Spec:** docs/conventions/zig-testing.md — spec tests must use
`"spec: topic -- requirement"` format. docs/conventions/zig-naming.md — inline
tests must use `"function_or_type: description"` format.

**CONV-6 (spec test naming):** ~80 spec tests in 10 files need renaming from
current format (e.g., `"spec 4.1: ..."`) to `"spec: topic -- requirement"`
format.

**CONV-10 (inline test prefix):** ~57 inline tests missing the
`function_or_type:` prefix need the prefix added.

**Depends on:** Task 10 (test directory restructure moves the files first)

**Verification:**

- All spec tests match the pattern `test "spec: <topic> -- <requirement>"`
- All inline tests match the pattern `test "<FunctionOrType>.<method>: ..."` or
  `test "<function>: ..."` with the function/type prefix present
- No test name starts with a bare description without a function/type prefix
  (for inline tests) or without `"spec: "` (for spec tests)

### Task 16: Convention Fixes — Arbitrary-Width Integer Replacement

**Files:** `src/core/types.zig` (modify), `src/core/split_tree.zig` (modify),
`src/core/session_manager.zig` (modify), `src/core/navigation.zig` (modify),
`src/server/event_loop.zig` (modify), and any other files using non-standard
integer widths for loop counters, indices, or constants

**Spec:** docs/conventions/zig-coding.md — standard-width integers only (u8,
u16, u32, u64). No arbitrary-width integers except packed struct fields, extern
struct ABI fields, and `u21` Unicode codepoints.

**Known violations:**

- `types.zig`: `MAX_PANES: u5`, `MAX_TREE_NODES: u5`, `MAX_TREE_DEPTH: u3` → all
  `u8`
- `types.zig`: `slotShift` loop counter `var i: u5` → `u8`
- `split_tree.zig`: loop counters and indices using `u5` → `u8`
- `navigation.zig`: loop counters using `u5` → `u8`
- `event_loop.zig`: loop counters using `u5` → `u8`
- `preedit_overlay.zig`: `bit_idx: u6` → `u8` (intermediate local variable, no
  reason for u6)
- `preedit_overlay.zig`: `codepointWidth` return `u2` → `enum` (discrete values
  1 or 2 should be a semantic enum, not a bare integer)

**Allowed exceptions (do NOT change):**

- `u21` for Unicode codepoints (Zig std convention)
- Packed struct fields in `ime_engine.zig` Modifiers (wire protocol layout)
- `u16` for `PaneSlot` type alias (if spec defines it as u16)

**Depends on:** Task 1 (SplitNodeData redesign already touches these files)

**Verification:**

- No `u3`, `u4`, `u5`, `u6` types remain in non-packed-struct, non-extern
  contexts
- All constants use standard-width types (u8, u16, u32, u64)
- All loop counters and array indices use standard-width types
- Build succeeds and all tests pass

## Dependency Graph

```
Task 1 (SplitNodeData) ──┬──> Task 5 (Pane/SessionEntry move) ──> Task 9 (input/ moves)
                          │                                    ──> Task 10 (test restructure)
                          ├──> Task 6 (navigation fix)                    │
                          └──> Task 16 (integer widths)                   v
                                                                Task 15 (test naming)
Task 2 (Direction enum) ─────────────────────────────────────/
Task 3 (Action enum + hid_keycode) ────────────────────────/
Task 4 (SIGHUP fix) ─────────────────────────────────────/
Task 7 (ClientEntry extraction) ────────────────────────/
Task 8 (TODO additions) ──────────────────────────────/
Task 11 (module-level docs) ────────────────────────/
Task 12 (section number removal) ─────────────────/
Task 13 (compiler test removal) ────────────────/
Task 14 (naming fixes) ───────────────────────/
```

**Parallelization opportunities:**

- Tasks 2, 3, 4, 7, 8, 11, 12, 13, 14 are all independent and can run in
  parallel
- Task 1 must complete before Tasks 5, 6, and 16
- Task 5 must complete before Tasks 9 and 10
- Task 15 should run last (after file moves stabilize)

## Summary

| Task                         | Files                                       | Spec Section                                 |
| ---------------------------- | ------------------------------------------- | -------------------------------------------- |
| 1. SplitNodeData redesign    | split_tree.zig, session.zig, navigation.zig | daemon-arch state-and-types, ADR 00043       |
| 2. Direction enum fix        | types.zig                                   | protocol 03-session-pane-management          |
| 3. Action enum + hid_keycode | ime_engine.zig                              | protocol 04-input-and-renderstate            |
| 4. SIGHUP fix + TODO         | signal_handler.zig                          | daemon-behavior daemon-lifecycle             |
| 5. Pane/SessionEntry move    | core/ -> server/, multiple files            | daemon-arch impl-constraints/state-and-types |
| 6. Navigation algorithm      | navigation.zig                              | daemon-arch state-and-types Section 2.2      |
| 7. ClientEntry extraction    | event_loop.zig, client_state.zig            | daemon-arch module-structure                 |
| 8. TODO additions            | event_loop.zig, client_accept.zig           | daemon-behavior event-handling               |
| 9. input/ module moves       | input/ files                                | daemon-arch module-structure                 |
| 10. Test dir restructure     | testing/ directory, build.zig               | zig-testing convention                       |
| 11. Module-level docs        | 7 root.zig files                            | zig-documentation convention                 |
| 12. Section number removal   | 8+ source files                             | zig-documentation convention                 |
| 13. Compiler test removal    | ring_buffer_spec_compliance_test.zig        | zig-testing convention                       |
| 14. Naming fixes             | mock_os, mock_ime_engine, session           | zig-naming convention                        |
| 15. Test naming              | ~20 files                                   | zig-naming + zig-testing conventions         |
| 16. Integer width fixes      | types.zig, split_tree.zig, navigation.zig+  | zig-coding convention                        |
