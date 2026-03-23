# Migrate HangulImeEngine Internals to In-Source Documentation

- **Date**: 2026-03-23
- **Raised by**: owner
- **Severity**: HIGH
- **Affected docs**: `behavior/draft/v1.0-r2/10-hangul-engine-internals.md`,
  `interface-contract/draft/v1.0-r10/02-types.md`
- **Status**: open

---

## Problem

`10-hangul-engine-internals.md` describes implementation details of
`HangulImeEngine` — struct fields, buffer layout, libhangul API call sequences,
keyboard ID mapping, setActiveInputMethod step sequences, and Backspace jamo
decomposition. Now that the implementation exists at
`modules/libitshell3-ime/src/hangul_engine.zig`, maintaining a parallel design
doc creates a DRY burden and has already caused drift.

### Verified Drift (implementation predates docs — Mar 9 vs Mar 14+)

| # | Aspect                  | Doc says                                               | Impl does                                                 | Which is correct                                                                                             | Evidence                                                                                             |
| - | ----------------------- | ------------------------------------------------------ | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| 1 | `prev_preedit_buf`      | Content-based dirty tracking with `[64]u8` buffer      | Length-only + "non-null→non-null always changed" shortcut | **Impl** — libhangul never leaves preedit unchanged after consuming a key; content comparison is unnecessary | Test N4 in `hangul_engine_test.zig` proves `preedit_changed = true` for same-byte-length transitions |
| 2 | `init()` signature      | `init(allocator: Allocator, input_method: []const u8)` | `init(input_method: []const u8)` — no allocator           | **Impl** — all buffers are fixed-size, no heap allocation needed                                             |                                                                                                      |
| 3 | Buffer init             | `= undefined`                                          | `= @splat(0)`                                             | **Impl** — zero-init is safer for debugging                                                                  |                                                                                                      |
| 4 | `isPrintablePosition()` | Split range excluding 0x28–0x2C                        | Continuous range 0x04–0x38 including 0x28–0x2C            | **Doc** — latent bug in impl, but not runtime because `hidToAscii()` is the actual gate                      | Test in `types.zig` proves `isPrintablePosition()` returns wrong result for gap keycodes             |

## Proposed Change

### Primary: Migrate doc 10 content to `hangul_engine.zig` doc comments

Replace the standalone design doc with in-source documentation on the struct,
fields, and functions in `hangul_engine.zig`. This is the canonical location
where implementors and maintainers will look.

Content to migrate as doc comments:

| Doc 10 Section                  | Target in `hangul_engine.zig`                    |
| ------------------------------- | ------------------------------------------------ |
| §1 Struct fields                | `///` on `HangulImeEngine` struct and each field |
| §1.2 EngineMode                 | `///` on `EngineMode` enum                       |
| §2 Keyboard ID mapping          | `///` on `libhangulKeyboardId()`                 |
| §2.1 Registry table             | `///` on the mapping table constant              |
| §3 Buffer layout/sizing         | `///` on buffer fields                           |
| §4 setActiveInputMethod steps   | `///` on `setActiveInputMethodImpl()`            |
| §5 processKeyImpl note          | `///` on `processKeyImpl()`                      |
| §6 Backspace/jamo decomposition | `///` on `handleBackspace()`                     |
| §7 Session persistence          | `///` on `init()`                                |

### Secondary: Fix latent `isPrintablePosition()` bug

Fix `types.zig` line 50 to use the split range per spec:

```zig
return (self.hid_keycode >= 0x04 and self.hid_keycode <= 0x27) or
       (self.hid_keycode >= 0x2D and self.hid_keycode <= 0x38);
```

Fix existing test at `types.zig:142-149` (Enter assertion should be `false`).

### Tertiary: Retire doc 10 entirely

After migration, `10-hangul-engine-internals.md` should be retired:

- Implementation details → source doc comments in `hangul_engine.zig`
- Design rationale §2.1 (engine-owned mapping) → ADR-00042 (already created)
- Design rationale §3.1 (buffer sizing) → doc comment on buffer fields (too
  trivial for an ADR)
- Dirty tracking rationale → ADR-00041 (already created)

No slimmed-down doc 10 needed — all content has a better home.

## Owner Decision

Left to designers for resolution.

## Resolution

_(To be filled when resolved.)_
