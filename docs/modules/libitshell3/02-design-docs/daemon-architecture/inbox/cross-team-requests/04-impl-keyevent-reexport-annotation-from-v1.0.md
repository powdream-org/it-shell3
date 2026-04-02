# KeyEvent File Annotation: Reflect Re-Export from libitshell3-ime

- **Date**: 2026-04-02
- **Source team**: impl
- **Source version**: libitshell3 Plan 8 verification
- **Source resolution**: Plan 8 Step 3 triage (SC-6)
- **Target docs**: daemon-architecture 02-state-and-types.md
- **Status**: open

---

## Context

Plan 8 verification found the spec annotates KeyEvent at `core/key_event.zig`
but no such file exists. KeyEvent is canonically defined in libitshell3-ime and
re-exported through `core/ime_engine.zig`:

```zig
pub const KeyEvent = ime_types.KeyEvent;
```

This pattern was chosen to avoid code duplication — KeyEvent has a single source
of truth in libitshell3-ime. Creating a separate `core/key_event.zig` file would
violate single-source-of-truth.

## Required Changes

1. **02-state-and-types.md**: Update KeyEvent annotation from
   `<<core/key_event.zig>>` to indicate re-export pattern, e.g.,
   `<<core/ime_engine.zig>>` with a note: "Re-exported from libitshell3-ime.
   Canonical definition in libitshell3-ime types."

## Summary Table

| Target Doc            | Section/Message     | Change Type       | Source Resolution |
| --------------------- | ------------------- | ----------------- | ----------------- |
| 02-state-and-types.md | KeyEvent annotation | Annotation update | SC-6 triage       |
