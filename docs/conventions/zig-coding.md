# Zig Coding Conventions

General coding rules for all Zig source code in the it-shell3 project. These
conventions complement the
[Zig style guide](https://ziglang.org/documentation/master/#Style-Guide) and add
project-specific rules.

## Integer Types

Use **standard-width integers** (`u8`, `u16`, `u32`, `u64`, `i8`, `i16`, `i32`,
`i64`) for all variables, fields, parameters, and constants.

**Do NOT use arbitrary-width integers** (`u3`, `u4`, `u5`, `u19`, etc.) unless
the value is a **wire protocol or hardware-level definition** where the bit
width is semantically mandated by an external specification.

### Allowed uses of arbitrary-width integers

- **Packed struct fields** that map to a wire protocol or hardware register
  layout (e.g., `packed struct(u8) { ctrl: bool, alt: bool, ... }`)
- **Extern struct fields** that must match a C ABI or binary format
- **Zig standard library conventions** — `u21` for Unicode codepoints (used by
  `std.unicode` and throughout the Zig ecosystem)

### NOT allowed

- Constants that happen to fit in a smaller type (e.g., `MAX_TREE_DEPTH: u3 = 4`
  — use `u8` instead)
- Loop counters, array indices, or function parameters sized to "just fit" the
  current value range
- Enum backing types chosen to minimize bits (use the default or a standard
  width)

### Examples

**Wrong — intermediate local with no reason for u6:**

```zig
const bit_idx: u6 = @intCast(cursor_row % 64);
```

**Right — use u8 for a local variable:**

```zig
const bit_idx: u8 = @intCast(cursor_row % 64);
```

**Wrong — u2 return for discrete semantic values:**

```zig
fn codepointWidth(cp: u21) u2 {
    // returns 1 or 2
}
```

**Right — use an enum for discrete semantic values:**

```zig
const CharWidth = enum { narrow, wide };

fn codepointWidth(cp: u21) CharWidth {
    // returns .narrow or .wide
}
```

### Rationale

Arbitrary-width integers create subtle bugs when the value range changes:

- `MAX_TREE_DEPTH: u3 = 4` cannot hold the spec's maximum of 16 (which requires
  at least `u5`). A `u8` would have prevented this class of bug entirely.
- `PaneSlot: u4` (max 15) breaks if MAX_PANES ever exceeds 16. A `u8` removes
  the coupling between the type width and the current constant value.

Standard-width integers also produce more predictable behavior at the CPU
register level — `u3` and `u8` both occupy at least one byte in memory, so the
space "savings" of arbitrary widths is illusory outside of packed structs.
