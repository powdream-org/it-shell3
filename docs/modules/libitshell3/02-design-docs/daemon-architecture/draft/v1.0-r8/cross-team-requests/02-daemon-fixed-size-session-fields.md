# Fixed-Size Inline Buffers and Field Naming for Session/Pane Types

- **Date**: 2026-03-26
- **Source team**: daemon
- **Source version**: N/A (implementation cycle Plan 5, not a
  design-doc-revision)
- **Source resolution**: ADR 00058 (Fixed-Size Inline Buffers for Session
  Fields), ADR 00052 (Static Allocation for SessionManager)
- **Target docs**: `impl-constraints/state-and-types.md`,
  `02-state-and-types.md` §1.2-§1.3, `03-policies-and-procedures.md` (overflow
  policy)
- **Status**: open

---

## Context

During Plan 5 (IME Integration) verification, a spec-code divergence was
discovered: the spec (`impl-constraints/state-and-types.md`) defines Session
string fields as `[]const u8` slices, while the code uses `[N]u8` + length field
inline buffers. No ADR, CTR, or design resolution existed for this choice.

ADR 00058 was created to formally accept the inline buffer pattern. The decision
complements ADR 00052 (static SessionManager allocation): static allocation
determines WHERE the struct lives (.bss); ADR 00058 determines HOW string fields
are stored within it (inline, not heap-pointed). Benefits include no allocator
dependency, no lifetime management, no allocation failure, and
compile-time-deterministic memory layout.

Additionally, several field naming divergences and missing fields were found
during spec-code verification.

## Required Changes

### 1. `impl-constraints/state-and-types.md` — Session type representation

- **Current**: Session string fields use `[]const u8` slice types:
  ```zig
  name: []const u8,
  active_input_method: []const u8,
  active_keyboard_layout: []const u8,
  current_preedit: ?[]const u8,
  ```
- **After**: Inline buffer representation per ADR 00058:
  ```zig
  name: [MAX_SESSION_NAME]u8,
  name_length: u8,
  active_input_method: [MAX_INPUT_METHOD_NAME]u8,
  active_input_method_length: u8,
  active_keyboard_layout: [MAX_KEYBOARD_LAYOUT_NAME]u8,
  active_keyboard_layout_length: u8,
  current_preedit: ?[]const u8,  // points into preedit_buf
  preedit_buf: [MAX_PREEDIT_BUF]u8,
  ```
- **Rationale**: ADR 00058 — fixed-size buffers eliminate allocator dependency
  and complement ADR 00052's static allocation model. Length fields use
  `_length` suffix per Zig naming convention (`docs/conventions/zig-naming.md`).

### 2. `01-module-structure.md` §1.5 — SessionManager data structure

- **Current**: "SessionManager uses `HashMap(u32, *SessionEntry)` for sessions
  (dynamic count, few instances — no fixed limit for sessions)."
- **After**: "SessionManager uses `[MAX_SESSIONS]?SessionEntry` fixed-size array
  for sessions. `MAX_SESSIONS = 64`. Session lookup by ID uses linear scan over
  the array (64 slots, negligible cost for single-threaded daemon)."
- **Rationale**: ADR 00052 established static allocation for SessionManager. The
  `[64]?SessionEntry` array is explicitly documented in the ADR. The spec's
  HashMap description predates this decision and was never updated.

### 3. `impl-constraints/state-and-types.md` — Add MAX_SIZE constants (including MAX_SESSIONS)

- **Current**: No buffer size constants defined.
- **After**: Add constants table:

  | Constant                   | Value | Rationale                              |
  | -------------------------- | ----- | -------------------------------------- |
  | `MAX_SESSION_NAME`         | 64    | Session name for display               |
  | `MAX_INPUT_METHOD_NAME`    | 32    | Identifier (`"korean_2set"`)           |
  | `MAX_KEYBOARD_LAYOUT_NAME` | 32    | Identifier (`"qwerty"`)                |
  | `MAX_PREEDIT_BUF`          | 64    | UTF-8 preedit overlay                  |
  | `MAX_PANE_TITLE`           | 256   | Terminal title (OSC 0/2)               |
  | `MAX_SESSIONS`             | 64    | Static array capacity (ADR 00052)      |
  | `MAX_PANE_CWD`             | 4096  | Current working directory (`PATH_MAX`) |

