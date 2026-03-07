# Build System and Licensing

## Building libhangul

### Source

```bash
git clone https://github.com/libhangul/libhangul.git
cd libhangul
```

### Minimal Build (No External Keyboards, No Hanja)

For libitshell3-ime, we need only the core composition engine — no XML keyboard loading, no hanja dictionary. This means:

- **No Expat dependency** (XML parsing only needed for `ENABLE_EXTERNAL_KEYBOARDS`)
- **No data files** (hanja dictionaries not needed for v1)
- **No gettext/intl** (internationalization not needed)

#### Source Files Needed

| File | Purpose | Size |
|------|---------|------|
| `hangul/hangulctype.c` | Character classification (is_choseong, is_jungseong, etc.) | ~200 lines |
| `hangul/hangulinputcontext.c` | Core composition engine (process, backspace, flush) | ~1200 lines |
| `hangul/hangulkeyboard.c` | Keyboard layout tables and mapping | ~1500 lines |
| `hangul/hanja.c` | Hanja dictionary lookup (can stub out) | ~400 lines |

#### Headers Needed

| File | Purpose |
|------|---------|
| `hangul/hangul.h` | Public API header |
| `hangul/hangulkeyboard.h` | Internal: keyboard table data (all 9 layouts compiled in) |
| `hangul/hangulinternals.h` | Internal function declarations |
| `hangul/hangul-gettext.h` | i18n macros (can be stubbed as no-ops) |

### Building with Zig

Since libitshell3-ime is a Zig library, we use Zig's build system to compile libhangul's C sources directly:

```zig
// build.zig (sketch)
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Compile libhangul C sources
    const libhangul = b.addStaticLibrary(.{
        .name = "hangul",
        .target = target,
        .optimize = optimize,
    });

    libhangul.addCSourceFiles(.{
        .files = &.{
            "deps/libhangul/hangul/hangulctype.c",
            "deps/libhangul/hangul/hangulinputcontext.c",
            "deps/libhangul/hangul/hangulkeyboard.c",
            "deps/libhangul/hangul/hanja.c",
        },
        .flags = &.{
            "-std=c99",
            "-DHAVE_CONFIG_H=0",        // Skip autotools config
            "-DENABLE_EXTERNAL_KEYBOARDS=0",  // No XML keyboard loading
        },
    });

    libhangul.addIncludePath(.{ .cwd_relative = "deps/libhangul" });
    libhangul.linkLibC();

    // Main libitshell3-ime library
    const lib = b.addStaticLibrary(.{
        .name = "itshell3-ime",
        .root_source_file = .{ .cwd_relative = "src/ime.zig" },
        .target = target,
        .optimize = optimize,
    });

    lib.addIncludePath(.{ .cwd_relative = "deps/libhangul/hangul" });
    lib.linkLibrary(libhangul);

    b.installArtifact(lib);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "src/ime.zig" },
        .target = target,
        .optimize = optimize,
    });
    tests.addIncludePath(.{ .cwd_relative = "deps/libhangul/hangul" });
    tests.linkLibrary(libhangul);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
```

### Zig @cImport for libhangul

```zig
const c = @cImport({
    @cInclude("hangul.h");
});

// Usage:
const hic = c.hangul_ic_new("2") orelse return error.InitFailed;
defer c.hangul_ic_delete(hic);

const consumed = c.hangul_ic_process(hic, 'r');
if (consumed) {
    const preedit = c.hangul_ic_get_preedit_string(hic);
    // preedit is *const u32 (ucschar*), null-terminated
}
```

---

## Directory Structure

```
libitshell3-ime/
├── build.zig
├── src/
│   ├── ime.zig                 # Main module, public API
│   ├── context.zig             # ImeContext implementation
│   ├── layout_mapper.zig       # HID keycode → ASCII mapping
│   ├── ucs4.zig                # UCS-4 → UTF-8 conversion
│   └── c_api.zig               # C header export (itshell3_ime.h)
├── deps/
│   └── libhangul/              # git submodule
│       └── hangul/
│           ├── hangul.h
│           ├── hangulctype.c
│           ├── hangulinputcontext.c
│           ├── hangulkeyboard.c
│           ├── hanja.c
│           └── ... (internal headers)
├── tests/
│   ├── composition_test.zig    # Korean composition roundtrips
│   ├── backspace_test.zig      # Jamo-level backspace
│   ├── modifier_test.zig       # Ctrl/Alt during composition
│   ├── mode_switch_test.zig    # English ↔ Korean toggle
│   └── layout_test.zig         # HID → ASCII mapping
└── docs/                       # This directory
```

