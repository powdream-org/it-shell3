# Zig Coding Conventions

General coding rules for all Zig source code in the it-shell3 project. These
conventions complement the
[Zig style guide](https://ziglang.org/documentation/master/#Style-Guide) and add
project-specific rules.

## Integer Types

Zig supports arbitrary-width integers (`u3`, `u5`, `u21`, etc.). Use them
intentionally — the choice of bit width should be a deliberate design decision,
not an accident of "what fits today."

### 1. Public symbols — tight bit width for safety

Public constants, struct fields, function parameters, and return types SHOULD
use the tightest bit width that covers the **future-proof valid range** — not
just the current value.

- `MAX_PANES: u8 = 16` — u8 covers the current 16 and any reasonable future
  increase, without risk of silent overflow
- `MAX_TREE_DEPTH: u8 = 4` — same reasoning (spec could change to 16, u3 cannot
  hold that)
- Packed struct fields: use the exact bit width required by the wire/hardware
  layout

**Anti-pattern:** sizing the type to exactly fit the current value
(`MAX_TREE_DEPTH: u3 = 4` — breaks if spec changes to 16).

### 2. Local variables — prefer register-friendly widths

Local variables in narrow scope (a few lines) SHOULD prefer standard register
widths (`u8`, `u16`, `u32`, `u64`) when there is no meaningful benefit from a
tighter type.

**Wrong:**

```zig
const bit_idx: u6 = @intCast(cursor_row % 64);
```

**Right:**

```zig
const bit_idx: u8 = @intCast(cursor_row % 64);
```

Register-aligned widths avoid unnecessary `@intCast` chains and match CPU
instruction argument sizes.

### 3. Fixed-size array indices — match array capacity

Array index types SHOULD match the array's capacity. This provides compile-time
bounds safety — Zig detects out-of-range indexing in Debug and ReleaseSafe
modes.

```zig
const flags: [8]Flag = ...;
var idx: u3 = 0;  // u3 max = 7 = array size - 1
```

This follows ghostty's `FlagStack` pattern where the index type inherently
prevents out-of-bounds access.

### 4. Loop counters — prefer u32 or usize

Loop counters (`while`, `for` iteration indices) SHOULD use `u32` or `usize`.

```zig
// Wrong
var i: u5 = 0;
while (i < MAX_PANES) : (i += 1) { ... }

// Right
var i: u32 = 0;
while (i < MAX_PANES) : (i += 1) { ... }
```

**Exception:** When the loop body passes the counter to APIs that expect a
narrower type, every iteration would require `@intCast`. In this case, declare
the counter in the target type to avoid per-iteration casts.

```zig
const MAX_CLIENTS: u16 = 64;
slots: [MAX_CLIENTS]ClientState,

// Without exception — @intCast on every iteration
var i: u32 = 0;
while (i < MAX_CLIENTS) : (i += 1) {
    const idx: u16 = @intCast(i);  // required because callback takes u16
    callback(context, &self.slots[idx], idx);
}

// With exception — counter matches the API boundary type
var i: u16 = 0;
while (i < MAX_CLIENTS) : (i += 1) {
    callback(context, &self.slots[i], i);
}
```

### 5. Sparse discrete values — use enum, not bare integer

When a function returns a small set of discrete values, use an `enum` with an
explicit backing type instead of a bare integer. The enum provides semantic
meaning; the backing type is an implementation detail.

**Wrong:**

```zig
fn codepointWidth(cp: u21) u2 {
    // returns 1 or 2
}
```

**Right:**

```zig
const CharWidth = enum(u2) { narrow = 1, wide = 2 };

fn codepointWidth(cp: u21) CharWidth {
    // returns .narrow or .wide
}
```

Arbitrary-width backing types are allowed on enums — the `u2` is encapsulated by
the enum and does not leak into the calling code.

### 6. Derived constants — comptime over hardcoded

When a constant can be derived from another constant, **always** derive it at
comptime. Do not hardcode values that have a mathematical relationship — a
hardcoded value can silently fall out of sync when the source constant changes.

**Wrong:**

```zig
pub const MAX_PANES: u8 = 16;
pub const MAX_TREE_NODES: u8 = 31;  // hardcoded 16*2-1
pub const MAX_TREE_DEPTH: u8 = 4;   // hardcoded log2(16)
```

**Right:**

```zig
pub const MAX_PANES: u8 = 16;
pub const MAX_TREE_NODES: u8 = MAX_PANES * 2 - 1;
pub const MAX_TREE_DEPTH: u8 = std.math.log2_int(u8, MAX_PANES);
```

Zig evaluates these at comptime with zero runtime cost. Changing `MAX_PANES`
automatically propagates to all derived constants.

### Summary

| Context                                     | Rule                                                                | Example                             |
| ------------------------------------------- | ------------------------------------------------------------------- | ----------------------------------- |
| Public symbol (const, field, param, return) | Tight but future-proof width                                        | `MAX_PANES: u8 = 16`                |
| Local variable (narrow scope)               | Register-friendly: u8/u16/u32/u64                                   | `const bit_idx: u8 = ...`           |
| Fixed-size array index                      | Match array capacity                                                | `var idx: u3` for `[8]T`            |
| Loop counter                                | Prefer u32/usize; narrower OK if it avoids per-iteration `@intCast` | `var i: u32 = 0`                    |
| Sparse discrete return                      | enum(uN)                                                            | `enum(u2) { narrow = 1, wide = 2 }` |
| Packed struct field                         | Exact bit width per layout                                          | `packed struct(u8) { ... }`         |
| Unicode codepoint                           | u21 (Zig std convention)                                            | `fn encode(cp: u21) ...`            |
