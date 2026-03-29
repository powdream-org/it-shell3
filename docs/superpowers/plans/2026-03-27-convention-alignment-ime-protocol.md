# Convention Alignment: libitshell3-ime and libitshell3-protocol — Implementation Plan

**Goal:** Apply the same four Zig convention standards to
`modules/libitshell3-ime` and `modules/libitshell3-protocol` that were applied
to `modules/libitshell3` in Plan 5.5. These are purely mechanical convention
fixes — no behavioral changes, no type API changes, no new features.

**Precedent:** Plan 5.5
(`docs/superpowers/plans/2026-03-27-libitshell3-spec-alignment-audit.md`)
defines the same categories of fixes for `libitshell3`. The approach there — one
task per violation category, parallelizable — is the model for this plan.

**Tech Stack:** Zig 0.15+, libitshell3-ime and libitshell3-protocol build
systems (`build.zig` in each module)

**Convention references (the specs for this plan):**

- `docs/conventions/zig-coding.md` — integer type rules, derived constants
- `docs/conventions/zig-naming.md` — no abbreviations, `_length` suffix, test
  naming patterns
- `docs/conventions/zig-documentation.md` — `//!` module docs, no spec section
  numbers in comments
- `docs/conventions/zig-testing.md` — `testing/mocks/` and `testing/spec/`
  directory structure, test naming format

---

## Scope

**In scope:**

1. Missing `//!` module-level doc comments on `root.zig` files
2. Spec section number references (`§`, `Doc N §N`, `Section N.N`) in doc
   comments and inline comments — replace with topic-name references
3. `_len` suffix on struct fields — rename to `_length`
4. Arbitrary-width integer types outside permitted exceptions — replace with
   register-friendly widths per zig-coding.md rules
5. Compiler-verified tests (zero behavioral assertions) — remove
6. Test directory restructure — create `testing/mocks/` and `testing/spec/`
   subdirectories, relocate files
7. Test naming — apply `"FunctionOrType: description"` (inline) and
   `"spec: topic — requirement"` (spec) formats

**Out of scope:**

- Any behavioral changes to functions or types
- Protocol or IME API changes of any kind
- New feature implementation
- Coverage additions beyond what accompanies the naming fixes
- Changes to `modules/libitshell3` (covered by Plan 5.5)

## File Inventory

### libitshell3-ime (`modules/libitshell3-ime/src/`)

| File                     | Violations present                                                                                                                               |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `root.zig`               | `//!` present (OK); test discovery via `_ = @import(...)` (verify vs. `refAllDecls`)                                                             |
| `types.zig`              | Section number in module doc (`Section 3.1–3.2`); `§02-types.md` in test comment                                                                 |
| `engine.zig`             | Section number in module doc (`Section 3.5`)                                                                                                     |
| `hangul_engine.zig`      | Section number in module doc (`Section 3.7`); inline comment (`Section 3.2`); `_len` fields (`committed_len`, `preedit_len`, `prev_preedit_len`) |
| `mock_engine.zig`        | Section number in module doc (`Section 3.8`)                                                                                                     |
| `hangul_engine_test.zig` | Section number in module doc (`§3.1` twice); test names use `"A1: ..."` shorthand format, not convention format                                  |
| `ucs4.zig`               | `encodeCodepoint` return type `u3` (should be `u8` per zig-coding Rule 2)                                                                        |
| `hid_to_ascii.zig`       | No violations found                                                                                                                              |
| `c.zig`                  | No violations found                                                                                                                              |

### libitshell3-protocol (`modules/libitshell3-protocol/src/`)

| File                   | Violations present                                                                                                                                     |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `root.zig`             | Missing `//!` module-level doc comment entirely                                                                                                        |
| `capability.zig`       | Section numbers in doc comments (`Doc 02 §4`, `Doc 02 §5.1`); two compiler-verified tests (no behavioral assertion)                                    |
| `error.zig`            | Section numbers in doc comments (`doc 03 convention`, `doc 01 §6.2-6.3`)                                                                               |
| `cell.zig`             | Section number in doc comment (`doc 04 §4`); shift constants `underline_shift: u4`, `semantic_prompt_shift: u3` (should be `u8` per zig-coding Rule 2) |
| `header.zig`           | `payload_len` struct field (`_len` suffix); test names not following `"TypeOrFunction: description"` convention                                        |
| `transport.zig`        | `socket_path_len` struct field (`_len` suffix); test names not following convention                                                                    |
| `message_type.zig`     | Test names not following convention                                                                                                                    |
| `handshake.zig`        | Test names not following convention                                                                                                                    |
| `handshake_io.zig`     | Test names not following convention; `integration_test.zig`-style tests flat in `src/` (no `testing/spec/`)                                            |
| `connection.zig`       | Test names not following convention                                                                                                                    |
| `reader.zig`           | Test names not following convention                                                                                                                    |
| `writer.zig`           | Test names not following convention                                                                                                                    |
| `input.zig`            | Test names not following convention                                                                                                                    |
| `cell.zig`             | Test names not following convention                                                                                                                    |
| `json.zig`             | Test names not following convention                                                                                                                    |
| `frame_update.zig`     | Test names not following convention                                                                                                                    |
| `preedit.zig`          | Test names not following convention                                                                                                                    |
| `session.zig`          | Test names not following convention                                                                                                                    |
| `pane.zig`             | Test names not following convention                                                                                                                    |
| `auxiliary.zig`        | Test names not following convention                                                                                                                    |
| `error.zig`            | Test names not following convention                                                                                                                    |
| `socket_path.zig`      | Test names not following convention                                                                                                                    |
| `auth.zig`             | Test names not following convention                                                                                                                    |
| `integration_test.zig` | File is flat in `src/`; test names use `"integration: ..."` prefix (not the `"spec: topic — requirement"` format)                                      |