- **Rationale**: ADR 00058 requires documented maximum sizes for all inline
  buffer fields. `MAX_SESSIONS` is per ADR 00052.

### 4. `02-state-and-types.md` §1.2 — Field naming and types

- **Current**: Field name `keyboard_layout` with default `"us"`.
- **After**: Field name `active_keyboard_layout` with default `"qwerty"`. Length
  fields use `_length` suffix (e.g., `name_length`,
  `active_input_method_length`).
- **Rationale**: `active_` prefix matches `active_input_method` and protocol
  wire field name. Default `"qwerty"` per protocol identifier space (ADR 00025).
  No abbreviations per Zig naming convention.

### 5. `02-state-and-types.md` §1.3 — Confirm SessionEntry fields

- **Current**: `SessionEntry` spec includes `latest_client_id: u32`. Code does
  not have this field.
- **After**: No spec change needed — spec is already correct. Code will be fixed
  to match.
- **Rationale**: Pre-existing spec requirement for the `latest` resize policy.

### 6. Transient artifact lifecycle

- **Current**: `impl-constraints/state-and-types.md` header says "Deleted when
  the types exist in code." The types now exist in code.
- **After**: Either update the artifact to match current code representation
  (per changes 1-2 above), or delete it per its own lifecycle rule.
- **Rationale**: The artifact's own lifecycle clause.

### 7. `03-policies-and-procedures.md` — Overflow handling for user-settable fields

- **Current**: No overflow policy defined for fixed-size buffer fields.
- **After**: Define overflow handling policy distinguishing two categories:

  **User-settable fields** (values from users or external sources):
  - `MAX_SESSION_NAME` (64) — user names sessions via protocol messages
  - `MAX_PANE_TITLE` (256) — set by shell via OSC 0/2 escape sequences
  - `MAX_PANE_CWD` (4096) — set by shell via OSC 7

  **Daemon-internal constants** (cannot be exceeded at runtime):
  - `MAX_INPUT_METHOD_NAME` (32) — predetermined identifiers
  - `MAX_KEYBOARD_LAYOUT_NAME` (32) — predetermined identifiers
  - `MAX_PREEDIT_BUF` (64) — IME engine output, bounded by composition rules

  The policy must specify:
  - What happens when a user-settable value exceeds MAX (truncate at UTF-8
    character boundary? reject with error?)
  - Where enforcement happens (at the setter/update path, not at read time)
  - Whether truncation is silent or logged

- **Rationale**: ADR 00058 introduces fixed-size buffers. Without an overflow
  policy, buffer overruns are possible for user-controlled values.

## Summary Table

| Target Doc                            | Section/Message     | Change Type                                      | Source Resolution    |
| ------------------------------------- | ------------------- | ------------------------------------------------ | -------------------- |
| `impl-constraints/state-and-types.md` | Session struct      | Update representation to inline buffers          | ADR 00058            |
| `01-module-structure.md`              | §1.5 SessionManager | HashMap → fixed array `[MAX_SESSIONS]?`          | ADR 00052            |
| `impl-constraints/state-and-types.md` | (new)               | Add MAX_SIZE constants table (incl MAX_SESSIONS) | ADR 00052, 00058     |
| `02-state-and-types.md`               | §1.2 Session        | Fix field names, types, defaults                 | ADR 00058, ADR 00025 |
| `02-state-and-types.md`               | §1.3 SessionEntry   | Confirm `latest_client_id` (no spec change)      | Pre-existing spec    |
| `impl-constraints/state-and-types.md` | lifecycle           | Update or delete per transient artifact rule     | Self-referential     |
| `03-policies-and-procedures.md`       | (new)               | Add overflow policy for user-settable fields     | ADR 00058            |
