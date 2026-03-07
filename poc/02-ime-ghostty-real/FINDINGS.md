# Real ghostty Integration PoC — Detailed Findings

> **Date**: 2026-03-04
> **PoC files**: `poc-ghostty-real.m`, `build-poc.sh`, `minimal_test.m`
> **Pre-built library**: it-shell v1's `GhosttyKit.xcframework/macos-arm64_x86_64/libghostty.a`

---

## 1. ghostty Headless Initialization (macOS)

### 1.1 NSApplication is mandatory

```objc
[NSApplication sharedApplication];
[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
```

Without this, ghostty's Metal renderer cannot initialize. `NSApplicationActivationPolicyAccessory` prevents dock icon and menu bar from appearing.

**Source**: `poc-ghostty-real.m:1117-1119`

### 1.2 Config isolation required

ghostty's `ghostty_config_load_default_files()` reads `~/.config/ghostty/config`. The user's real config may contain settings that break headless operation (e.g., font paths, keybindings).

**Solution**: Redirect `HOME` and `XDG_CONFIG_HOME` to temp directories before loading config.

```objc
setenv("HOME", tmpHome.UTF8String, 1);
setenv("XDG_CONFIG_HOME", xdgConfigDir.UTF8String, 1);
```

**Source**: `poc-ghostty-real.m:417-423`

### 1.3 `window-vsync = false` is critical

Default `window-vsync = true` calls `CVDisplayLinkCreateWithActiveCGDisplays()` which fails in CLI context without a display link. This causes `ghostty_surface_new()` to return NULL.

**Fix**: Write `window-vsync = false` to the isolated config file before calling `ghostty_config_load_default_files()`.

**Source**: `poc-ghostty-real.m:414-415`

### 1.4 NSWindow + NSView required for Metal

ghostty's Metal renderer (`Metal.zig`) sets `view.layer = metalLayer` and `view.wantsLayer = true` internally. The surface needs a real NSView in a real NSWindow.

```objc
NSWindow *window = [[NSWindow alloc]
    initWithContentRect:frame
              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                         NSWindowStyleMaskResizable)
                backing:NSBackingStoreBuffered
                  defer:NO];
NSView *view = [[NSView alloc] initWithFrame:frame];
[window setContentView:view];
[window orderBack:nil];  // Connect to window server
```

**Critical**: Do NOT pre-set `wantsLayer` or provide a custom layer — ghostty creates its own IOSurfaceLayer.

**Source**: `poc-ghostty-real.m:462-473`

---

## 2. ghostty C API — Initialization Sequence

### 2.1 Full initialization flow

```
ghostty_init(0, NULL)
  → ghostty_config_new()
  → ghostty_config_load_default_files(config)
  → ghostty_config_finalize(config)
  → ghostty_app_new(&runtime_config, config)
  → ghostty_surface_new(app, &surface_config)
  → ghostty_surface_set_size(surface, width, height)
  → ghostty_surface_set_focus(surface, true)
  → ghostty_app_tick(app) × 5  // let child process start
```

### 2.2 Runtime config — stub callbacks

All 6 callbacks are mandatory but can be no-ops:

```c
ghostty_runtime_config_s runtime_cfg = {
    .userdata = NULL,
    .supports_selection_clipboard = false,
    .wakeup_cb = stub_wakeup,           // void (*)(void*)
    .action_cb = stub_action,           // bool (*)(app, target, action)
    .read_clipboard_cb = stub_read_clipboard,
    .confirm_read_clipboard_cb = stub_confirm_read_clipboard,
    .write_clipboard_cb = stub_write_clipboard,
    .close_surface_cb = stub_close_surface,
};
```

**Source**: `poc-ghostty-real.m:359-369, 439-448`

### 2.3 Surface config fields

```c
ghostty_surface_config_s surface_cfg = ghostty_surface_config_new();
surface_cfg.platform_tag = GHOSTTY_PLATFORM_MACOS;
surface_cfg.platform.macos.nsview = (__bridge void *)view;
surface_cfg.userdata = NULL;
surface_cfg.scale_factor = 1.0;
surface_cfg.font_size = 0;            // 0 = use default
surface_cfg.working_directory = NULL;  // NULL = use cwd
surface_cfg.command = "/bin/cat";      // child process command
surface_cfg.wait_after_command = false;
```