---

## Tasks

### Task 1: Missing `//!` Module-Level Docs

**Files:**

- `modules/libitshell3-protocol/src/root.zig` — add `//!` header

**Spec:** `docs/conventions/zig-documentation.md` Section 1 — every `root.zig`
MUST begin with `//!` module-level doc comments describing the module's purpose.

**Note:** `libitshell3-ime/src/root.zig` already has `//!`. Only the protocol
module's root file is missing it.

**Depends on:** None

**Verification:**

- `modules/libitshell3-protocol/src/root.zig` begins with at least one `//!`
  line describing the module's purpose
- No `//!` line references spec section numbers

---

### Task 2: Spec Section Number Removal

**Files:**

- `modules/libitshell3-ime/src/types.zig` (module doc + test comment)
- `modules/libitshell3-ime/src/engine.zig` (module doc)
- `modules/libitshell3-ime/src/hangul_engine.zig` (module doc + inline comment)
- `modules/libitshell3-ime/src/mock_engine.zig` (module doc)
- `modules/libitshell3-ime/src/hangul_engine_test.zig` (module doc)
- `modules/libitshell3-protocol/src/capability.zig` (doc comments)
- `modules/libitshell3-protocol/src/error.zig` (doc comments)
- `modules/libitshell3-protocol/src/cell.zig` (doc comment)

**Spec:** `docs/conventions/zig-documentation.md` Section 5 — do NOT embed spec
section numbers. Reference specs by document or topic name only.

**Specific instances to fix:**