---

## Licensing

### libhangul: LGPL-2.1-or-later

The LGPL-2.1 license allows:

1. **Dynamic linking**: Your code can use any license. You must allow users to replace the libhangul shared library.
2. **Static linking**: Your code can use any license, BUT you must provide one of:
   - (a) The libhangul source + your application's object files (`.o`) so users can relink
   - (b) A written offer to provide the above for 3 years

### Our Approach: Static Linking

We statically link libhangul into libitshell3-ime because:
- Simpler deployment (no separate .dylib/.so to ship)
- Zig's build system compiles C sources directly
- Single artifact for libitshell3 to link against

### LGPL-2.1 Compliance for Static Linking

To comply with LGPL-2.1 Section 6, we must:

1. **Ship libhangul source**: Include as a git submodule. The source is publicly available at https://github.com/libhangul/libhangul.

2. **Provide object files or linkable form**: Since libitshell3-ime is itself a library (not an end-user application), the LGPL relinkability obligation passes through to downstream consumers. We document this clearly.

3. **Prominent notice**: Include LGPL-2.1 license text in the distribution.

### License Headers

```
libitshell3-ime: [chosen license]
Contains libhangul, Copyright (C) libhangul contributors, LGPL-2.1-or-later
See deps/libhangul/COPYING for the full LGPL-2.1 license text.
```

### Alternative: LGPL-3.0 Compliance

Since libhangul's license is "LGPL-2.1 or later", we could opt to comply under LGPL-3.0 instead, which has clearer provisions for static linking in modern build systems. The practical difference is minimal for our use case.

---

## Testing Strategy

### Unit Tests (Pure, No OS Resources)

| Test | What It Verifies |
|------|-----------------|
| Composition roundtrip | Type "rksk" → committed "간" + preedit "ㄱ" |
| Backspace through syllable | "한" → BS → "하" → BS → "ㅎ" → BS → empty |
| Compound jongseong | Type "rkfr" → preedit with compound jong ㄺ |
| Jamo reassignment | Type "rks" + "k" → commit "간" + preedit "나"... wait: "rks" = 간, then 'k' = ㅏ → commit "가" + preedit "나" (jong ㄴ reassigned as cho of next syllable). Actually: r=ㄱ, k=ㅏ (가), s=ㄴ→jong (간), k=ㅏ → reassign: commit 가, new cho ㄴ + jung ㅏ = 나. So preedit "나". |
| Modifier flush | Preedit "하" + Ctrl+C → committed "하" + forward Ctrl+C |
| Arrow key flush | Preedit "한" + → → committed "한" + forward right arrow |
| Enter flush | Preedit "ㅎ" + Enter → committed "ㅎ" + forward Enter |
| Mode toggle | Korean mode, preedit "하" → toggle → committed "하", mode=English |
| English passthrough | English mode, 'a' → committed "a", no preedit |
| Layout switch | Switch "2" → "3f" → verify different key mapping |
| Empty backspace | Empty composition + Backspace → forward backspace |
| Double consonant | Type "rr" with COMBI_ON_DOUBLE_STROKE → preedit "ㄲ" |
| UCS-4 to UTF-8 | 한 (U+D55C) → 0xED 0x95 0x9C |
| HID to ASCII | HID 0x04 → 'a', HID 0x04+shift → 'A' |

### Integration Tests

| Test | What It Verifies |
|------|-----------------|
| Full key sequence | Simulate typing "안녕하세요" → verify PTY receives correct UTF-8 |
| Mixed Korean/English | Korean "한" → toggle → English "abc" → toggle → Korean "글" |
| Rapid input | 100 keystrokes/second → no dropped or reordered events |
| Concurrent panes | Two panes with independent IME state |

All tests are pure Zig unit tests — no GUI, no OS IME, no display needed. 100% CI-compatible.