**Key finding**: `command` field allows overriding the shell. `/bin/cat` gives deterministic echo behavior for testing.

**Source**: `poc-ghostty-real.m:475-484`

### 2.4 `ghostty_app_tick()` for I/O processing

After sending key events, ghostty needs to process I/O (write to PTY, read echo from child, update terminal state).

```c
static void ghostty_ctx_tick(GhosttyContext* ctx, int count) {
    for (int i = 0; i < count; i++) {
        ghostty_app_tick(ctx->app);
        usleep(10000); // 10ms
    }
}
```

Typical usage: 3 ticks after each key event, 5 ticks after flush (child may need more time to echo multi-byte Korean).

**Source**: `poc-ghostty-real.m:517-522`

---

## 3. ghostty C API — Key Input

### 3.1 Committed text: `ghostty_surface_key()` with `.text`

```c
ghostty_input_key_s ev = {
    .action = GHOSTTY_ACTION_PRESS,
    .mods = GHOSTTY_MODS_NONE,
    .consumed_mods = GHOSTTY_MODS_NONE,
    .keycode = GHOSTTY_KEY_UNIDENTIFIED,  // or actual key
    .text = committed_utf8,                // UTF-8 string
    .unshifted_codepoint = 0,
    .composing = false,                    // NEVER true for committed
};
ghostty_surface_key(surface, ev);

// Must also send RELEASE (no text on release)
ev.action = GHOSTTY_ACTION_RELEASE;
ev.text = NULL;
ghostty_surface_key(surface, ev);
```

**Critical rule**: NEVER use `ghostty_surface_text()` for IME output. It triggers bracketed paste (`\e[200~...\e[201~`) which causes Korean doubling bug. This was discovered in it-shell v1.

**Source**: `poc-ghostty-real.m:592-608`

### 3.2 Forwarded special keys: `ghostty_surface_key()` without text

```c
ghostty_input_key_s ev = {
    .action = GHOSTTY_ACTION_PRESS,
    .mods = mods,                          // CTRL, ALT, SHIFT, SUPER
    .consumed_mods = GHOSTTY_MODS_NONE,
    .keycode = ghostty_key_enum,           // e.g. GHOSTTY_KEY_ENTER
    .text = NULL,                          // NULL for special keys
    .unshifted_codepoint = 0,
    .composing = false,
};
```

**Exception**: Space is forwarded with `.text = " "` and `.unshifted_codepoint = ' '`.

**Source**: `poc-ghostty-real.m:624-656`

### 3.3 Preedit overlay: `ghostty_surface_preedit()`

```c
// Set preedit
ghostty_surface_preedit(surface, utf8_text, (uintptr_t)strlen(utf8_text));

// Clear preedit (MUST be explicit — ghostty does NOT auto-clear)
ghostty_surface_preedit(surface, NULL, 0);
```

**Source**: `poc-ghostty-real.m:612-620`

### 3.4 HID-to-ghostty key mapping

Letters use offset pattern:
```c
if (hid >= 0x04 && hid <= 0x1D) {
    return GHOSTTY_KEY_A + (hid - 0x04);  // A=0x04 → GHOSTTY_KEY_A
}
```

Special keys mapped individually:
| HID | ghostty enum |
|-----|-------------|
| 0x28 | `GHOSTTY_KEY_ENTER` |
| 0x29 | `GHOSTTY_KEY_ESCAPE` |
| 0x2A | `GHOSTTY_KEY_BACKSPACE` |
| 0x2B | `GHOSTTY_KEY_TAB` |
| 0x2C | `GHOSTTY_KEY_SPACE` |
| 0x4F | `GHOSTTY_KEY_ARROW_RIGHT` |
| 0x50 | `GHOSTTY_KEY_ARROW_LEFT` |
| 0x51 | `GHOSTTY_KEY_ARROW_DOWN` |
| 0x52 | `GHOSTTY_KEY_ARROW_UP` |
| 0x4A | `GHOSTTY_KEY_HOME` |