- IME module docs: `Section 3.1–3.2`, `Section 3.5`, `Section 3.7`,
  `Section 3.8` — replace with topic-name references (e.g., "See the IME
  interface-contract spec for the canonical type definitions.")
- IME inline comment: `Section 3.2` in `hangul_engine.zig`
- IME test comment: `§02-types.md` in `types.zig` test block
- IME test module doc: `§3.1` (two occurrences) in `hangul_engine_test.zig`
- Protocol doc comments: `Doc 02 §4`, `Doc 02 §5.1`, `doc 03 convention`,
  `doc 01 §6.2-6.3`, `doc 04 §4` — replace with topic-name references (e.g.,
  "See the server-client-protocols capability spec for the canonical flag
  list.")

**Depends on:** None

**Verification:**

- No Zig source file in either module contains `§` followed by a digit
- No Zig source file contains `Section [0-9]` or `doc [0-9]` in comments
- Replacement references name the spec document or topic without a section
  number

---

### Task 3: `_len` Struct Field Renaming

**Files:**

- `modules/libitshell3-ime/src/hangul_engine.zig`
  - `committed_len` → `committed_length`
  - `preedit_len` → `preedit_length`
  - `prev_preedit_len` → `prev_preedit_length`
- `modules/libitshell3-protocol/src/header.zig`
  - `payload_len` → `payload_length`
- `modules/libitshell3-protocol/src/transport.zig`
  - `socket_path_len` → `socket_path_length`

All read sites for these fields must also be updated within the same module and
across any files that import and use these fields.

**Spec:** `docs/conventions/zig-naming.md` — the `_length` suffix is required.
No abbreviations in identifiers.

**Scope note for `payload_len`:** The field is on the `Header` struct, which is
used throughout the protocol library and referenced from `modules/libitshell3`
as well. The implementer must locate all read sites via a project-wide search
and update them atomically (build must pass at the end of the task).

**Depends on:** None

**Verification:**

- No struct field named `*_len` (with `_len` as a suffix, not `_length`) exists
  in either module's source
- All read sites compile: `zig build test` passes for both modules
- `getter` methods (`socketPath`, etc.) that compute slices from the renamed
  field are updated accordingly

---

### Task 4: Arbitrary-Width Integer Fixes

**Files:**

- `modules/libitshell3-ime/src/ucs4.zig`
  - `encodeCodepoint` return type `u3` → `u8`
  - All call sites that use `@as(u3, ...)` in test assertions updated to
    `@as(u8, ...)`
- `modules/libitshell3-protocol/src/cell.zig`
  - `underline_shift: u4 = 8` → `underline_shift: u8 = 8`
  - `semantic_prompt_shift: u3 = 2` → `semantic_prompt_shift: u8 = 2`

**Spec:** `docs/conventions/zig-coding.md`:

- Rule 2 (local variables / narrow-scope): prefer register-friendly widths
  (`u8`/`u16`/`u32`/`u64`). The return type of `encodeCodepoint` is a byte count
  (1–4); `u3` fits today but `u8` is the register-friendly choice for a function
  return type.
- Rule 1 (public constants): shift constants are public constants on a public
  struct. Use standard widths that are future-proof; `u4` and `u3` are
  unnecessarily tight for a shift value.

**Exceptions to preserve (do NOT change):**

- `_padding: u5 = 0` in `KeyEvent.Modifiers` — this is a packed struct field
  with exact bit-width required by the 1-byte layout (`packed struct(u8)`)
- `_reserved: u4 = 0` in `Flags` — packed struct field
- `enum(u2)` backing types — permitted per zig-coding.md Section 5 (enum backing
  types are encapsulated)
- Any other packed struct fields with explicit wire layout constraints

**Depends on:** None

**Verification:**

- `encodeCodepoint` signature is `pub fn encodeCodepoint(cp: u32, buf: []u8) u8`
- `cell.zig` shift constants are typed `u8`
- Test assertions updated where needed (e.g., `@as(u8, 1)` instead of
  `@as(u3, 1)`)
- Build passes; no implicit truncation warnings introduced

---

### Task 5: Compiler-Verified Test Removal

**Files:**

- `modules/libitshell3-protocol/src/capability.zig`
  - Remove `test "Capability enum values exist"` — only accesses enum variants
    via `_ = Enum.variant`; no behavioral assertion; the compiler enforces
    variant existence at all usage sites
  - Remove `test "RenderCapability enum values exist"` — same reason

**Spec:** `docs/conventions/zig-testing.md` — a test that only confirms "the
code does what the code does" is invalid. Field/declaration existence is
enforced by the compiler; a test that only checks existence tests the compiler,
not the spec.

**Note on `header.zig` size tests:** Tests like `"header size is 16"` and
`"flags
packed struct is exactly 1 byte"` use `@sizeOf` assertions, which ARE
behavioral — they catch regressions if fields are accidentally added or removed.
These should be kept; they verify a spec constraint (the 16-byte wire format),
not just compiler behavior.

**Depends on:** None

**Verification:**

- The two `capability.zig` tests no longer exist
- No remaining test in either module has `_ = SomeType.variant` or
  `_ = SomeVar.field` as its only substantive line

---

### Task 6: Test Directory Restructure

**Files:**

libitshell3-ime:

- Create `modules/libitshell3-ime/src/testing/` directory structure:
  - `testing/helpers.zig` (empty or stub, required by convention)
  - `testing/root.zig` (imports all mocks and spec tests)
  - `testing/mocks/mock_engine.zig` — move `mock_engine.zig` here (rename file,
    keep type name `MockImeEngine`)
  - `testing/spec/hangul_engine_spec_test.zig` — move `hangul_engine_test.zig`
    here (rename file)
- Update `root.zig` imports to use the new paths
- Update `build.zig` if module root source paths change

libitshell3-protocol:

- Create `modules/libitshell3-protocol/src/testing/` directory structure:
  - `testing/helpers.zig` (empty or stub)
  - `testing/root.zig` (imports all spec tests)
  - `testing/spec/integration_spec_test.zig` — move `integration_test.zig` here
    (rename file)
- Update `root.zig` imports
- Update `build.zig` if needed

**Spec:** `docs/conventions/zig-testing.md` — directory layout:
`<module>/src/testing/mocks/` for mock implementations,
`<module>/src/testing/spec/` for spec compliance tests. File naming:
`mock_*.zig` in `mocks/`, `*_spec_test.zig` in `spec/`.

**Classification guidance for the implementer:**

- `mock_engine.zig` is clearly a mock (implements the `ImeEngine` vtable
  interface for testing). It belongs in `testing/mocks/`.
- `hangul_engine_test.zig` tests real `HangulImeEngine` behavior against the
  v0.7 scenario matrix (spec-derived scenarios). It belongs in `testing/spec/`.
- `integration_test.zig` (protocol) tests end-to-end wire behavior — encode,
  frame, decode round-trips. It belongs in `testing/spec/`.
- Inline unit tests at the bottom of production source files stay where they
  are. They do NOT move to `testing/`.

**Depends on:** None (can run in parallel with other tasks; Task 7 test naming
should be sequenced after this task because renaming the files before renaming
the test strings avoids a double-edit)

**Verification:**

- `testing/mocks/mock_engine.zig` exists in libitshell3-ime
- `testing/spec/hangul_engine_spec_test.zig` exists in libitshell3-ime
- `testing/spec/integration_spec_test.zig` exists in libitshell3-protocol
- The original flat files (`mock_engine.zig`, `hangul_engine_test.zig`,
  `integration_test.zig`) are removed from `src/`
- `root.zig` in each module imports from the new paths
- `testing/root.zig` in each module imports and re-exports all testing files,
  ending with `test { std.testing.refAllDecls(@This()); }`
- `zig build test` passes for both modules with all previously passing tests
  still discovered and passing

---

### Task 7: Test Naming

**Files:**

libitshell3-ime:

- `modules/libitshell3-ime/src/hangul_engine_test.zig` (or its new path
  `testing/spec/hangul_engine_spec_test.zig` after Task 6)
- Inline tests in `types.zig`, `engine.zig`, `mock_engine.zig`,
  `hangul_engine.zig`, `hid_to_ascii.zig`, `ucs4.zig`

libitshell3-protocol:

- `integration_test.zig` (or its new path
  `testing/spec/integration_spec_test.zig` after Task 6)
- Inline tests in all other protocol source files (see File Inventory above)

**Spec:**

- `docs/conventions/zig-naming.md` and `docs/conventions/zig-testing.md`:
  - Inline tests: `"FunctionOrType.method: description"` or
    `"functionName: description"`
  - Spec compliance tests: `"spec: topic — requirement"`

**Inline test naming — specific guidance:**

Current inline tests generally lack the `FunctionOrType:` prefix. Examples
needing fixes:

- `"header size is 16"` → `"Header: size is 16 bytes"`
- `"flags packed struct is exactly 1 byte"` →
  `"Flags: packed struct is exactly 1 byte"`
- `"header encode/decode round-trip"` →
  `"Header.encode/Header.decode: round-trip"`
- `"BufferTransport write then read"` → `"BufferTransport: write then read"`
- `"hidToAscii: letters unshifted"` — already correct (has function prefix)
- `"encodeCodepoint: ASCII"` — already correct
- `"KeyEvent: hasCompositionBreakingModifier"` — already correct
- `"ImeEngine: vtable dispatch works via MockImeEngine"` — already correct

**Spec test naming — specific guidance:**

- `hangul_engine_test.zig`/`hangul_engine_spec_test.zig` uses a category
  shorthand `"A1: direct_printable_lowercase"` — these derive from the v0.7
  scenario matrix (a spec document). Rename to
  `"spec: direct input — printable lowercase letter"`,
  `"spec: Korean composition — initial consonant"`, etc.
- `integration_test.zig`/`integration_spec_test.zig` uses `"integration: ..."`
  prefix — rename to `"spec: ..."` format:
  `"spec: frame encoding — ClientHello round-trip"`,
  `"spec: connection lifecycle — full handshake over socketpair"`, etc.

**Depends on:** Task 6 (file locations must be stable before renaming test
strings)

**Verification:**

- All inline tests match `"TypeOrFunction[.method]: description"` (the function
  or type under test appears before the colon)
- All spec compliance tests (in `testing/spec/`) match
  `"spec: topic — requirement"`
- No test name is a bare description without a qualifying prefix
- `zig build test` passes for both modules

---

## Dependency Graph

```
Task 1 (module docs)        — independent
Task 2 (section numbers)    — independent
Task 3 (_len rename)        — independent
Task 4 (integer widths)     — independent
Task 5 (compiler tests)     — independent
Task 6 (test dir structure) — independent; must complete before Task 7
Task 7 (test naming)        — depends on Task 6
```

Tasks 1–6 are all independent and can run in parallel. Task 7 should be
sequenced after Task 6 to avoid editing files that are about to be moved.

## Summary

| Task                           | Module(s)      | Convention Ref                 |
| ------------------------------ | -------------- | ------------------------------ |
| 1. Missing `//!` module doc    | protocol       | zig-documentation §1           |
| 2. Spec section number removal | ime + protocol | zig-documentation §5           |
| 3. `_len` → `_length` rename   | ime + protocol | zig-naming (no abbrev.)        |
| 4. Arbitrary-width integers    | ime + protocol | zig-coding Rules 1, 2          |
| 5. Compiler-verified tests     | protocol       | zig-testing (what NOT to test) |
| 6. Test directory restructure  | ime + protocol | zig-testing (dir layout)       |
| 7. Test naming                 | ime + protocol | zig-naming + zig-testing       |
