# IME Interface Contract v1.0-r9 — Extensibility and Deployment

> **Version**: v1.0-r9
> **Date**: 2026-03-14
> **Part of the IME Interface Contract v1.0-r9. See [01-overview.md](01-overview.md) for the document index.**
> **Changes from v0.8**: Sections renumbered per-document sequential (CTR-04). See [Appendix K: Changes from v0.8](99-appendices.md#appendix-k-changes-from-v08).

## 1. Future Extensibility

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

## 2. C API Boundary

libitshell3-ime exports a Zig API only; it has no public C header. It is an internal dependency of libitshell3, statically linked into the daemon binary. See [daemon design doc 02 §5](../../../../../libitshell3/02-design-docs/daemon/draft/v1.0-r3/02-integration-boundaries.md#5-c-api-surface-design) for the full C API surface design.

---

## 3. Session Persistence

The engine constructor accepts a canonical `input_method` string: `HangulImeEngine.init(allocator, input_method)`. This is the only engine-internal field needed to reconstruct an engine on session restore. Composition state is never persisted — the engine always starts with empty composition.

Session persistence procedures (save/restore timing, flush-on-save policy, persistence schema) are defined in [daemon design doc 02 §4.1](../../../../../libitshell3/02-design-docs/daemon/draft/v1.0-r3/02-integration-boundaries.md#41-per-session-imeengine-lifecycle) and daemon doc 04 §8.