**Source**: `poc-ghostty-real.m:122-141`

---

## 4. ghostty C API — Terminal State Readback

### 4.1 `ghostty_surface_read_text()` with selection

```c
ghostty_selection_s sel = {
    .top_left = {
        .tag = GHOSTTY_POINT_VIEWPORT,
        .coord = GHOSTTY_POINT_COORD_TOP_LEFT,
        .x = 0,
        .y = line_number,
    },
    .bottom_right = {
        .tag = GHOSTTY_POINT_VIEWPORT,
        .coord = GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
        .x = cols - 1,
        .y = line_number,
    },
    .rectangle = false,
};

ghostty_text_s text = {0};
bool ok = ghostty_surface_read_text(surface, sel, &text);
if (ok && text.text && text.text_len > 0) {
    // text.text is UTF-8, text.text_len is byte length
    // ...
    ghostty_surface_free_text(surface, &text);  // MUST free
}
```

### 4.2 `ghostty_surface_size()` for terminal dimensions

```c
ghostty_surface_size_s sz = ghostty_surface_size(surface);
// sz.columns, sz.rows — cell dimensions
```

**Source**: `poc-ghostty-real.m:525-558`

---

## 5. Build Requirements (macOS)

### 5.1 Source language

Must use Objective-C (`.m` extension) due to Foundation/AppKit dependency for NSApplication, NSWindow, NSView.

### 5.2 Compiler flags

```bash
cc -fobjc-arc \
    poc-ghostty-real.m \
    libhangul/hangul/hangulctype.c \
    libhangul/hangul/hangulinputcontext.c \
    libhangul/hangul/hangulkeyboard.c \
    libhangul/hangul/hanja.c \
    -I<ghostty-headers> \
    -I<libhangul> \
    -L<ghostty-lib> \
    -lghostty \
    -lz -lc++ \
    -framework Foundation \
    -framework AppKit \
    -framework CoreText \
    -framework CoreGraphics \
    -framework Metal \
    -framework QuartzCore \
    -framework CoreFoundation \
    -framework Security \
    -framework IOKit \
    -framework GameController \
    -framework UniformTypeIdentifiers \
    -framework IOSurface \
    -framework Carbon
```

### 5.3 Library size

`libghostty.a` is ~425MB (universal arm64+x86_64, debug symbols included).

**Source**: `build-poc.sh`

---

## 6. IME Pipeline — Confirmed Patterns

### 6.1 Three-phase processing

```
Phase 0: Global shortcuts (language toggle) — consumed, not forwarded
Phase 1: IME processKey(KeyEvent) → ImeResult
Phase 2: ImeResult → ghostty API calls
```

### 6.2 ImeResult struct (C implementation)

```c
typedef struct {
    const char* committed;     // UTF-8 committed text, NULL if none
    const char* preedit;       // UTF-8 preedit text, NULL if none
    bool forward_key;          // true if key should be forwarded to terminal
    const char* forward_desc;  // human-readable description (logging only)
    KeyEvent original_key;     // the original key event (for forwarding)
} ImeResult;
```

### 6.3 processKey behavior (confirmed by 22 test scenarios)

| Input | IME State | Result |
|-------|-----------|--------|
| Printable key, Korean mode | Empty | Feed to libhangul → preedit |
| Printable key, Korean mode | Composing | Feed to libhangul → may commit previous + new preedit |
| Backspace, Korean mode | Composing | `hangul_ic_backspace()` → reduced preedit |
| Backspace, Korean mode | Empty | forward_key = true |
| Space, Korean mode | Composing | FLUSH + forward space |
| Space, Korean mode | Empty | forward_key = true |
| Modifier key (Ctrl/Alt/Super) | Composing | FLUSH + forward key |
| Modifier key | Empty | forward_key = true |
| Special key (Enter/Esc/Tab/Arrow) | Composing | FLUSH + forward key |
| Special key | Empty | forward_key = true |
| Any key, Direct mode | — | committed = ASCII char, OR forward_key |

