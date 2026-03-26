# 00058. Fixed-Size Inline Buffers for Session Fields

- Date: 2026-03-26
- Status: Accepted

## Context

The design spec (`daemon-architecture/impl-constraints/state-and-types.md`)
defines Session string fields as Zig slices:

```zig
name: []const u8,
active_input_method: []const u8,
active_keyboard_layout: []const u8,
current_preedit: ?[]const u8,
```

The implementation uses fixed-size inline buffers with separate length fields:

```zig
name: [64]u8,
name_length: u8,
active_input_method: [32]u8,
active_input_method_length: u8,
active_keyboard_layout: [32]u8,
active_keyboard_layout_length: u8,
```

This divergence was discovered during Plan 5 (IME Integration) verification when
no ADR, CTR, or design resolution justified the difference. Per project
convention, the spec is authoritative unless an explicit decision document says
otherwise.

However, the inline buffer pattern has substantial technical merit in this
project's architecture:

- **ADR 00052** places SessionManager in static (.bss) allocation. Session and
  SessionEntry are stored by value in `[64]?SessionEntry`. Slice fields would
  require heap allocation for the pointed-to data, reintroducing the allocator
  dependency that ADR 00052 explicitly eliminated.
- Session string fields have natural maximum lengths: `name` (64 bytes),
  `active_input_method` / `active_keyboard_layout` (32 bytes — sufficient for
  identifiers like `"korean_2set"`, `"qwerty"`), `preedit_buf` (64 bytes — one
  Korean syllable is 3 UTF-8 bytes; 64 bytes covers ~21 characters, well beyond
  any composition).
- The daemon is single-threaded (kqueue event loop). There is no concurrent
  access to Session fields. Fixed-size structs are trivially copyable and have
  no lifetime concerns.

Alternatives considered:

- **Use slices as spec says**: Requires an allocator for Session.init() and
  careful free in deinit(). Contradicts ADR 00052's goal of eliminating
  allocator dependency from core types. Introduces use-after-free risk if a
  slice outlives its backing allocation.
- **Use sentinel-terminated strings** (`[:0]const u8`): Still requires heap
  allocation for the backing buffer. Same problems as slices.
- **Use `std.BoundedArray`**: Essentially the same as inline buffer + len, but
  with a generic wrapper. Adds indirection without meaningful benefit for
  fixed-capacity fields.

## Decision

Session and SessionEntry fields that represent bounded strings use **fixed-size
inline buffers** with a separate length field (`[N]u8` + `u8 len`). Getter
methods return `[]const u8` slices into the inline buffer for read access.

Specific field sizes:

| Field                    | Buffer size | Rationale                              |
| ------------------------ | ----------- | -------------------------------------- |
| `name`                   | 64 bytes    | Session name — generous for display    |
| `active_input_method`    | 32 bytes    | Identifier string (`"korean_2set"`)    |
| `active_keyboard_layout` | 32 bytes    | Identifier string (`"qwerty"`)         |
| `preedit_buf`            | 64 bytes    | Max preedit overlay text (UTF-8)       |
| `title` (Pane)           | 256 bytes   | Terminal title (OSC 0/2)               |
| `cwd` (Pane)             | 4096 bytes  | Current working directory (`PATH_MAX`) |

The design spec's `impl-constraints/state-and-types.md` is a transient
implementer reference artifact (per its own header). It will be updated to
reflect the inline buffer representation as part of the next spec revision or
deleted per its own lifecycle rule.

This decision complements ADR 00052: static allocation determines WHERE the
struct lives (.bss); this ADR determines HOW string fields are stored within it
(inline, not heap-pointed).

## Consequences

**What gets easier:**

- No allocator dependency for Session — init/deinit remain trivial.
- No lifetime management — no dangling pointers, no use-after-free.
- Predictable memory layout — SessionManager size is fully determined at compile
  time.
- Value-copyable — Sessions can be moved/copied with `@memcpy`.
- No allocation failure — string assignment cannot OOM.

**What gets harder:**

- String lengths are capped — names longer than 64 bytes are truncated. This is
  acceptable for all current fields (identifiers, titles, paths have natural
  limits).
- Each Session is larger than it would be with slices — the full buffer is
  allocated even for short strings. Acceptable given ADR 00052's static model
  (memory is allocated regardless).
- Adding a new string field increases SessionEntry size — must verify the total
  remains reasonable for the `[64]?SessionEntry` array.

**New obligations:**

- All Session string fields must have documented maximum sizes (see table
  above).
- Getter methods (e.g., `getName()`, `getActiveInputMethod()`) return
  `[]const
  u8` slices for API ergonomics — callers should not access raw
  buffers directly.
- The spec (`impl-constraints/state-and-types.md`) must be updated or deleted to
  reflect this representation.
