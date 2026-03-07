# IME Interface Contract v0.7 — Extensibility and Deployment

> **Version**: v0.7
> **Date**: 2026-03-07
> **Part of the IME Interface Contract v0.7. See [01-overview.md](01-overview.md) for the document index.**
> **Changes from v0.6**: See [Appendix I: Changes from v0.6](99-appendices.md#appendix-i-changes-from-v06)

## 7. Future Extensibility

### Candidate Support (Japanese/Chinese)

When Japanese (libkkc/libmozc) or Chinese (librime) engines are added, they need candidate list support. The design principle: **don't add candidate fields to ImeResult**.

**Why not ImeResult?**
- Korean/English (99% of keystrokes for v1) would carry an always-null `candidates` field.
- Candidate events are rare — triggered by explicit user action (Space in Japanese, candidate keys in Chinese), not every keystroke.
- Candidate list lifecycle is different from key processing: a list stays visible across multiple keystrokes (arrow navigation, page up/down).

> **Korean Hanja conversion is explicitly excluded.** Korean Hanja (Chinese character) conversion will not be supported in the Korean IME engine. The candidate callback mechanism below is reserved for future Chinese/Japanese engines only. This is a permanent design decision, not a deferral.

**Solution: Separate callback channel.**

```zig
// Future -- not implemented in v1
pub const CandidateEvent = union(enum) {
    show: CandidateList,    // display candidate panel
    update: CandidateList,  // update visible candidates (page change, cursor move)
    hide: void,             // hide candidate panel
};

pub const CandidateList = struct {
    candidates: []const Candidate,
    selected_index: usize,
    page_start: usize,
    page_size: usize,
};

pub const Candidate = struct {
    text: []const u8,       // UTF-8 candidate text
    comment: ?[]const u8,   // Optional annotation (e.g., reading, meaning)
};
```

The `ImeEngine` VTable would gain an optional callback:

```zig
// Future addition to VTable
setCandidateCallback: ?*const fn (
    ptr: *anyopaque,
    callback: ?*const fn (ctx: *anyopaque, event: CandidateEvent) void,
    ctx: ?*anyopaque,
) void,
```

Korean engine's `setCandidateCallback` implementation: no-op (never emits candidates). Japanese/Chinese engines set the callback and emit `CandidateEvent` when the user invokes candidate selection.

**Impact on v1**: Zero. The VTable field is `null`. No code path touches it.

> **European dead keys**: European dead key sequences (e.g., `'` + `e` = `é`) will be implemented as a separate engine (e.g., `"european_deadkey"`), NOT as a feature of direct mode. Direct mode must remain pure passthrough (HID → ASCII, zero composition state). This is a permanent design decision.

### Adding a New Language Engine

To add a new language (e.g., Japanese via libkkc):

1. Implement a struct with all `ImeEngine.VTable` functions.
2. Return an `ImeEngine` from a factory function.
3. Add canonical input method strings to the registry (e.g., `"japanese_romaji"`, `"japanese_kana"`).
4. Register the factory in libitshell3's engine registry (future Phase 7).
5. No changes to `KeyEvent`, `ImeResult`, or the processing pipeline.

---

## 8. C API Boundary

### Decision: libitshell3-ime Has No Public C API

libitshell3-ime is an **internal dependency** of libitshell3. It is statically linked into the libitshell3 library. External consumers interact with the combined library through `itshell3.h` only.

**Rationale:**
- libitshell3-ime is only consumed by libitshell3 (both Zig). No C FFI needed.
- The IME's key types (`KeyEvent`, `ImeResult`) are internal to the daemon. Clients never see them — they send raw HID keycodes over the wire protocol and receive preedit via FrameUpdate.
- Exposing a separate `itshell3_ime.h` would create two public APIs to maintain. YAGNI.

**If a standalone C API is ever needed** (e.g., another project wants to use the Korean IME), it can be added later. The `ImeEngine` vtable maps naturally to a C opaque handle + function pointers:

```c
// Hypothetical future itshell3_ime.h -- NOT for v1
typedef void* itshell3_ime_t;
typedef struct { /* ... */ } itshell3_ime_key_event_s;
typedef struct { /* ... */ } itshell3_ime_result_s;

itshell3_ime_t itshell3_ime_new(const char* input_method);
void itshell3_ime_free(itshell3_ime_t);
itshell3_ime_result_s itshell3_ime_process_key(itshell3_ime_t, itshell3_ime_key_event_s);
itshell3_ime_result_s itshell3_ime_flush(itshell3_ime_t);
void itshell3_ime_reset(itshell3_ime_t);
```

### What IS Public: itshell3.h

The public C API (`itshell3.h`) exposes preedit through callbacks, not through IME types:

```c
// In itshell3.h -- the preedit callback the host app receives
typedef void (*itshell3_preedit_cb)(
    uint32_t pane_id,
    const char* text,       // UTF-8 preedit text, NULL if cleared
    size_t text_len,
    uint32_t cursor_x,      // OBSOLETE — see note below
    uint32_t cursor_y,      // OBSOLETE — see note below
    void* userdata
);

// In itshell3.h -- the input method change callback
typedef void (*itshell3_input_method_cb)(
    uint32_t pane_id,
    const char* input_method,  // canonical string, e.g. "korean_2set", "direct"
    void* userdata
);
```

> **Revision note (v0.7)**: The `cursor_x` and `cursor_y` parameters of `itshell3_preedit_cb` are obsolete under the "preedit is cell data" model established in protocol v0.8. The server calls `ghostty_surface_preedit()` which injects preedit into cell data at the terminal cursor position — cursor coordinates are ghostty-internal and never exposed to the client. When the C API is implemented, this callback's purpose should be re-evaluated: with preedit rendering via cell data, the callback may serve only non-rendering uses (status bar, accessibility) with a simplified signature of `(pane_id, text, text_len, userdata)`. The `cursor_x` and `cursor_y` parameters will be removed at that time.

The host app never knows about `ImeEngine`, `KeyEvent`, or `ImeResult`. It sends raw key events via the wire protocol and receives preedit/mode updates via callbacks.

---

## 9. Session Persistence

### What is Saved (Per-Session)

The IME state is stored at the session level, not the pane level. All panes within a session share the same engine and the same `input_method`.

```json
{
    "session_id": 1,
    "name": "my-session",
    "ime": {
        "input_method": "korean_2set",
        "keyboard_layout": "qwerty"
    },
    "panes": [
        { "pane_id": 1 },
        { "pane_id": 2 }
    ]
}
```

Two fields at session level:
- `input_method`: canonical protocol string (e.g., `"korean_2set"`). No reverse-mapping needed.
- `keyboard_layout`: physical keyboard layout (e.g., `"qwerty"`). Orthogonal to `input_method`. Both axes of the engine's configuration live at the same scope.

Panes carry no IME state. They do not have per-pane `input_method` or `keyboard_layout` fields.

### What is NOT Saved

- Preedit text (in-progress composition). On restore, all sessions start with empty composition. Nobody expects to resume mid-syllable after a daemon restart.
- Engine-internal state (libhangul's jamo stack). Reconstructing this is not feasible and not useful.

### On Restore

Create a new `HangulImeEngine` with the saved `input_method` string: `HangulImeEngine.init(allocator, saved_input_method)`. All panes in the session share this engine.