### 6.4 Modifier flush policy

**FLUSH (commit), NOT RESET (discard)** — for ALL modifiers and special keys.

Evidence: ibus-hangul and fcitx5-hangul both call `hangul_ic_flush()` (not `hangul_ic_reset()`) on Ctrl/Alt/Super.

**Source**: `poc-ghostty-real.m:276-288`

### 6.5 Language switch

```c
static ImeResult ime_set_language(ImeEngine* eng, int lang_id) {
    if (eng->active_language == lang_id) return (ImeResult){};  // no-op
    if (eng->active_language == LANG_KOREAN) {
        result = ime_flush(eng);  // commit pending composition
    }
    eng->active_language = lang_id;
    return result;
}
```

- Same-language = no-op (no flush, no state change)
- Switching away from Korean: flush composition
- Switching away from Direct: nothing to flush
- `forward_key` is always NULL from language switch

**Source**: `poc-ghostty-real.m:342-353`

### 6.6 Pane deactivate/reactivate

- **Deactivate**: flush composition + clear preedit overlay
- **Reactivate**: no-op (language mode preserved, HangulInputContext ready)

**Source**: `poc-ghostty-real.m:1019-1044`

---

## 7. Known Limitations

### 7.1 Left/Home arrow key crash

Left arrow and Home key trigger a crash in this pre-built libghostty version:

```
invalid enum value in terminal.stream.Stream.nextNonUtf8
```

The crash occurs when ghostty's VT parser processes the shell's escape sequence response to cursor movement. Right arrow works correctly.

**Tests affected**: #10 (Left arrow insertion), #13 (Home + compose)
**Workaround**: Right arrow (Test 2) verifies the flush-on-cursor-move behavior.
**Root cause**: Pre-built `libghostty.a` may be from an older ghostty version with this parser bug. Building from latest ghostty source may fix it.

### 7.2 Terminal readback timing

`ghostty_surface_read_text()` may return stale data if called too soon after key events. The PTY echo round-trip (key → cat → echo → ghostty VT parser) takes time.

**Mitigation**: Call `ghostty_app_tick()` 3-5 times with 10ms sleep between ticks before reading.

---

## 8. Test Results Summary

| Test | Description | Status |
|------|-------------|--------|
| 1 | r,k,s,r → 간ㄱ (syllable break) | PASS |
| 2 | Arrow during composition → flush + cursor move | PASS |
| 3 | Ctrl+C during composition → flush + forward | PASS |
| 4 | Enter during composition → flush + newline | PASS |
| 5 | Backspace chain: 간→가→ㄱ→empty→forward | PASS |
| 6 | Type "한글" → buffer accumulation | PASS |
| 7 | "한" + Space + "글" → "한 글" | PASS |
| 8 | "hello" in direct mode | PASS |
| 9 | Mixed "hi" + Korean "한글" | PASS |
| 10 | Left arrow insertion | SKIPPED (parser bug) |
| 11 | "테스트" → Backspace → "테스" | PASS |
| 12 | "한" → Enter → "글" (two lines) | PASS |
| 13 | Home + Korean before English | SKIPPED (parser bug) |
| 14 | Ctrl+C no composition → forward | PASS |
| 15 | Escape during composition → flush + forward | PASS |
| 16 | Tab during composition → flush + forward | PASS |
| 17 | Ctrl+D no composition → forward | PASS |
| 18 | Rapid syllable breaks r,k,s,k,s,k | PASS |
| 19 | Shift+R (ㄲ) + k → 까 → Enter | PASS |
| 20 | Language switch mid-composition | PASS |
| 21 | Empty backspace → forward | PASS |
| 22 | Pane deactivate/reactivate | PASS |
| 23 | "안녕하세요" → Enter → "Hello!" | PASS |
| 24 | Wide char cursor alignment "a가b" | PASS |

**Result: 22/24 pass, 2 skipped (libghostty VT parser bug, not IME code)**
